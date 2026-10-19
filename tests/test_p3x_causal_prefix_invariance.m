function test_p3x_causal_prefix_invariance(rootDir, run_id)
%TEST_P3X_CAUSAL_PREFIX_INVARIANCE Acceptance A2/A3/A8.
% (a) runs the four frozen E1 dev variants and checks the release/source audit
%     on every decision row (issue_s / latest_available / max_source_index);
% (b) simulator-level future-perturbation invariance: changing NOT-YET-PUBLISHED
%     future actuals must leave every decision and forecast issuance unchanged
%     up to the perturbation visibility time (only the invisible prefix is
%     required to be invariant -- once the future becomes published, later
%     decisions MAY change);
% (c) perturbing values beyond the last target changes NOTHING in the whole run;
% (d) oracle is explicitly separated as IDEAL_INFORMATION (future read audited).
if nargin < 2, run_id = '20261018_171608_963_p3_supplement'; end
outRoot = fullfile(rootDir, '06_results', run_id);
devDir = fullfile(outRoot, 'dev_acceptance', 'test_p3x_causal_prefix_invariance');
carbon = p3_load_carbon(rootDir);
history = [carbon.g_train(:); carbon.g_val(:)];

% ---------------- (a) E1 dev artifact set (frozen params, dev seed) ----------
base = struct('block', 'E1', 'seed', 20261018, 'offset', 96, 'first_index', 1441, ...
    'strategy', 'adaptive_gain', 'lambda', 0.1, 'C', 4, 'budget_mode', 'scaled', ...
    'B_per_request', 1.5, 'T_arr', 7200, 'W_batch', 1800, 'd_int', 10, ...
    'lag_s', 3600, 'rho_route', 0, 'bias', 0, 'carbon_sigma', 0, 'demand_M', 1, ...
    'note', 'E1 dev acceptance (dev seed 20261018; NOT a final-matrix run)');
variants = {
    struct('case_id', 'DEV_E1_w96_imm', 'carbon_sched', false, 'predictor', 'n/a(unused)')
    struct('case_id', 'DEV_E1_w96_persist', 'carbon_sched', true, 'predictor', 'persistence')
    struct('case_id', 'DEV_E1_w96_seasonal', 'carbon_sched', true, 'predictor', 'seasonal')
    struct('case_id', 'DEV_E1_w96_oracle', 'carbon_sched', true, 'predictor', 'oracle')};
for k = 1:numel(variants)
    cfg = base;
    cfg.case_id = variants{k}.case_id;
    cfg.carbon_sched = variants{k}.carbon_sched;
    cfg.predictor = variants{k}.predictor;
    [run, ~, rec] = p3x_run_one(cfg, rootDir, fullfile(devDir, cfg.case_id));
    assert(strcmp(rec.status, 'success'), 'p3x:DevRun', 'dev run %s not successful', cfg.case_id);
    dl = run.decisions;
    assert(~isempty(dl), 'p3x:Audit', 'no decisions recorded');
    assert(all(isfinite([dl.latest_available])) && all(isfinite([dl.max_source_index])) && ...
        all(isfinite([dl.issue_s])), 'p3x:Audit', 'release/source audit fields must be non-empty');
    iss = read_issuance(fullfile(devDir, cfg.case_id, 'forecast_issuance.csv'));
    assert(~isempty(iss), 'p3x:Audit', 'forecast issuance audit missing');
    if strcmp(cfg.predictor, 'oracle')
        assert(strcmp(run.meta.information_class, 'IDEAL_INFORMATION'), ...
            'p3x:OracleLabel', 'oracle must be labelled IDEAL_INFORMATION');
        assert(any(iss.msi > iss.latest), 'p3x:OracleLabel', ...
            'oracle future read must be visible in the source audit');
    else
        assert(all(iss.msi <= iss.latest), 'p3x:FutureSource', ...
            'causal predictor read beyond the publication frontier');
        if cfg.carbon_sched
            assert(~strcmp(run.meta.information_class, 'IDEAL_INFORMATION'), ...
                'p3x:Label', 'causal predictor must not carry the oracle label');
        end
    end
    fprintf('  dev artifact %s OK (N=%d, issuances=%d)\n', cfg.case_id, rec.N_arr, numel(iss));
end

