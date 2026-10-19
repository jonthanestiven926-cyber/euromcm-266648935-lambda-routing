function [run, ex, receipt] = p3x_run_one(cfg, rootDir, outDir, opts)
%P3X_RUN_ONE Execute exactly one supplement run with a raw receipt.
% Status vocabulary (raw manifest): 'success' | 'failed' | 'incomplete'
%   failed     : engine/config error BEFORE the simulation produced a run struct
%   incomplete : run struct produced but validation/export failed (raw data kept)
%   success    : validated run + complete artifact set + receipt
% Reuse/dedup rule: with opts.reuse=true an existing SUCCESS receipt with the SAME
% config_hash short-circuits the run (repeated baselines never add independent n).
if nargin < 4, opts = struct(); end
if ~isfield(opts, 'reuse'), opts.reuse = false; end
% project run_id (06_results/<run_id>/...) is needed to resolve dev-calibrated
% budget tokens; cfg.run_id is the MATRIX row id and must not be used for paths
if isfield(opts, 'run_id') && ~isempty(opts.run_id)
    projRunId = char(opts.run_id);
else
    d = outDir;
    for k = 1:3
        d = fileparts(d);   % .../06_results/<run_id>/runs/<case>/seed_N -> run_id dir
    end
    [~, projRunId] = fileparts(d);
end
cfg = p3x_cfg_normalize(cfg);
cfgHash = p3x_config_hash(cfg);
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
receiptFile = fullfile(outDir, 'receipt.json');

if opts.reuse && exist(receiptFile, 'file') == 2
    try
        old = jsondecode(fileread(receiptFile));
    catch
        old = struct();
    end
    if isfield(old, 'config_hash') && strcmp(old.config_hash, cfgHash) && ...
            isfield(old, 'status') && strcmp(old.status, 'success')
        run = []; ex = [];
        receipt = old;
        receipt.reused = true;
        receipt.reuse_checked_at = p3_now_iso();
        return;
    end
end

receipt = struct('case_id', cfg.case_id, 'matrix_run_id', cfg.run_id, ...
    'block', cfg.block, 'seed', cfg.seed, 'config_hash', cfgHash, ...
    'started_at', p3_now_iso(), 'status', 'incomplete', 'reused', false);
run = []; ex = [];

srcDir = fileparts(mfilename('fullpath'));
[sh, snames] = p3_source_hashes(srcDir);
receipt.source_hashes = sh;
receipt.source_files = {snames{:}}; %#ok<CCAT>
carbon = p3_load_carbon(rootDir);
receipt.data_hashes = struct('train_sha256', carbon.train_sha256, ...
    'validation_sha256', carbon.val_sha256, 'test_targets_loaded', false);

