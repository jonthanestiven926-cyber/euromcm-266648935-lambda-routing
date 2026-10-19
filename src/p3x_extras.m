function [ex, attr] = p3x_extras(run, cfg, P)
%P3X_EXTRAS Supplement metrics + mutually-exclusive attribution (E2 protocol).
% All values recomputed from the raw exported ledgers (events / windows / req);
% missing sets stay NaN (never beautified to 0).
% Primary-cause rule (00_PROTOCOL.md sec.2): rejected -> budget; not rejected but
% c_final>d -> deadline; unfinished within drain limit -> horizon; on-time -> none.
% Associated factors are recorded separately and NEVER double-counted.
req = run.req;
N = numel(req);
wins = run.windows;
ev = run.events;
q_target = P.q_target;
T_arr = cfg.T_arr;
C = cfg.C;

% ---- request fields ----
st = cell(N, 1); a = zeros(N, 1); d = zeros(N, 1); cfin = nan(N, 1);
q = zeros(N, 1); ontime = false(N, 1); rej = false(N, 1); degr = false(N, 1);
fmiss = false(N, 1);
for i = 1:N
    st{i} = req(i).status;
    a(i) = req(i).a; d(i) = req(i).d; cfin(i) = req(i).c_final;
    q(i) = req(i).q_real; ontime(i) = logical(req(i).on_time);
    rej(i) = logical(req(i).rejected); degr(i) = logical(req(i).degraded);
    fmiss(i) = logical(req(i).fb_missing);
end

% ---- stage-1 queue wait = stage-1 window start - arrival ----
sw = nan(N, 1);
if ~isempty(wins)
    for w = 1:numel(wins)
        if wins(w).stage == 1
            sw(wins(w).req) = wins(w).start - a(wins(w).req);
        end
    end
end
ex.stage1_wait_mean = local_mean(sw);
ex.stage1_wait_p95 = local_p95(sw);
ex.stage1_wait_max = local_max(sw);
ex.n_with_stage1_window = sum(~isnan(sw));

% ---- utilization / concurrency (windows clipped to [0, T_arr]) ----
ov = 0;
if ~isempty(wins)
    for w = 1:numel(wins)
        s0 = max(wins(w).start, 0);
        s1 = min(wins(w).stop, T_arr);
        if s1 > s0
            ov = ov + (s1 - s0);
        end
    end
end
ex.utilization_over_0_to_T_arr = ov / (C * T_arr);
ex.utilized_machine_seconds_in_horizon = ov;
ex.max_concurrency_in_horizon = local_maxconc(wins, 0, T_arr);
ex.max_concurrency_full_drain = local_maxconc(wins, -inf, inf);
ex.capacity_C = C;
ex.T_arr_s = T_arr;

% ---- terminal states (mutually exclusive, exhaustive) ----
ex.N_arr = N;
ex.n_completed = sum(strcmp(st, 'completed'));
ex.n_late = sum(strcmp(st, 'completed_late'));
ex.n_rejected_budget = sum(strcmp(st, 'rejected_budget'));
ex.n_drain_violation = sum(strcmp(st, 'drain_violation'));
ex.n_undrained_violation = sum(strcmp(st, 'undrained_violation'));
ex.n_completed_total = ex.n_completed + ex.n_late;
ex.status_sum_check = ex.n_completed + ex.n_late + ex.n_rejected_budget + ...
    ex.n_drain_violation + ex.n_undrained_violation;

% ---- quality ----
ex.quality_total = sum(q);
ex.quality_per_arrival = ex.quality_total / N;
if ex.n_completed_total == 0
    ex.quality_per_completed = NaN;
else
    ex.quality_per_completed = ex.quality_total / ex.n_completed_total;
end
ex.quality_target_met_per_arrival = sum(strcmp(st, 'completed') & q >= q_target) / N;
ex.quality_target_met_count = sum(strcmp(st, 'completed') & q >= q_target);
ex.q_target = q_target;

% ---- conditional response time (never treat rejections as zero latency) ----
comp = ~rej & ~isnan(cfin);
rtv = cfin(comp) - a(comp);
ex.n_completed_any = sum(comp);
ex.resp_mean_conditional = local_mean(rtv);
ex.resp_p95_conditional = local_p95(rtv);
ex.resp_max_conditional = local_max(rtv);

% ---- budget / carbon from raw ledgers ----
ex.B = run.metrics.B;
ex.budget_used = run.metrics.budget_used;
ex.budget_remaining = run.metrics.budget_remaining;
ex.budget_remaining_frac = run.metrics.budget_remaining / run.metrics.B;
ex.rho_total = run.metrics.rho_total;
ex.carbon_total = run.carbon.total;
ex.carbon_per_arrival = run.carbon.total / N;

% ---- event-derived counters (recomputable from events.csv) ----
etypes = cell(0, 1); edet = cell(0, 1); ereq = zeros(0, 1);
if ~isempty(ev)
    etypes = {ev.type}'; edet = {ev.detail}'; ereq = [ev.req]';