% ---------------- (b,c) simulator-level perturbation invariance --------------
P = p3_default_params();
P.T_arr = 1800; P.lambda = 0.1; P.C = 4; P.W_batch = 1800; P.d_int = 10;
P.carbon_sigma = 0; P.demand_M = 1;
traj = p3_gen_trajectory(P, 20261018);
firstIndex = 1441;
K = ceil((P.T_arr + P.W_batch + 2 * P.segment_seconds) / P.segment_seconds) + 2;
lastTarget = firstIndex + K - 1;
T_cut = 3600;   % at t=3600 the frontier is firstIndex-1: nothing from the
                % perturbed range [firstIndex, end] is published yet
modes = {'persistence', 'seasonal'};
for m = 1:numel(modes)
    mode = modes{m};
    [runA, issA] = local_run(traj, P, carbon, history, firstIndex, K, mode);
    H2 = history;
    H2(firstIndex:end) = H2(firstIndex:end) + 1000;      % unpublished future actuals
    [runB, issB] = local_run(traj, P, carbon, H2, firstIndex, K, mode);
    H3 = history;
    H3(lastTarget + 1:end) = H3(lastTarget + 1:end) + 1000;   % never-read region
    [runC, issC] = local_run(traj, P, carbon, H3, firstIndex, K, mode);

    assert(strcmp(dec_sig(runA, T_cut), dec_sig(runB, T_cut)), 'p3x:FutureLeak', ...
        '%s: decisions up to %ds changed when unpublished future actuals changed', mode, T_cut);
    assert(strcmp(ev_sig(runA, T_cut), ev_sig(runB, T_cut)), 'p3x:FutureLeak', ...
        '%s: events up to %ds changed when unpublished future actuals changed', mode, T_cut);
    assert(strcmp(iss_sig(issA, T_cut), iss_sig(issB, T_cut)), 'p3x:FutureLeak', ...
        '%s: forecast issuance up to %ds changed', mode, T_cut);

    assert(strcmp(dec_sig(runA, inf), dec_sig(runC, inf)), 'p3x:FutureLeak', ...
        '%s: decisions changed when the never-read region changed', mode);
    assert(strcmp(ev_sig(runA, inf), ev_sig(runC, inf)), 'p3x:FutureLeak', ...
        '%s: events changed when the never-read region changed', mode);
    assert(strcmp(iss_sig(issA, inf), iss_sig(issC, inf)), 'p3x:FutureLeak', ...
        '%s: issuance changed when the never-read region changed', mode);
    fprintf('  %s perturbation invariance OK (T_cut=%ds, N=%d)\n', mode, T_cut, traj.N);
end
fprintf('P3X_CAUSAL_PREFIX_INVARIANCE_PASS\n');
end

function [run, iss] = local_run(traj, P, carbon, history, firstIndex, K, mode)
[sigfh, getlog] = p3x_make_signal(history, firstIndex, K, 3600, mode, 0, 0, traj.c_noise(:));
simopts = struct('signal_fn', sigfh, 'B', 1.5 * traj.N, 'carbon_sched', true, ...
    'label', ['DEV_INVARIANT_' mode], 'offline_diagnostic', false, ...
    'max_defer_s', inf, 'gActual', history(firstIndex : firstIndex + K - 1));
run = p3x_simulate(traj, P, carbon, 'adaptive_gain', simopts);
iss = getlog();
end

function s = dec_sig(run, tmax)
s = '';
for i = 1:numel(run.decisions)
    d = run.decisions(i);
    if d.time <= tmax
        s = [s sprintf('%.6f|%d|%s|%s|%d|%s;', d.time, d.req, d.phase, ...
            d.action0, d.revise, d.action2)]; %#ok<AGROW>
    end
end
end

function s = ev_sig(run, tmax)
s = '';
for i = 1:numel(run.events)
    e = run.events(i);
    if e.time <= tmax
        s = [s sprintf('%.6f|%s|%d|%s;', e.time, e.type, e.req, e.detail)]; %#ok<AGROW>
    end
end
end

function s = iss_sig(iss, tmax)
s = '';
for i = 1:numel(iss.issue_s)
    if iss.issue_s(i) <= tmax
        s = [s sprintf('%.6f|%d|%d;', iss.issue_s(i), iss.latest_available(i), ...
            iss.max_source_index(i))]; %#ok<AGROW>
    end
end
end

function iss = read_issuance(f)
iss = struct('issue_s', [], 'latest', [], 'msi', []);
if exist(f, 'file') ~= 2, return; end
T = readtable(f, 'TextType', 'string');
iss.issue_s = T.issue_s;
iss.latest = T.latest_available;
iss.msi = T.max_source_index;
end
