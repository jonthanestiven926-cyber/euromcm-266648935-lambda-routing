function test_p3x_demand_prefix(rootDir, run_id)
%TEST_P3X_DEMAND_PREFIX Acceptance A6 + 01_PROTOCOL_AMENDMENT_X1 (X1-2).
% E2B doubling uses a Poisson(2*lambda) BASE STREAM with independent
% Bernoulli(0.5) marks (p3x_demand_marks, dedicated substream, fixed per seed):
%   demand_M=2 = full stream  = Poisson(2*lambda)
%   demand_M=1 = marked subset = Poisson(lambda)   (thinning theorem, CV=1)
% The kept stream is a NESTED SUBSET (same base-stream index -> identical arrival
% time / features / potential outcomes, pairable); the extra d2 requests are never
% paired. Even-index extraction is FORBIDDEN: it would give Erlang-2 interarrivals
% (CV=1/sqrt(2)=0.707) and conflate demand growth with regularity.
if nargin < 2, run_id = '20261018_171608_963_p3_supplement'; end
outRoot = fullfile(rootDir, '06_results', run_id);
devDir = fullfile(outRoot, 'dev_acceptance', 'test_p3x_demand_prefix');

baseCfg = struct('block', 'E2B', 'seed', 20261018, 'offset', 96, 'first_index', 1441, ...
    'strategy', 'adaptive_gain', 'carbon_sched', false, 'predictor', 'n/a(unused)', ...
    'lambda', 0.1, 'C', 4, 'T_arr', 900, 'W_batch', 300, 'd_int', 10, 'lag_s', 3600, ...
    'rho_route', 0, 'bias', 0, 'carbon_sigma', 0, 'note', ...
    'E2B demand-pair dev acceptance (dev seed; Bernoulli-marked nested subset)');
c1 = baseCfg; c1.case_id = 'DEV_E2B_d1_scaled'; c1.demand_M = 1;
c1.budget_mode = 'scaled'; c1.B_per_request = 1.5;
c2 = baseCfg; c2.case_id = 'DEV_E2B_d2_scaled'; c2.demand_M = 2;
c2.budget_mode = 'scaled'; c2.B_per_request = 1.5;
c3 = baseCfg; c3.case_id = 'DEV_E2B_d2_fixed'; c3.demand_M = 2;
c3.budget_mode = 'fixed_abs'; c3.B_abs = '1.5*N1(seed)';

[run1, ~, rec1] = p3x_run_one(c1, rootDir, fullfile(devDir, c1.case_id));
[run2, ~, rec2] = p3x_run_one(c2, rootDir, fullfile(devDir, c2.case_id));
[run3, ~, rec3] = p3x_run_one(c3, rootDir, fullfile(devDir, c3.case_id));
assert(strcmp(rec1.status, 'success') && strcmp(rec2.status, 'success') && ...
    strcmp(rec3.status, 'success'), 'p3x:DevRun', 'E2B dev runs failed');

% ---- regenerate the shared exogenous base stream + fixed Bernoulli marks ----
P = p3_default_params();
P.T_arr = 900; P.lambda = 0.1; P.C = 4; P.W_batch = 300; P.d_int = 10;
P.carbon_sigma = 0; P.demand_M = 2; P.rho_route = 0;
base = p3_gen_trajectory(P, 20261018);
N2 = base.N;
marks = p3x_demand_marks(N2, 20261018);
idx = find(marks);
N1 = numel(idx);
assert(N1 == sum(marks), 'p3x:DemandPair', 'N1 must be the marked count (random per seed)');
assert(N1 < N2, 'p3x:DemandPair', 'thinning must keep a strict subset');

% ---- nested subset identity (arrival / deadline / features / potentials) ----
assert(rec1.N_arr == N1 && rec2.N_arr == N2 && rec3.N_arr == N2, ...
    'p3x:DemandPair', 'N must match the marked subset / full base stream');
for j = 1:N1
    r1 = run1.req(j);
    r2 = run2.req(idx(j));
    assert(abs(r1.a - r2.a) < 1e-12 && abs(r1.d - r2.d) < 1e-12 && ...
        abs(r1.x - r2.x) < 1e-12, 'p3x:DemandPair', ...
        'shared request %d differs in arrival/deadline/features', j);
    assert(abs(r1.qhat_light - r2.qhat_light) < 1e-12 && ...
        abs(r1.qhat_strong - r2.qhat_strong) < 1e-12, 'p3x:DemandPair', ...
        'shared request %d differs in potential quality estimates', j);
end

% ---- d1 arrival sequence is a SUBSET of d2 (nested, same base indices) ------
a1 = [run1.req.a]';
a2 = [run2.req.a]';
assert(all(ismember(a1, a2)), 'p3x:DemandPair', 'd1 arrivals must be a subset of d2 arrivals');
assert(isequal(a1, base.a(idx)), 'p3x:DemandPair', 'd1 must equal the marked subset of the base stream');