end
ex.n_defer_events = sum(strcmp(etypes, 'DEFER'));
ex.n_revision_failed_budget = sum(strcmp(etypes, 'REVISION_FAILED_BUDGET'));
ex.n_upgrade_dropped_deadline = sum(strcmp(etypes, 'UPGRADE_DROPPED_DEADLINE'));
ex.n_degraded_budget = sum(strcmp(etypes, 'DEGRADED_BUDGET'));
ex.n_reject_routing_overhead = sum(strcmp(etypes, 'REJECTED_BUDGET') & contains_local(edet, 'routing overhead'));
ex.n_reject_plan_unaffordable = sum(strcmp(etypes, 'REJECTED_BUDGET') & contains_local(edet, 'plan unaffordable'));
ex.n_reject_migration = sum(strcmp(etypes, 'REJECTED_BUDGET') & contains_local(edet, 'migration'));
ex.n_rejected_budget_events = sum(strcmp(etypes, 'REJECTED_BUDGET'));

% ---- attribution table (one row per request; single primary cause) ----
attr = struct('request_id', {}, 'terminal_status', {}, 'primary_cause', {}, ...
    'primary_reason_detail', {}, 'stage1_wait_s', {}, 'assoc_capacity_queue', {}, ...
    'assoc_degraded', {}, 'assoc_revision_failed_budget', {}, ...
    'assoc_upgrade_dropped', {}, 'assoc_fb_missing', {}, 'on_time', {}, ...
    'c_final_s', {}, 'deadline_s', {}, 'q_realized', {});
for i = 1:N
    if strcmp(st{i}, 'rejected_budget')
        cause = 'budget';
        det = 'rejected: see events.csv REJECTED_BUDGET row';
        k = find(ereq == i & strcmp(etypes, 'REJECTED_BUDGET'), 1, 'last');
        if ~isempty(k), det = ['rejected: ' edet{k}]; end
    elseif strcmp(st{i}, 'completed_late')
        cause = 'deadline';
        det = 'c_final > d (late completion; see associated factors)';
    elseif strcmp(st{i}, 'completed')
        cause = 'none';
        det = 'completed on time';
    else
        cause = 'horizon';
        det = ['not finished within drain rule: ' st{i}];
    end
    assocQ = ~isnan(sw(i)) && sw(i) > 1e-9;
    assocRevFail = any(ereq == i & strcmp(etypes, 'REVISION_FAILED_BUDGET'));
    assocDrop = any(ereq == i & strcmp(etypes, 'UPGRADE_DROPPED_DEADLINE'));
    attr(end+1, 1) = struct('request_id', i, 'terminal_status', st{i}, ...
        'primary_cause', cause, 'primary_reason_detail', det, 'stage1_wait_s', sw(i), ...
        'assoc_capacity_queue', assocQ, 'assoc_degraded', degr(i), ...
        'assoc_revision_failed_budget', assocRevFail, 'assoc_upgrade_dropped', assocDrop, ...
        'assoc_fb_missing', fmiss(i), 'on_time', ontime(i), 'c_final_s', cfin(i), ...
        'deadline_s', d(i), 'q_realized', q(i));
end
ex.n_assoc_capacity_queue_late = sum(strcmp(st, 'completed_late') & ~isnan(sw) & sw > 1e-9);
ex.n_late_without_queue = ex.n_late - ex.n_assoc_capacity_queue_late;
ex.attribution_rule = ['primary cause mutually exclusive: budget (rejected) / deadline ', ...
    '(late) / horizon (drain) / none (on time); associated factors listed separately'];
end

function v = local_mean(x)
x = x(~isnan(x));
if isempty(x), v = NaN; else, v = mean(x); end
end

function v = local_p95(x)
x = sort(x(:));
x = x(~isnan(x));
if isempty(x), v = NaN; return; end
k = max(1, min(numel(x), ceil(0.95 * numel(x))));
v = x(k);
end

function v = local_max(x)
x = x(~isnan(x));
if isempty(x), v = NaN; else, v = max(x); end
end

function m = local_maxconc(wins, t0, t1)
m = 0;
if isempty(wins), return; end
ev = zeros(0, 2);
for w = 1:numel(wins)
    if wins(w).stop <= t0 || wins(w).start >= t1
        continue;
    end
    ev(end+1, :) = [wins(w).start, 1];
    ev(end+1, :) = [wins(w).stop, -1];
end
if isempty(ev), return; end
ev = sortrows(ev, [1, 2]);   % ends (-1) before starts (+1) at equal times
cur = 0;
for k = 1:size(ev, 1)
    cur = cur + ev(k, 2);
    if cur > m, m = cur; end
end
end

function tf = contains_local(cells, pat)
tf = false(numel(cells), 1);
for k = 1:numel(cells)
    tf(k) = ~isempty(strfind(cells{k}, pat)); %#ok<STREMP>
end
end
