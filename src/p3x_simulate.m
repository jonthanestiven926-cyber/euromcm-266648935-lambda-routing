function run = p3x_simulate(traj, P, carbon, policyName, opts)
%P3X_SIMULATE Isolated copy of p3_system/p3_simulate.m for the P3 supplement.
% See DIFF_LIST.md for the exhaustive diff list. Preserved unchanged: the
% S5r2/R2 numeric deadline repairs (stage-2 feasibility drop at feedback and the
% end-to-end slack reservation when deferring batch jobs). Differences:
%   D1 function name
%   D2 opts.signal_fn injection in carbon_signal (policy sees ONLY the issued
%      forecast; the environment keeps true actuals for scoring)
%   D3 obs.carbon carries the release/source audit fields
%   D4 decisions log carries issue_s / latest_available / max_source_index
%   D5 opts.max_defer_s: independent wait upper limit; the deadline d = a+W_batch
%      is NEVER changed by this knob (0 = immediately schedulable)
%   D6 run.meta merges opts.meta_extra (predictor/information class/config hash)
%   D7 invariants record max_defer_s and the signal source
%P3_SIMULATE Event-driven finite-capacity causal scheduling simulation.
% CONSTRUCTED_SCENARIO/DEVELOPMENT only. Independent exogenous trajectory:
% every random draw lives in 'traj' (precomputed); this simulator and the
% strategies never call RNG, so policy branching cannot drift random streams.
% INFORMATION BOUNDARY: decision functions receive only decision-time visible
% inputs (see p3_policy); true quality / future arrivals / future carbon
% actuals stay in the environment and are used for SCORING only.
% Capacity: at any t the number of executing requests <= P.C (per-request
% concurrent occupancy; wait states hold no slot). Jobs:
%   stage-1 job  : tau(action)+tau_verify, cost rho(action)+rho_verify
%   stage-2 job  : tau(action2)+tau_verify, cost rho(action2)+rho_verify
% Revision (upgrade/extra) is only created at the feedback event, i.e. at
% stage-1 end + P.delta_fb -- hard causality (S1 sec.1).
% Full-cost rule: a revision produces a second verified answer, so it pays
% stage-2 + a second verification ("初始+额外+校验全部成本").
if nargin < 5
    opts = struct();
end
if ~isfield(opts,'replay'), opts.replay = []; end
if ~isfield(opts,'audit'), opts.audit = false; end
if ~isfield(opts,'carbon_sched'), opts.carbon_sched = false; end
if ~isfield(opts,'label'), opts.label = policyName; end
if ~isfield(opts,'B'), opts.B = []; end
if ~isfield(opts,'forcePlan'), opts.forcePlan = []; end
if ~isfield(opts,'offline_diagnostic'), opts.offline_diagnostic = false; end
if ~isfield(opts,'signal_fn'), opts.signal_fn = []; end                 % D2
if ~isfield(opts,'max_defer_s'), opts.max_defer_s = inf; end            % D5
if ~isfield(opts,'meta_extra'), opts.meta_extra = struct(); end         % D6

N = numel(traj.a);
if isempty(opts.B)
    B = P.B_per_request * N;
else
    B = opts.B;
end
seg = P.segment_seconds;

% ---- carbon series: safe train/validation artifacts only (or explicit
% override for hand-computed micro instances) ----
if isfield(opts, 'gActual') && ~isempty(opts.gActual)
    gActual = opts.gActual(:);
    K = numel(gActual);
    cn = zeros(K,1);
else
    switch P.carbon_source
        case 'validation', base_g = carbon.g_val;
        case 'train', base_g = carbon.g_train;
        otherwise, error('p3:carbon', 'unknown carbon source %s', P.carbon_source);
    end
    off = P.carbon_offset_segments;
    K = ceil((max(traj.a) + P.W_batch + 2*seg)/seg) + 2;
    if off + K > numel(base_g)
        error('p3:carbon', 'not enough safe carbon segments (%d needed)', off+K);
    end
    gActual = base_g(off+1:off+K);
    if isfield(traj,'c_noise') && ~isempty(traj.c_noise)
        cn = traj.c_noise(:);
        if numel(cn) < K, cn(end+1:K,1) = 0; end
        cn = cn(1:K);
    else
        cn = zeros(K,1);
    end
end
gForecast = gActual + cn;
if isfield(opts, 'gForecast') && ~isempty(opts.gForecast)
    gForecast = opts.gForecast(:);
    if numel(gForecast) ~= K
        error('p3:carbon', 'gForecast override length mismatch');
    end
end
segStart = (0:K-1)' * seg;
segEnd = segStart + seg;

