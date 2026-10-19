function fm = p3x_freeze(run_id, opts)
%P3X_FREEZE Final freeze of the supplement implementation BEFORE the matrix run.
% Binds every new source file to its binary SHA256, cross-checked with a second,
% independent hash implementation (certutil) to rule out byte-conversion bugs
% (e.g. int8 saturation). Also records: frozen windows/seeds, the complete final
% coverage list (304 rows with per-row config hash), the baseline dedup/reuse
% rules, and the explicit evidence that the 8 final seeds have NOT been run.
if nargin < 2, opts = struct(); end
thisDir = fileparts(mfilename('fullpath'));
rootDir = def(opts, 'rootDir', fileparts(fileparts(fileparts(thisDir))));
outRoot = def(opts, 'outRoot', fullfile(rootDir, '06_results', run_id));
if exist(outRoot, 'dir') ~= 7, mkdir(outRoot); end

% ---- 1. source + frozen-file hashes with independent cross-check ----
files = [list_dir(fullfile(thisDir, '*.m')); ...
         list_dir(fullfile(thisDir, '*.md')); ...
         list_dir(fullfile(thisDir, '*.csv'))];
hc = cell(numel(files), 9);
for k = 1:numel(files)
    fp = files{k};
    h1 = p3_sha256(fp);                 % MATLAB implementation (typecast, no int8)
    h2 = p3x_sha256_certutil(fp);       % independent Windows implementation
    d = dir(fp);
    hc(k, :) = {fp, d.bytes, h1, h2, char(string(strcmp(h1, h2))), ...
        h1, d.datenum, h2, char(string(strcmp(h1, h2)))};
end
cols = cell(1, 5);
for k = 1:5
    cols{k} = hc(:, k);
end
p3_write_csv(fullfile(outRoot, 'hash_crosscheck.csv'), ...
    {'file','bytes','sha256_matlab','sha256_certutil','match'}, cols);
if ~all(strcmp(hc(:, 5), 'true'))
    error('p3x:Freeze', 'independent hash cross-check mismatch; freeze refused');
end

% ---- 2. final coverage list (complete, with per-row config hash) ----
T = readtable(fullfile(thisDir, 'run_matrix.csv'), 'TextType', 'string');
n = height(T);
rid = cell(n, 1); blk = cell(n, 1); cid = cell(n, 1); sd = cell(n, 1); ch = cell(n, 1);
rb = cell(n, 1);   % resolved numeric absolute budget (X1-3 unified across C)
for i = 1:n
    s = struct();
    vn = T.Properties.VariableNames;
    for k = 1:numel(vn)
        s.(vn{k}) = T.(vn{k})(i);
    end
    cfg = p3x_cfg_from_row(s);
    rid{i} = cfg.run_id; blk{i} = cfg.block; cid{i} = cfg.case_id;
    sd{i} = sprintf('%d', cfg.seed); ch{i} = p3x_config_hash(cfg);
    rb{i} = p3x_resolve_row_budget(cfg, rootDir, run_id);
end
cols = {rid, blk, cid, sd, ch, rb};
p3_write_csv(fullfile(outRoot, 'final_coverage_list.csv'), ...
    {'matrix_run_id','block','case_id','seed','config_hash','resolved_budget'}, cols);

% ---- 3. coverage summary + frozen windows/seeds ----
blocks = {'E1','E2A','E2B','E3'};
counts = zeros(4, 1);
for k = 1:4
    counts(k) = sum(strcmp(blk, blocks{k}));
end
seeds_final = 2026101901:2026101908;

% ---- 4. evidence that the 8 final seeds are NOT run yet ----
finalSeedsRun = p3x_scan_seeds(outRoot, seeds_final);