% ---- single-sample consistency check (NOT a distribution proof): the thinning
% theorem gives Poisson(lambda)/Exp-1 interarrivals; this dev-seed CV only shows
% the realized sample is consistent with it and inconsistent with Erlang-2 0.707 ----
Pl = p3_default_params();
Pl.T_arr = 20000; Pl.lambda = 0.1; Pl.C = 4; Pl.W_batch = 300; Pl.d_int = 10;
Pl.carbon_sigma = 0; Pl.demand_M = 2; Pl.rho_route = 0;
baseL = p3_gen_trajectory(Pl, 20261018);
mkL = p3x_demand_marks(baseL.N, 20261018);
aL = baseL.a(mkL);
dt = diff(aL);
cv = std(dt) / mean(dt);
assert(cv > 0.85 && cv < 1.20, 'p3x:DemandCV', ...
    'marked d1 stream must have CV~1 (Exp), got %.3f (Erlang-2 would be 0.707)', cv);
assert(abs(mean(dt) - 10) < 1.5, 'p3x:DemandCV', ...
    'd1 mean interarrival must stay ~1/lambda=10s, got %.3f', mean(dt));
% contrast: even-index extraction would be Erlang-2 (kept only as evidence)
aE = baseL.a(2:2:end);
cvE = std(diff(aE)) / mean(diff(aE));
assert(cvE < 0.85, 'p3x:DemandCV', 'even-index contrast should show the CV=0.707 defect, got %.3f', cvE);

% ---- budget rules: d1 scaled == d1 fixed (deduped), d2 scaled vs d2 fixed ----
assert(abs(run1.metrics.B - 1.5 * N1) < 1e-9, 'p3x:DemandBudget', 'd1 budget must be 1.5*N1(seed)');
assert(abs(run2.metrics.B - 1.5 * N2) < 1e-9, 'p3x:DemandBudget', 'd2_scaled budget must be 1.5*N2');
assert(abs(run3.metrics.B - 1.5 * N1) < 1e-9, 'p3x:DemandBudget', ...
    'd2_fixed budget must equal the realized d1 budget 1.5*N1(seed)');
assert(~strcmp(rec1.config_hash, rec2.config_hash) && ~strcmp(rec2.config_hash, rec3.config_hash) && ...
    ~strcmp(rec1.config_hash, rec3.config_hash), 'p3x:ConfigHash', ...
    'the three E2B configs must hash differently');

% ---- frozen matrix: E2B has exactly 3 unique conditions x 8 seeds = 24 rows ----
T = readtable(fullfile(fileparts(mfilename('fullpath')), 'run_matrix.csv'), 'TextType', 'string');
e2b = T(strcmp(T.block, 'E2B'), :);
assert(height(e2b) == 24, 'p3x:Matrix', 'E2B must have 24 rows (3 unique x 8 seeds), got %d', height(e2b));
assert(numel(unique(e2b.case_id)) == 3, 'p3x:Matrix', 'E2B must have exactly 3 unique conditions');
assert(~any(strcmp(e2b.case_id, 'E2B_d1_fixed')), 'p3x:Matrix', ...
    '(d1,fixed) must be deduplicated into (d1,scaled), never an extra run');

% ---- report ----
hdr = {'case_id','demand_M','thinning_rule','N_arr','N1_marked','N2_base', ...
    'budget_B','budget_used','budget_remaining','config_hash'};
rows = {
    c1.case_id, '1', 'Bernoulli(0.5) marked subset of Poisson(2*lambda)', ...
        sprintf('%d', N1), sprintf('%d', N1), sprintf('%d', N2), ...
        sprintf('%.17g', run1.metrics.B), sprintf('%.17g', run1.metrics.budget_used), ...
        sprintf('%.17g', run1.metrics.budget_remaining), rec1.config_hash
    c2.case_id, '2', 'Poisson(2*lambda) full stream', ...
        sprintf('%d', N2), sprintf('%d', N1), sprintf('%d', N2), ...
        sprintf('%.17g', run2.metrics.B), sprintf('%.17g', run2.metrics.budget_used), ...
        sprintf('%.17g', run2.metrics.budget_remaining), rec2.config_hash
    c3.case_id, '2', 'Poisson(2*lambda) full stream', ...
        sprintf('%d', N2), sprintf('%d', N1), sprintf('%d', N2), ...
        sprintf('%.17g', run3.metrics.B), sprintf('%.17g', run3.metrics.budget_used), ...
        sprintf('%.17g', run3.metrics.budget_remaining), rec3.config_hash};
cols = cell(1, numel(hdr));
for j = 1:numel(hdr)
    cols{j} = rows(:, j);
end
p3_write_csv(fullfile(devDir, 'demand_pair_report.csv'), hdr, cols);
fprintf('  demand pair OK: N1=%d (marked) N2=%d, CV(d1)=%.3f, B(d1)=B(d2_fixed)=%.4f\n', ...
    N1, N2, cv, run1.metrics.B);
fprintf('P3X_DEMAND_PREFIX_PASS\n');
end