% ---- request state ----
st_action0 = zeros(N,1);      % 0 none, 1 light, 2 strong
st_action2 = zeros(N,1);      % 0 none, 1 strong-upgrade, 2 extra
st_revised = false(N,1);
st_degraded = false(N,1);
st_rejected = false(N,1);
st_failed = zeros(N,1);
st_dropD = zeros(N,1);      % S5r2: revisions dropped by causal deadline feasibility
st_cint = nan(N,1);
st_cfinal = nan(N,1);
st_rho_route = zeros(N,1);
st_mig = zeros(N,1);
st_rho1 = zeros(N,1);
st_rho2 = zeros(N,1);
st_rho_v = zeros(N,1);
st_job1 = zeros(N,1);
st_job2 = zeros(N,1);
st_status = cell(N,1);
st_status(:) = {'pending'};

% ---- jobs (processing segments) ----
jb_req = zeros(0,1); jb_stage = zeros(0,1); jb_release = zeros(0,1);
jb_dur = zeros(0,1); jb_deadline = zeros(0,1); jb_rho = zeros(0,1);
jb_kind = cell(0,1); jb_started = false(0,1); jb_startT = zeros(0,1);
jb_endT = zeros(0,1); jb_done = false(0,1); jb_machine = zeros(0,1);
jb_defer = nan(0,1);

% ---- events: 1 arrival, 2 feedback, 3 job_end, 4 defer-start ----
evT = zeros(0,1); evType = zeros(0,1); evReq = zeros(0,1); evJob = zeros(0,1);

mf = zeros(1, P.C);          % machine-free times (P.C = maximum capacity)
C_sched = [0, P.C];           % active-capacity step schedule (S4 F4)
if isfield(P, 'C_schedule') && ~isempty(P.C_schedule)
    C_sched = P.C_schedule;
    if size(C_sched,2) ~= 2 || C_sched(1,1) ~= 0 || any(diff(C_sched(:,1)) <= 0)
        error('p3:cfg', 'P.C_schedule must be Nx2 with t0=0 and strictly increasing times');
    end
    if max(C_sched(:,2)) > P.C
        error('p3:cfg', 'P.C must be the maximum scheduled capacity');
    end
end

% ---- ledgers for independent recomputation ----
evl = struct('time',{},'type',{},'req',{},'detail',{},'rho_delta',{},'budget_remaining',{});
bled = struct('req',{},'component',{},'rho_delta',{},'budget_remaining',{});
wins = struct('req',{},'stage',{},'start',{},'stop',{},'rho',{});
decLog = struct('time',{},'req',{},'phase',{},'action0',{},'revise',{},'action2',{},'reason',{}, ...
    'issue_s',{},'latest_available',{},'max_source_index',{});   % D4 template
auditObs = {};
state = struct('phat_counts', zeros(3,2), 'n_fb', 0, 'change_count', 0);
Brem = B;
% S5r2 G1 repair: worst-case stage-2 service requirement incl. verification;
% used to causally reserve end-to-end slack when deferring batch jobs
maxDur2 = max(P.tau_strong, P.tau_extra) + P.tau_verify;

% ============================ main event loop ============================
for i = 1:N
    add_event(traj.a(i), 1, i, 0);
end
guard = 0;
while ~isempty(evT)
    guard = guard + 1;
    if guard > 500000
        error('p3:sim', 'event loop guard tripped');
    end
    tt = min(evT);
    sel = find(evT == tt);
    selT = evType(sel); selR = evReq(sel); selJ = evJob(sel);
    keep = true(numel(evT),1);
    keep(sel) = false;
    evT = evT(keep); evType = evType(keep); evReq = evReq(keep); evJob = evJob(keep);
    for pass = [3 2 4 1]
        kk = find(selT == pass);
        for jj = kk(:)'
            switch pass
                case 3
                    on_job_end(tt, selJ(jj), selR(jj));
                case 2
                    on_feedback(tt, selR(jj));
                case 4
                    % defer marker: scheduling pass below performs the assignment
                case 1
                    on_arrival(tt, selR(jj));
            end
        end
    end
    schedule_pass(tt);
end

% ============================ finalize ============================
drain_limit = max(traj.a) + P.W_batch + (P.tau_strong + P.tau_verify) + P.delta_fb + 1;
for i = 1:N
    if st_rejected(i)
        continue;
    end
    if isnan(st_cfinal(i))
        st_status{i} = 'undrained_violation';
    elseif st_cfinal(i) > drain_limit
        st_status{i} = 'drain_violation';
    elseif st_cfinal(i) <= traj.d(i) + 1e-9
        st_status{i} = 'completed';
    else
        st_status{i} = 'completed_late';
    end