fm = struct();
fm.run_id = run_id;
fm.frozen_at = p3_now_iso();
fm.phase = 'IMPLEMENTATION_FROZEN_BEFORE_FINAL_MATRIX';
fm.sources = struct('files', {files'}, 'hash_crosscheck', 'hash_crosscheck.csv', ...
    'all_match', true, 'matlab_hash', 'p3_sha256 (typecast uint8->int8, no saturation)', ...
    'independent_hash', 'certutil -hashfile SHA256');
fm.frozen_protocol_files = {'00_PROTOCOL.md','acceptance.md','params_freeze.csv', ...
    'windows.csv','run_matrix.csv'};
fm.windows = struct('file', 'windows.csv', 'note', ['four pre-fixed non-overlapping ', ...
    'validation windows firstIndex=1345/1441/1537/1633; lastTarget<=2016; sealed test untouched']);
fm.seeds = struct('dev', 20261018, 'final', seeds_final, ...
    'statistical_unit', ['seed within window/cell (n=8); the four E1 windows are NOT i.i.d.; ', ...
    'cross-window aggregation is descriptive only']);
fm.final_coverage = struct('matrix_file', 'run_matrix.csv', 'total_rows', n, ...
    'counts', struct('E1', counts(1), 'E2A', counts(2), 'E2B', counts(3), 'E3', counts(4)), ...
    'list_file', 'final_coverage_list.csv', ...
    'unique_config_hashes', numel(unique(ch)));
fm.reuse_and_dedup_rules = [ ...
    '1) repeated baselines (E3 baseline E3_W1800, E2B d1=(d1,fixed), oracle sigma=0 point) ', ...
    'are REUSED across comparisons and never counted as extra independent samples; ', ...
    '2) p3x_run_one skips an existing SUCCESS receipt with identical config_hash ', ...
    '(opts.reuse=true) and marks it reused in raw_manifest.csv; ', ...
    '3) a changed config hash always produces a NEW run directory - old outputs are kept; ', ...
    '4) per-run receipts bind config_hash + source SHA256 + train/validation data SHA256.'];
% ---- 5. dev-calibrated E2A budget axis (X1-1), hash-bound ----
calFile = fullfile(outRoot, 'dev_acceptance', 'budget_calibration', 'budget_calibration.json');
if exist(calFile, 'file') == 2
    cal = jsondecode(fileread(calFile));
    fm.budget_calibration = struct('file', '06_results/<run_id>/dev_acceptance/budget_calibration/budget_calibration.json', ...
        'sha256', p3_sha256(calFile), 'rule', cal.rule, ...
        'tokens', 'TBD_tight -> B_tight; TBD_high -> B_high_final (raised gate re-freezes before final)', ...
        'cells', {cal.cells});
else
    fm.budget_calibration = struct('file', '', 'sha256', 'MISSING', ...
        'tokens', 'TBD_tight/TBD_high unresolved until dev calibration runs');
end
% ---- 6. data hashes (safe train/validation split only) + protocol hashes ----
carbon = p3_load_carbon(rootDir);
fm.data_hashes = struct('train_sha256', carbon.train_sha256, ...
    'validation_sha256', carbon.val_sha256, 'test_targets_loaded', false, ...
    'split_info', '03_config/prediction_protocol.json 1344 train + 672 validation; sealed test never loaded');
protoFiles = {'00_PROTOCOL.md','01_PROTOCOL_AMENDMENT_X1.md','acceptance.md', ...
    'params_freeze.csv','windows.csv','run_matrix.csv'};
ph = cell(numel(protoFiles), 3);
for k = 1:numel(protoFiles)
    ph{k, 1} = protoFiles{k};
    ph{k, 2} = upper(p3_sha256(fullfile(thisDir, protoFiles{k})));
    ph{k, 3} = 'math-member final freeze (X1-3)';
end
fm.protocol_hashes = struct('files', {ph}, 'note', ...
    'protocol frozen by the math member before this freeze; implementation binds these exact bytes');
fm.final_seeds_executed = finalSeedsRun;
fm.final_seeds_run_flag = isempty(finalSeedsRun);
fm.status_vocabulary = 'success | failed | incomplete | reused (raw_manifest.csv)';
fm.declared_scope = ['SUPPLEMENT DEVELOPMENT / MECHANISM CONSTRUCTED SCENARIOS only; ', ...
    'relative carbon index (not measured gCO2); not a real-deployment evaluation; ', ...
    '09_paper untouched; sealed carbon test never loaded'];
p3_write_json(fullfile(outRoot, 'freeze_manifest.json'), fm);
end

function s = p3x_resolve_row_budget(cfg, rootDir, run_id)
% numeric absolute budget actually used by the runner for this matrix row
if strcmp(cfg.budget_mode, 'scaled')
    s = sprintf('scaled:%.17g*N(seed)', cfg.B_per_request);
    return;
end
tok = cfg.B_abs;
if isnumeric(tok)
    s = sprintf('%.17g', tok);
    return;
end
tok = char(tok);
if strcmp(tok, '1.5*N1(seed)') || strcmp(tok, '1.5*N1(d1 realized)')
    s = '1.5*N1(seed) [per-seed realized marked count]';
elseif strcmp(tok, 'TBD_tight') || strcmp(tok, 'TBD_high')
    lvl = erase(tok, 'TBD_');
    B = p3x_resolve_budget(rootDir, run_id, cfg.lambda, cfg.C, lvl);
    s = sprintf('%.17g', B);
else
    s = tok;
end
end

function files = list_dir(pattern)
d = dir(pattern);
files = cell(numel(d), 1);
for k = 1:numel(d)
    files{k} = fullfile(d(k).folder, d(k).name);
end
end

function h = p3x_sha256_certutil(fp)
[st, out] = system(sprintf('certutil -hashfile "%s" SHA256', fp));
if st ~= 0
    error('p3x:Freeze', 'certutil failed for %s', fp);
end
tok = regexp(out, '([0-9a-fA-F]{64})', 'tokens', 'once');
if isempty(tok)
    error('p3x:Freeze', 'certutil produced no digest for %s', fp);
end
h = lower(tok{1});
end

function hit = p3x_scan_seeds(outRoot, seeds)
% Recursively look for any executed final seed in receipts/manifests.
hit = {};
d = dir(outRoot);
for k = 1:numel(d)
    if d(k).isdir
        if any(strcmp(d(k).name, {'.','..'}))
            continue;
        end
        hit = [hit; p3x_scan_seeds(fullfile(d(k).folder, d(k).name), seeds)]; %#ok<AGROW>
    elseif strcmp(d(k).name, 'receipt.json')
        fp = fullfile(d(k).folder, d(k).name);
        try
            b = jsondecode(fileread(fp));
            if isfield(b, 'seed') && any(b.seed == seeds)
                hit{end+1, 1} = fp; %#ok<AGROW>
            end
        catch
        end
    elseif strcmp(d(k).name, 'raw_manifest.csv')
        fp = fullfile(d(k).folder, d(k).name);
        try
            T = readtable(fp, 'TextType', 'string');
            if any(ismember(str2double(T.seed), seeds))
                hit{end+1, 1} = fp; %#ok<AGROW>
            end
        catch
        end
    end
end
end

function v = def(opts, name, default)
if isfield(opts, name) && ~isempty(opts.(name))
    v = opts.(name);
else
    v = default;
end
end
