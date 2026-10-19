function test_p3x_attribution(rootDir, run_id)
%TEST_P3X_ATTRIBUTION Acceptance A5 + task conservation / budget / deadline micro
% examples with TRUE non-zero negative cases, and the preserved R2 numeric
% deadline repair (stage-2 feasibility drop at feedback).
if nargin < 2, run_id = '20261018_171608_963_p3_supplement'; end
outRoot = fullfile(rootDir, '06_results', run_id);
devDir = fullfile(outRoot, 'dev_acceptance', 'test_p3x_attribution');
carbon = p3_load_carbon(rootDir);
P = p3_default_params();
P.carbon_source = 'validation';

% =============== micro 1: conservation + exact budget (hand-checked) =========
traj = p3x_micro_traj([0; 2; 5], [100; 100; 100], 'int');
fp = force_light(3);
run = p3x_simulate(traj, P, carbon, 'adaptive_gain', struct('forcePlan', fp, ...
    'B', 10, 'gActual', 200 * ones(16, 1), 'label', 'DEV_micro_conservation'));
assert(abs(run.metrics.budget_used - 3.3) < 1e-9, 'p3x:MicroBudget', ...
    '3 light requests must cost exactly 3*(rho_light+rho_verify)=3.3, got %.12g', ...
    run.metrics.budget_used);
assert(run.metrics.n_completed == 3 && run.metrics.n_rejected == 0, ...
    'p3x:MicroConservation', 'all three micro requests must complete');
assert(abs(run.metrics.quality_total - 1.5) < 1e-9, 'p3x:MicroQuality', ...
    'quality total must be 3*0.5=1.5');
assert(numel(run.windows) == 3, 'p3x:MicroConservation', 'one window per completed request');
p3_validate_run(run, P);
fprintf('  micro1 conservation/budget OK (budget_used=%.12g)\n', run.metrics.budget_used);

% =============== micro 2: TRUE non-zero budget negative ======================
traj = p3x_micro_traj([0; 2; 5], [100; 100; 100], 'int');
fp = force_light(3);
run = p3x_simulate(traj, P, carbon, 'adaptive_gain', struct('forcePlan', fp, ...
    'B', 2.5, 'gActual', 200 * ones(16, 1), 'label', 'DEV_micro_budget_negative'));
assert(run.metrics.n_rejected == 1 && run.metrics.n_completed == 2, ...
    'p3x:MicroNegative', 'budget 2.5 must reject exactly the third request');
assert(abs(run.metrics.budget_used - 2.2) < 1e-9, 'p3x:MicroNegative', ...
    'budget used must be exactly 2.2');
[ex, attr] = p3x_extras(run, cfg_micro(), P);
assert(strcmp(attr(3).primary_cause, 'budget'), 'p3x:Attribution', ...
    'rejected request must be attributed to budget');
assert(contains_local(attr(3).primary_reason_detail, 'plan unaffordable'), ...
    'p3x:Attribution', 'rejection detail must name the unaffordable plan');
assert(ex.n_reject_plan_unaffordable == 1, 'p3x:Attribution', 'plan-unaffordable count must be 1');
p3_validate_run(run, P);
fprintf('  micro2 budget negative OK (1 rejected, %.12g used)\n', run.metrics.budget_used);

% =============== micro 3: capacity queue -> late, deadline attribution =======
traj = p3x_micro_traj([0; 0; 0], [1.5; 1.5; 1.5], 'int');
fp = force_light(3);
P1 = P; P1.C = 1;
run = p3x_simulate(traj, P1, carbon, 'adaptive_gain', struct('forcePlan', fp, ...
    'B', 10, 'gActual', 200 * ones(16, 1), 'label', 'DEV_micro_deadline_negative'));
assert(strcmp(run.req(1).status, 'completed'), 'p3x:MicroDeadline', 'first job on time');
assert(strcmp(run.req(2).status, 'completed_late') && strcmp(run.req(3).status, 'completed_late'), ...
    'p3x:MicroDeadline', 'queued jobs must be completed_late (hand-checked 2.2s/3.3s > 1.5s)');
[ex, attr] = p3x_extras(run, cfg_micro(), P1);
assert(strcmp(attr(2).primary_cause, 'deadline') && strcmp(attr(3).primary_cause, 'deadline'), ...
    'p3x:Attribution', 'late completions must be attributed to deadline');