simDone = false;
try
    % ---------- parameters ----------
    P = p3_default_params();
    P.scenario_label = ['SUPPLEMENT_CONSTRUCTED_SCENARIO/' cfg.block];
    P.T_arr = cfg.T_arr;
    P.lambda = cfg.lambda;
    P.C = cfg.C;
    P.W_batch = cfg.W_batch;
    P.d_int = cfg.d_int;
    P.rho_route = cfg.rho_route;
    P.tau_route = 0;
    P.carbon_sigma = cfg.carbon_sigma;
    P.carbon_delta_h = cfg.lag_s / 3600;
    P.demand_M = 1;

    % ---------- carbon history (safe train+validation only) ----------
    history = [carbon.g_train(:); carbon.g_val(:)];
    firstIndex = cfg.first_index;
    K = ceil((cfg.T_arr + cfg.W_batch + 2 * P.segment_seconds) / P.segment_seconds) + 2;
    if firstIndex + K - 1 > numel(history)
        error('p3x:Window', 'window %d..%d exceeds safe history %d', ...
            firstIndex, firstIndex + K - 1, numel(history));
    end

    % ---------- exogenous trajectory (never RNG inside sim/policy) ----------
    N1 = NaN;
    baseMarks = [];
    switch cfg.block
        case 'E2B'
            % nested subset via independent Bernoulli(0.5) marks (X1-2):
            % base Poisson(2*lambda); demand_M=2 = full stream; demand_M=1 =
            % marked subset = Poisson(lambda) by the thinning theorem (CV=1).
            % Even-index extraction is FORBIDDEN (it would give Erlang-2 CV=0.707).
            Pbase = P;
            Pbase.lambda = cfg.lambda;
            Pbase.demand_M = 2;
            base = p3_gen_trajectory(Pbase, cfg.seed);
            N2 = base.N;
            baseMarks = p3x_demand_marks(N2, cfg.seed);
            N1 = sum(baseMarks);
            if cfg.demand_M == 2
                traj = base;
                traj.meta.base_marks = baseMarks;
            else
                traj = p3x_thin_traj(base, baseMarks);
            end
        otherwise
            traj = p3_gen_trajectory(P, cfg.seed);
    end

    % ---------- budget ----------
    switch cfg.budget_mode
        case 'scaled'
            B = cfg.B_per_request * traj.N;
        case 'fixed_abs'
            tok = cfg.B_abs;
            if isnumeric(tok) && ~isempty(tok) && ~isnan(tok)
                B = tok;
            elseif ischar(tok) || isstring(tok)
                tok = char(tok);
                if strcmp(tok, '1.5*N1(seed)') || strcmp(tok, '1.5*N1(d1 realized)')
                    % frozen E2B d2_fixed rule: same absolute budget as the d1 run
                    if isnan(N1)
                        error('p3x:Config', 'B_abs token %s only resolvable inside E2B', tok);
                    end
                    B = 1.5 * N1;
                elseif strcmp(tok, 'TBD_tight') || strcmp(tok, 'TBD_high')
                    % dev-calibrated E2A budget axis (X1-3 unified per-lambda)
                    lvl = erase(tok, 'TBD_');
                    [B, ~] = p3x_resolve_budget(rootDir, projRunId, cfg.lambda, cfg.C, lvl);
                else
                    error('p3x:Config', 'unknown B_abs token %s', tok);
                end
            else
                error('p3x:Config', 'fixed_abs budget_mode requires B_abs or a frozen token');
            end
    end

    % ---------- causal signal closure (forecast issuance audit) ----------
    if cfg.carbon_sched
        sigMode = cfg.predictor;
    else
        sigMode = 'persistence';   % issued for audit only; policy never consumes it
    end
    switch cfg.predictor
        case 'persistence', infoClass = 'CAUSAL_PERSISTENCE';
        case 'seasonal', infoClass = 'CAUSAL_PREVIOUS_DAY';
        case 'oracle', infoClass = 'IDEAL_INFORMATION';
        case 'oracle_noise', infoClass = 'IDEAL_INFORMATION_NOISY';
        otherwise, infoClass = 'UNUSED_IMMEDIATE';
    end
    if ~cfg.carbon_sched
        infoClassPolicy = 'UNUSED_IMMEDIATE';
    else
        infoClassPolicy = infoClass;
    end
    [sigfh, getlog] = p3x_make_signal(history, firstIndex, K, cfg.lag_s, ...
        sigMode, cfg.bias, cfg.carbon_sigma, traj.c_noise(:));

    meta = struct('block', cfg.block, 'case_id', cfg.case_id, ...
        'matrix_run_id', cfg.run_id, 'predictor_mode', sigMode, ...
        'predictor_label', cfg.predictor, 'information_class', infoClassPolicy, ...
        'predictor_consumed_by_policy', cfg.carbon_sched, ...
        'bias_gCO2_per_kWh', cfg.bias, 'carbon_sigma_gCO2_per_kWh', cfg.carbon_sigma, ...
        'lag_s', cfg.lag_s, 'max_defer_s', cfg.max_defer_s, ...
        'demand_M', cfg.demand_M, 'budget_mode', cfg.budget_mode, ...
        'demand_rule', p3x_demand_rule(cfg), 'N1_marked', N1, ...
        'marks_hash', p3x_marks_hash(baseMarks), ...
        'budget_rule', p3x_budget_rule(cfg, B), ...
        'budget_B', B, 'window_first_index', firstIndex, ...
        'window_last_target', firstIndex + K - 1, 'K_segments', K, ...
        'config_hash', cfgHash, 'dev_or_matrix_note', cfg.note, ...
        'carbon_slice_rule', 'environment truth = safe_history(firstIndex:firstIndex+K-1)');
    % The environment holds the TRUE window slice (scoring only); the policy only
    % ever sees the issued forecast through the signal closure (info boundary).
    simopts = struct('signal_fn', sigfh, 'B', B, ...
        'carbon_sched', cfg.carbon_sched, 'label', cfg.case_id, ...
        'offline_diagnostic', false, 'max_defer_s', cfg.max_defer_s, ...
        'gActual', history(firstIndex : firstIndex + K - 1), ...
        'meta_extra', meta);

    run = p3x_simulate(traj, P, carbon, cfg.strategy, simopts);
    simDone = true;
    [ex, attr] = p3x_extras(run, cfg, P);
    receipt.traj_hash = p3x_traj_hash(traj);
    receipt.N_arr = traj.N;
    % raw capture first: failure evidence survives even if validation fails
    save(fullfile(outDir, 'run_raw.mat'), 'run', 'ex', 'attr', 'cfg', 'cfgHash', '-v7');

    vrep = p3_validate_run(run, P);
    p3_write_run_artifacts(outDir, run);
    p3x_write_supplement_artifacts(outDir, run, ex, attr, getlog(), cfg, cfgHash);

    receipt.status = 'success';
    receipt.finished_at = p3_now_iso();
    receipt.validation = vrep;
    receipt.summary = struct('N_arr', ex.N_arr, 'n_completed', ex.n_completed, ...
        'n_late', ex.n_late, 'n_rejected_budget', ex.n_rejected_budget, ...
        'n_drain_violation', ex.n_drain_violation + ex.n_undrained_violation, ...
        'quality_total', ex.quality_total, 'carbon_total', ex.carbon_total, ...
        'budget_used', ex.budget_used, 'budget_remaining', ex.budget_remaining, ...
        'utilization_over_0_to_T_arr', ex.utilization_over_0_to_T_arr, ...
        'stage1_wait_mean', ex.stage1_wait_mean, 'n_defer_events', ex.n_defer_events);
    p3_write_json(receiptFile, receipt);