end

q_real = zeros(N,1);
for i = 1:N
    if st_rejected(i)
        q_real(i) = 0;
    elseif st_revised(i) && st_action2(i) == 1
        q_real(i) = traj.q_strong(i);
    elseif st_revised(i) && st_action2(i) == 2
        if st_action0(i) == 2
            baseq = traj.q_strong(i);
        else
            baseq = traj.q_light(i);
        end
        q_real(i) = min(1, baseq + traj.gain(i));
    elseif st_action0(i) == 2
        q_real(i) = traj.q_strong(i);
    else
        q_real(i) = traj.q_light(i);
    end
end

reqOut = struct('id',{},'a',{},'d',{},'gtype',{},'x',{},'action0',{},'revised',{}, ...
    'action2',{},'degraded',{},'rejected',{},'failed_attempts',{},'c_int',{}, ...
    'c_final',{},'resp_time',{},'on_time',{},'status',{},'qhat_light',{}, ...
    'qhat_strong',{},'q_real',{},'truth_unsat',{},'verdict_unsat',{},'fb_missing',{}, ...
    'rho_route',{},'rho_stage1',{},'rho_stage2',{},'rho_verify',{},'rho_total',{});
for i = 1:N
    if st_rejected(i)
        rt = NaN;
    else
        rt = st_cfinal(i) - traj.a(i);
    end
    reqOut(end+1,1) = struct('id',i,'a',traj.a(i),'d',traj.d(i),'gtype',traj.gtype{i}, ...
        'x',traj.x(i),'action0',act1name(st_action0(i)),'revised',st_revised(i), ...
        'action2',act2name(st_action2(i)),'degraded',st_degraded(i),'rejected',st_rejected(i), ...
        'failed_attempts',st_failed(i),'c_int',st_cint(i),'c_final',st_cfinal(i), ...
        'resp_time',rt,'on_time',~st_rejected(i) && ~isnan(st_cfinal(i)) && st_cfinal(i) <= traj.d(i)+1e-9, ...
        'status',st_status{i},'qhat_light',traj.qhat_light(i),'qhat_strong',traj.qhat_strong(i), ...
        'q_real',q_real(i),'truth_unsat',logical(traj.truth_unsat(i)), ...
        'verdict_unsat',logical(traj.verdict_unsat(i)),'fb_missing',logical(traj.fb_missing(i)), ...
        'rho_route',st_rho_route(i),'rho_stage1',st_rho1(i),'rho_stage2',st_rho2(i), ...
        'rho_verify',st_rho_v(i),'rho_total',st_rho_route(i)+st_rho1(i)+st_rho2(i)+st_rho_v(i)+st_mig(i));
end

[Ctot, segRateSeconds, segContrib] = p3_carbon_index(wins, gActual, seg);

m = struct();
m.N_arr = N;
m.n_completed = sum(strcmp(st_status, 'completed'));
m.n_completed_on_time = m.n_completed;   % S5r2 F3: explicit on-time alias
m.n_late = sum(strcmp(st_status, 'completed_late'));
m.n_completed_total = m.n_completed + m.n_late;  % S5r2 F3: on-time + completed_late
m.n_rejected = sum(st_rejected);
m.n_drain_violation = sum(strcmp(st_status, 'drain_violation')) + sum(strcmp(st_status, 'undrained_violation'));
m.n_degraded = sum(st_degraded);
m.rate_completed = m.n_completed / N;
m.rate_late = m.n_late / N;
m.rate_rejected = m.n_rejected / N;
m.rate_drain_violation = m.n_drain_violation / N;
m.n_failed_revision_attempts = sum(st_failed);
m.n_upgrade_dropped_deadline = sum(st_dropD);  % S5r2 G1: feasibility-dropped revisions
m.quality_total = sum(q_real);
m.quality_mean_per_arrival = m.quality_total / N;
comp = ~st_rejected & ~isnan(st_cfinal);
rtv = st_cfinal(comp) - traj.a(comp);
m.n_completed_any = sum(comp);
m.resp_mean = mean_no_nan(rtv);
m.resp_p95 = pct_local(rtv, 95);
m.resp_max = max_no_nan(rtv);
m.rho_route = sum(st_rho_route);
m.rho_stage1 = sum(st_rho1);
m.rho_stage2 = sum(st_rho2);
m.rho_verify = sum(st_rho_v);
m.rho_mig = sum(st_mig);
m.rho_total = m.rho_route + m.rho_stage1 + m.rho_stage2 + m.rho_verify + m.rho_mig;
m.B = B;
m.budget_used = B - Brem;
m.budget_remaining = Brem;
m.strong_share = sum(st_action0 == 2 | st_action2 == 1) / N;
m.carbon_total = Ctot;
m.carbon_per_arrival = Ctot / N;
types = {'int','bat'};
tnames = {'interactive','batch'};
for k = 1:2
    selT2 = strcmp(traj.gtype, types{k});
    sub = struct();
    sub.n = sum(selT2);
    sub.rate_completed = sum(selT2 & strcmp(st_status,'completed')) / max(1, sub.n);
    sub.rate_late = sum(selT2 & strcmp(st_status,'completed_late')) / max(1, sub.n);
    sub.rate_completed_total = sum(selT2 & (strcmp(st_status,'completed') | strcmp(st_status,'completed_late'))) / max(1, sub.n);
    sub.rate_rejected = sum(selT2 & st_rejected) / max(1, sub.n);
    sub.quality_mean_per_arrival = sum(q_real(selT2)) / max(1, sub.n);
    selC = selT2 & comp;
    sub.resp_mean = mean_no_nan(st_cfinal(selC) - traj.a(selC));
    sub.resp_p95 = pct_local(st_cfinal(selC) - traj.a(selC), 95);
    sub.carbon_per_arrival = Ctot * 0; %#ok<NASGU> % filled below from windows
    m.(tnames{k}) = sub;