assert(attr(2).assoc_capacity_queue && attr(3).assoc_capacity_queue, ...
    'p3x:Attribution', 'capacity queueing must be listed as an associated factor');
assert(~attr(1).assoc_capacity_queue, 'p3x:Attribution', 'no queue factor without waiting');
assert(abs(ex.stage1_wait_mean - (0 + 1.1 + 2.2) / 3) < 1e-9, 'p3x:MicroWait', ...
    'stage1 waits must be 0/1.1/2.2 s');
p3_validate_run(run, P1);
fprintf('  micro3 deadline negative OK (1 on time, 2 late)\n');

% =============== micro 4: R2 revision-feasibility repair preserved ==========
traj = p3x_micro_traj(0, 1.5, 'int');
fp = struct('action0', {{'light'}}, 'revise', {{true}}, 'action2', {{'strong'}});
run = p3x_simulate(traj, P, carbon, 'adaptive_gain', struct('forcePlan', fp, ...
    'B', 10, 'gActual', 200 * ones(16, 1), 'label', 'DEV_micro_revision_drop'));
assert(run.metrics.n_upgrade_dropped_deadline == 1, 'p3x:R2Repair', ...
    'infeasible revision must be dropped by the R2 deadline-feasibility repair');
assert(~run.req(1).revised && strcmp(run.req(1).status, 'completed'), ...
    'p3x:R2Repair', 'stage-1 answer must stand after the drop');
assert(abs(run.metrics.budget_used - 1.1) < 1e-9, 'p3x:R2Repair', ...
    'a dropped revision must not be charged stage-2 cost');
p3_validate_run(run, P);
fprintf('  micro4 R2 revision-drop repair OK\n');

% =============== mixed E2A cell: attribution completeness ===================
cfg = struct('block', 'E2A', 'case_id', 'DEV_E2A_attribution_cell', 'seed', 20261018, ...
    'offset', 96, 'first_index', 1441, 'strategy', 'adaptive_gain', ...
    'carbon_sched', false, 'predictor', 'n/a(unused)', 'lambda', 1.0, 'C', 1, ...
    'budget_mode', 'fixed_abs', 'B_abs', 90, 'T_arr', 900, 'W_batch', 300, ...
    'd_int', 10, 'lag_s', 3600, 'rho_route', 0, 'bias', 0, 'carbon_sigma', 0, ...
    'demand_M', 1, 'note', 'mixed-status attribution dev cell (dev seed)');
[run, ex, rec] = p3x_run_one(cfg, rootDir, fullfile(devDir, cfg.case_id));
assert(strcmp(rec.status, 'success'), 'p3x:DevRun', 'attribution dev cell failed');
assert(ex.status_sum_check == ex.N_arr, 'p3x:Attribution', 'terminal states not exhaustive');
attrFile = fullfile(devDir, cfg.case_id, 'attribution.csv');
T = readtable(attrFile, 'TextType', 'string');
assert(height(T) == ex.N_arr, 'p3x:Attribution', 'one attribution row per request');
assert(all(ismember(T.primary_cause, {'none','budget','deadline','horizon'})), ...
    'p3x:Attribution', 'primary cause must be single and from the frozen vocabulary');
assert(ex.n_rejected_budget + ex.n_late + ex.n_completed + ...
    ex.n_drain_violation + ex.n_undrained_violation == ex.N_arr, ...
    'p3x:Attribution', 'status counts must partition N exactly');
fprintf('  mixed cell: N=%d completed=%d late=%d rejected=%d drain=%d\n', ...
    ex.N_arr, ex.n_completed, ex.n_late, ex.n_rejected_budget, ...
    ex.n_drain_violation + ex.n_undrained_violation);
fprintf('P3X_ATTRIBUTION_PASS\n');
end

function fp = force_light(n)
fp = struct('action0', repmat({'light'}, n, 1), 'revise', repmat({false}, n, 1), ...
    'action2', repmat({'strong'}, n, 1));
end

function cfg = cfg_micro()
cfg = struct('T_arr', 10, 'C', 4, 'q_target', 0.7);
end

function tf = contains_local(s, pat)
tf = ~isempty(strfind(s, pat)); %#ok<STREMP>
end