catch ME
    receipt.finished_at = p3_now_iso();
    receipt.error = struct('identifier', ME.identifier, 'message', ME.message);
    if simDone
        receipt.status = 'incomplete';
    else
        receipt.status = 'failed';
    end
    try
        receipt.error_stack = {ME.stack.name};
    catch
        receipt.error_stack = {};
    end
    p3_write_json(receiptFile, receipt);
    rethrow(ME);
end
end

function s = p3x_demand_rule(cfg)
if strcmp(cfg.block, 'E2B')
    s = 'E2B nested subset: Poisson(2*lambda) base + independent Bernoulli(0.5) marks (X1-2); d1 subset of d2; d2 extras unpaired';
else
    s = 'Poisson(lambda*demand_M) direct generation';
end
end

function h = p3x_marks_hash(marks)
if isempty(marks)
    h = 'none';
else
    h = p3_sha256_str(sprintf('%d', double(marks(:))'));
end
end

function s = p3x_budget_rule(cfg, B)
if strcmp(cfg.budget_mode, 'scaled')
    s = sprintf('scaled: B=%.17g*B_per_request*N', cfg.B_per_request);
else
    if isnumeric(cfg.B_abs)
        tok = sprintf('%.17g', cfg.B_abs);
    else
        tok = char(cfg.B_abs);
    end
    s = sprintf('fixed_abs token %s -> B=%.17g (X1-3 unified per-lambda levels resolve TBD_tight/TBD_high; same numeric B for C=1 and C=4)', tok, B);
end
end

function h = p3x_traj_hash(traj)
% Deterministic hash of the exogenous trajectory (pairing identity).
s = sprintf('N=%d;', traj.N);
fields = {'a','d','x','q_light','q_strong','gain'};
for k = 1:numel(fields)
    v = traj.(fields{k});
    s = [s fields{k} ':' sprintf('%.17g,', v)]; %#ok<AGROW>
end
h = p3_sha256_str(s);
end