end
% per-type carbon from windows
for k = 1:2
    selT2 = strcmp(traj.gtype, types{k});
    if isempty(wins)
        ct = 0;
    else
        wsel = wins(selT2([wins.req]));
        if isempty(wsel)
            ct = 0;
        else
            ct = p3_carbon_index(wsel, gActual, seg);
        end
    end
    m.(tnames{k}).carbon_per_arrival = ct / max(1, m.(tnames{k}).n);
end

run = struct();
run.meta = struct('policy', policyName, 'label', opts.label, ...
    'scheduler', pick(opts.carbon_sched), 'offline_diagnostic', opts.offline_diagnostic, ...
    'generated_at', p3_now_iso(), 'scenario_label', P.scenario_label, ...
    'carbon_source', tern(isfield(opts,'gActual') && ~isempty(opts.gActual), 'explicit_micro_series', P.carbon_source));
if isfield(traj, 'meta') && isfield(traj.meta, 'seed')
    run.meta.seed = traj.meta.seed;
else
    run.meta.seed = NaN;
end
% D6: supplement metadata (predictor, information class, config hash, ...)
if isfield(opts, 'meta_extra') && ~isempty(opts.meta_extra)
    fnX = fieldnames(opts.meta_extra);
    for kX = 1:numel(fnX)
        run.meta.(fnX{kX}) = opts.meta_extra.(fnX{kX});
    end
end
run.P = P;
run.req = reqOut;
run.events = evl;
run.budget = bled;
run.windows = wins;
run.decisions = decLog;
run.carbon = struct('g_actual', gActual, 'g_forecast', gForecast, 'seg_start', segStart, ...
    'seg_rate_seconds', segRateSeconds, 'seg_contrib', segContrib, 'total', Ctot, ...
    'segment_seconds', seg);
run.metrics = m;
run.policy_state = state;
run.audit = unique(auditObs);
run.invariants = struct('drain_rule', 'simulate-until-empty (identical for all strategies)', ...
    'drain_limit', drain_limit, 'capacity', P.C, 'capacity_schedule', C_sched, ...
    'capacity_rule', ['jobs running at a capacity drop continue to completion (no preemption); ', ...
        'a new job may start only while the number currently running is below the active ', ...
        'capacity C(t) (admission control)'], 'budget', B, ...
    'unit_time', 's', 'unit_resource', 'relative (rho_light=1, not kWh)', ...
    'unit_quality', '[0,1] constructed correctness fraction', ...
    'unit_carbon', 'relative-resource*gCO2/kWh index (not gCO2)', ...
    'max_defer_s', opts.max_defer_s, ...   % D7
    'signal_source', tern(isempty(opts.signal_fn), 'legacy_gActual_plus_noise', ...
        'injected_causal_signal_fn'));    % D7

% ============================ nested functions ============================
    function c = cap_at(tt2)
        idx = find(C_sched(:,1) <= tt2 + 1e-12, 1, 'last');
        c = C_sched(idx, 2);
    end

    function add_event(tt2, ty, rq, jb)
        evT(end+1,1) = tt2;
        evType(end+1,1) = ty;
        evReq(end+1,1) = rq;
        evJob(end+1,1) = jb;
    end

    function log_event(tt2, ty, rq, detail, drho)
        evl(end+1,1) = struct('time', tt2, 'type', ty, 'req', rq, 'detail', detail, ...
            'rho_delta', drho, 'budget_remaining', Brem);
    end

    function ok = charge(rho, component, i)
        if rho <= 0
            ok = true;
            % zero-amount rows are still written so that every decision point
            % (including failed attempts) leaves an audit trace (S4 F6)
            bled(end+1,1) = struct('req', i, 'component', component, 'rho_delta', 0, ...
                'budget_remaining', Brem);
            return;
        end
        if Brem >= rho - 1e-9
            Brem = Brem - rho;
            ok = true;
            drho = rho;
        else
            ok = false;
            drho = 0;
        end
        bled(end+1,1) = struct('req', i, 'component', component, 'rho_delta', drho, ...
            'budget_remaining', Brem);
    end

    function [gh, latest, msi] = carbon_signal(tt2)
        % D2: injected causal signal -- the ONLY carbon channel visible to the
        % policy. The true series (gActual) stays in the environment for scoring.
        if ~isempty(opts.signal_fn)
            [gh, latest, msi] = opts.signal_fn(tt2);
            if numel(gh) ~= K || any(~isfinite(gh(:)))
                error('p3x:SignalInvalid', 'signal_fn returned invalid vector at t=%.3f', tt2);
            end
            gh = gh(:);
            return;
        end
        latest = NaN; msi = NaN;
        gh = gForecast;
        lag = P.carbon_delta_h * 3600;
        pub = find(segStart <= tt2 - lag);
        if ~isempty(pub)
            gh(pub) = gActual(pub);
        end
        if P.carbon_naive
            if isempty(pub)
                base_val = gActual(1);
            else
                base_val = gActual(pub(end));
            end
            gh(:) = base_val;
        end
        kmax = floor((tt2 + P.carbon_h * 3600) / seg) + 1;
        if kmax < 1
            kmax = 1;
        end
        if kmax < K
            gh(kmax+1:end) = gh(kmax);
        end
    end

    function v = seg_integral(s0, s1, gh)
        v = 0;
        for kk2 = 1:K
            ov = min(s1, segEnd(kk2)) - max(s0, segStart(kk2));
            if ov > 0
                v = v + gh(kk2) * ov;
            end
        end
    end

    function s_star = carbon_optimal_start(tt2, ls, dur)
        cand = [tt2; ls];
        kb = find(segStart > tt2 & segStart < ls);
        cand = unique([cand; segStart(kb)]);
        gh = carbon_signal(tt2);
        best = inf;
        s_star = cand(1);
        for cc = cand(:)'
            val = seg_integral(cc, cc + dur, gh);
            if val < best - 1e-12
                best = val;
                s_star = cc;
            end
        end
    end

    function j = add_job(i, stage, release, dur, deadline, rho, kind)
        jb_req(end+1,1) = i;
        jb_stage(end+1,1) = stage;
        jb_release(end+1,1) = release;
        jb_dur(end+1,1) = dur;
        jb_deadline(end+1,1) = deadline;
        jb_rho(end+1,1) = rho;
        jb_kind{end+1,1} = kind;
        jb_started(end+1,1) = false;
        jb_startT(end+1,1) = NaN;
        jb_endT(end+1,1) = NaN;
        jb_done(end+1,1) = false;
        jb_machine(end+1,1) = 0;
        jb_defer(end+1,1) = NaN;
        j = numel(jb_req);
    end

    function [cost, dur, rhoStage, rhoVer] = plan1(act)
        if strcmp(act, 'strong')
            rhoStage = P.rho_strong;
            dur = P.tau_strong + P.tau_verify;
        else
            rhoStage = P.rho_light;
            dur = P.tau_light + P.tau_verify;
        end
        rhoVer = P.rho_verify;
        cost = rhoStage + rhoVer;
    end

    function obs = build_obs(tt2, i, phase)
        req = struct('id', i, 'a', traj.a(i), 'd', traj.d(i), 'gtype', traj.gtype{i}, ...
            'x', traj.x(i), 'qhat_light', traj.qhat_light(i), 'qhat_strong', traj.qhat_strong(i), ...
            'qhat_gain', traj.qhat_gain(i), 'u_route', traj.u_route(i));
        if strcmp(phase, 'feedback')
            fb = struct('id', i, 'tfb', tt2, 'verdict_unsat', logical(traj.verdict_unsat(i)), ...
                'received', ~logical(traj.fb_missing(i)));
        else
            fb = struct('id', i, 'tfb', NaN, 'verdict_unsat', false, 'received', false);
        end
        [ghObs, latestObs, msiObs] = carbon_signal(tt2);   % D3
        carb = struct('g_hat', ghObs, 'seg_start', segStart, ...
            'delta_h', P.carbon_delta_h, 't_last_published', tt2 - P.carbon_delta_h*3600, ...
            'forecast_horizon_h', P.carbon_h, 'issue_s', tt2, ...
            'latest_available', latestObs, 'max_source_index', msiObs);
        sys = struct('budget_remaining', Brem, 'busy_machines', sum(mf > tt2), ...
            'n_machines', cap_at(tt2), 'n_queued', sum(~jb_started & ~jb_done & jb_release <= tt2));
        obs = struct('t', tt2, 'phase', phase, 'req', req, 'feedback', fb, ...
            'carbon', carb, 'system', sys);
    end

    function s = obs_fields(obs)
        s = sprintf('top[%s] req[%s] feedback[%s] system[%s] carbon[%s]', ...
            strjoin(sort(fieldnames(obs))', '|'), ...
            strjoin(sort(fieldnames(obs.req))', '|'), ...
            strjoin(sort(fieldnames(obs.feedback))', '|'), ...
            strjoin(sort(fieldnames(obs.system))', '|'), ...
            strjoin(sort(fieldnames(obs.carbon))', '|'));
    end

    function on_arrival(tt2, i)
        obs = build_obs(tt2, i, 'arrival');
        if isempty(opts.forcePlan)
            [dec, state] = p3_policy(policyName, obs, P, state, 'arrival', opts.replay);
        else
            dec = struct('action0', opts.forcePlan(i).action0, 'revise', false, ...
                'action2', 'strong', 'intent', false, 'reason', 'FORCED');
        end
        if opts.audit
            auditObs{end+1,1} = obs_fields(obs);
        end
        decLog(end+1,1) = struct('time', tt2, 'req', i, 'phase', 'arrival', ...
            'action0', dec.action0, 'revise', false, 'action2', 'none', 'reason', dec.reason, ...
            'issue_s', obs.carbon.issue_s, 'latest_available', obs.carbon.latest_available, ...
            'max_source_index', obs.carbon.max_source_index);   % D4
        okR = charge(P.rho_route, 'routing_arrival', i);
        if ~okR
            st_rejected(i) = true;
            st_status{i} = 'rejected_budget';
            log_event(tt2, 'REJECTED_BUDGET', i, 'routing overhead unaffordable', 0);
            return;
        end
        st_rho_route(i) = st_rho_route(i) + P.rho_route;
        % cross-location transfer / migration cost (L1): a request served by a
        % location other than its home pays rho_mig as a real charged event
        if isfield(traj, 'loc_home') && ~isempty(traj.loc_home) && ...
                isfield(P, 'loc_id') && ~isempty(P.loc_id) && traj.loc_home(i) ~= P.loc_id
            okM = charge(P.rho_mig, 'migration_transfer', i);
            if ~okM
                st_rejected(i) = true;
                st_status{i} = 'rejected_budget';
                log_event(tt2, 'REJECTED_BUDGET', i, 'migration transfer unaffordable', 0);
                return;
            end
            st_mig(i) = st_mig(i) + P.rho_mig;
            log_event(tt2, 'MIGRATION_TRANSFER', i, ...
                sprintf('home=%d served_at=%d cost=%.3f', traj.loc_home(i), P.loc_id, P.rho_mig), ...
                P.rho_mig);
        end
        act = dec.action0;
        [costS, durS, rhoStageS, rhoVerS] = plan1('strong');
        [costL, durL, rhoStageL, rhoVerL] = plan1('light'); %#ok<ASGLU>
        if strcmp(act, 'strong') && Brem < costS - 1e-9
            if Brem >= costL - 1e-9
                act = 'light';
                st_degraded(i) = true;
                log_event(tt2, 'DEGRADED_BUDGET', i, 'strong plan unaffordable; downgraded to light', 0);
            else
                act = '';
            end
        elseif strcmp(act, 'light') && Brem < costL - 1e-9
            act = '';
        end
        if isempty(act)
            st_rejected(i) = true;
            st_status{i} = 'rejected_budget';
            log_event(tt2, 'REJECTED_BUDGET', i, 'plan unaffordable', 0);
            return;
        end
        if strcmp(act, 'strong')
            st_action0(i) = 2;
            rhoStage = rhoStageS; rhoVer = rhoVerS; dur1 = durS;
        else
            st_action0(i) = 1;
            rhoStage = rhoStageL; rhoVer = rhoVerL; dur1 = durL;
        end
        ok1 = charge(rhoStage, 'stage1', i);
        ok2 = charge(rhoVer, 'verify1', i);
        if ~(ok1 && ok2)
            error('p3:sim', 'budget race at arrival of request %d', i);
        end
        st_rho1(i) = st_rho1(i) + rhoStage;
        st_rho_v(i) = st_rho_v(i) + rhoVer;
        j = add_job(i, 1, tt2, dur1, traj.d(i), rhoStage + rhoVer, traj.gtype{i});
        st_job1(i) = j;
        log_event(tt2, 'ARRIVAL', i, sprintf('action0=%s', act), rhoStage + rhoVer);
    end

    function on_feedback(tt2, i)
        obs = build_obs(tt2, i, 'feedback');
        if isempty(opts.forcePlan)
            [dec, state] = p3_policy(policyName, obs, P, state, 'feedback', opts.replay);
        else
            dec = struct('action0', 'light', 'revise', opts.forcePlan(i).revise, ...
                'action2', opts.forcePlan(i).action2, 'intent', false, 'reason', 'FORCED');
        end
        if opts.audit
            auditObs{end+1,1} = obs_fields(obs);
        end
        decLog(end+1,1) = struct('time', tt2, 'req', i, 'phase', 'feedback', ...
            'action0', 'none', 'revise', logical(dec.revise), ...
            'action2', tern(logical(dec.revise), dec.action2, 'none'), 'reason', dec.reason, ...
            'issue_s', obs.carbon.issue_s, 'latest_available', obs.carbon.latest_available, ...
            'max_source_index', obs.carbon.max_source_index);   % D4
        log_event(tt2, 'FEEDBACK', i, sprintf('verdict_unsat=%d', traj.verdict_unsat(i)), 0);
        if ~dec.revise
            return;
        end
        if strcmp(dec.action2, 'extra')
            rhoStage2 = P.rho_extra;
            dur2 = P.tau_extra + P.tau_verify;
        else
            rhoStage2 = P.rho_strong;
            dur2 = P.tau_strong + P.tau_verify;
        end
        rhoVer2 = P.rho_verify;
        % decision overhead is charged at EVERY decision point, including
        % failed attempts and rejections ("失败尝试/拒绝已发生开销计入")
        okR = charge(P.rho_route, 'routing_feedback', i);
        if okR
            st_rho_route(i) = st_rho_route(i) + P.rho_route;
        end
        if ~okR || Brem < rhoStage2 + rhoVer2 - 1e-9
            st_failed(i) = st_failed(i) + 1;
            log_event(tt2, 'REVISION_FAILED_BUDGET', i, ...
                'revision attempt failed (budget); incurred overhead kept', 0);
            return;
        end
        % S5r2 G1 repair (strict causal feasibility at feedback): create the
        % revision only if it can still finish by its deadline under the
        % CURRENT state; earliest causal start bound = max(now, earliest
        % machine-free time); requirement = stage-2 service + verification.
        % No future outcome is consulted. If infeasible the upgrade is
        % DROPPED: the stage-1 answer stands (on-time) instead of late.
        est2 = max(tt2, min(mf));
        if est2 + dur2 > traj.d(i) + 1e-9
            st_dropD(i) = st_dropD(i) + 1;
            log_event(tt2, 'UPGRADE_DROPPED_DEADLINE', i, ...
                sprintf('est_start %.3f + dur2 %.3f > deadline %.3f; upgrade dropped (stage-1 stands)', ...
                est2, dur2, traj.d(i)), 0);
            return;
        end
        charge(rhoStage2, 'stage2', i);
        charge(rhoVer2, 'verify2', i);
        st_rho2(i) = st_rho2(i) + rhoStage2;
        st_rho_v(i) = st_rho_v(i) + rhoVer2;
        st_revised(i) = true;
        if strcmp(dec.action2, 'extra')
            st_action2(i) = 2;
        else
            st_action2(i) = 1;
        end
        j = add_job(i, 2, tt2, dur2, traj.d(i), rhoStage2 + rhoVer2, traj.gtype{i});
        st_job2(i) = j;
        log_event(tt2, 'REVISE', i, sprintf('action2=%s', dec.action2), rhoStage2 + rhoVer2);
    end

    function on_job_end(tt2, j, i)
        jb_done(j) = true;
        if jb_stage(j) == 1
            st_cint(i) = tt2;
            st_cfinal(i) = tt2;
            if traj.fb_missing(i)
                log_event(tt2, 'JOB_END', i, 'stage1 done; feedback missing (no revision possible)', 0);
            else
                log_event(tt2, 'JOB_END', i, 'stage1 done', 0);
            end
        else
            st_cfinal(i) = tt2;
            log_event(tt2, 'JOB_END', i, 'stage2 done', 0);
        end
    end

    function schedule_pass(tt2)
        % capacity-drop rule (S4 F4, admission control): jobs running at a
        % drop CONTINUE to completion (no preemption); a NEW job may start only
        % while the number currently running is below the ACTIVE capacity C(t)
        Cact = cap_at(tt2);
        run_ct = sum(mf > tt2);
        free = find(mf <= tt2);
        if isempty(free)
            return;
        end
        cand = find(~jb_started & ~jb_done & jb_release <= tt2);
        if isempty(cand)
            return;
        end
        [~, ord] = sortrows([jb_deadline(cand), jb_release(cand), cand(:)]);
        cand = cand(ord);
        for j = cand(:)'
            if isempty(free) || run_ct >= Cact
                break;
            end
            ls = jb_deadline(j) - jb_dur(j);
            if opts.carbon_sched && strcmp(jb_kind{j}, 'bat')
                % S5r2 G1 repair (causal end-to-end slack): a deferred batch
                % job can still cascade (feedback delay + stage-2 service incl.
                % verification) after its stage-1 answer, so the deferral
                % window reserves delta_fb + worst-case stage-2 duration.
                % Only parameters and this job's own known service/deadline
                % enter the bound; no future outcome is consulted.
                ls_e2e = jb_deadline(j) - (jb_dur(j) + P.delta_fb + maxDur2);
                % D5: independent wait upper limit (max_defer_s). The deadline
                % d = a + W_batch is NEVER touched by this knob; only the
                % voluntarily deferred start is capped at arrival + max_defer_s.
                % max_defer_s = 0 -> ls_upper <= arrival <= tt2 -> no deferral
                % (immediately schedulable), completion still only needs d.
                if isfinite(opts.max_defer_s)
                    ls_upper = min(ls_e2e, traj.a(jb_req(j)) + opts.max_defer_s);
                else
                    ls_upper = ls_e2e;
                end
                if isnan(jb_defer(j))
                    if tt2 < ls_upper - 1e-9
                        s_star = carbon_optimal_start(tt2, ls_upper, jb_dur(j));
                        if s_star > tt2 + 1e-9
                            jb_defer(j) = s_star;
                            add_event(s_star, 4, jb_req(j), j);
                            log_event(tt2, 'DEFER', jb_req(j), ...
                                sprintf('carbon-optimal start at %.3f', s_star), 0);
                            continue;
                        end
                    end
                else
                    if tt2 < jb_defer(j) - 1e-9 && tt2 < ls - 1e-9
                        continue;
                    end
                end
            end
            run_ct = run_ct + 1;
            m = free(1);
            free(1) = [];
            mf(m) = tt2 + jb_dur(j);
            jb_started(j) = true;
            jb_startT(j) = tt2;
            jb_endT(j) = tt2 + jb_dur(j);
            jb_machine(j) = m;
            add_event(jb_endT(j), 3, jb_req(j), j);
            wins(end+1,1) = struct('req', jb_req(j), 'stage', jb_stage(j), ...
                'start', tt2, 'stop', tt2 + jb_dur(j), 'rho', jb_rho(j));
            log_event(tt2, 'JOB_START', jb_req(j), ...
                sprintf('stage=%d machine=%d', jb_stage(j), m), 0);
            % feedback is scheduled from the ACTUAL stage-1 completion time
            % (job end), never from the arrival time: queued requests must not
            % receive feedback before their stage-1 answer exists
            if jb_stage(j) == 1 && ~traj.fb_missing(jb_req(j))
                add_event(tt2 + jb_dur(j) + P.delta_fb, 2, jb_req(j), 0);
            end
        end
    end
end

% ============================ local helpers ============================
function s = act1name(a)
switch a
    case 1, s = 'light';
    case 2, s = 'strong';
    otherwise, s = 'none';
end
end

function s = act2name(a)
switch a
    case 1, s = 'strong';
    case 2, s = 'extra';
    otherwise, s = 'none';
end
end

function v = tern(c, a, b)
if c
    v = a;
else
    v = b;
end
end

function s = pick(tf)
if tf
    s = 'carbon_defer_batch';
else
    s = 'edf_immediate';
end
end

function v = pct_local(x, p)
x = sort(x(:));
x = x(~isnan(x));
if isempty(x)
    v = NaN;
    return;
end
k = max(1, min(numel(x), ceil(p/100 * numel(x))));
v = x(k);
end

function v = mean_no_nan(x)
x = x(~isnan(x));
if isempty(x)
    v = NaN;
else
    v = mean(x);
end
end

function v = max_no_nan(x)
x = x(~isnan(x));
if isempty(x)
    v = NaN;
else
    v = max(x);
end
end
