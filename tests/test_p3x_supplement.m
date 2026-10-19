function test_p3x_supplement(run_id)
%TEST_P3X_SUPPLEMENT Acceptance entry point for the supplement implementation.
% Runs BEFORE the final matrix: unit/contract tests, dev small-example
% acceptance, artifact completeness, the bounded runner demo (dev seeds only),
% protected-artifact integrity checks and the final freeze with independent
% SHA256 cross-check. Any assertion failure exits non-zero and keeps the failed
% receipt in 08_logs/<run_id>/xiaomi/receipts/.
if nargin < 1, run_id = '20261018_171608_963_p3_supplement'; end
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(fileparts(thisDir)));
[~, dirName] = fileparts(thisDir);
assert(strcmp(dirName, run_id), 'p3x:RunId', 'run_id %s != directory %s', run_id, dirName);
outRoot = fullfile(rootDir, '06_results', run_id);
logRoot = fullfile(rootDir, '08_logs', run_id, 'xiaomi');
recDir = fullfile(logRoot, 'receipts');
if exist(outRoot, 'dir') ~= 7, mkdir(outRoot); end
if exist(recDir, 'dir') ~= 7, mkdir(recDir); end

% ---------- explicit addpath + shadow audit (never restoredefaultpath) -------
addpath(thisDir);
addpath(fullfile(rootDir, '04_scripts', 'p3_system'));
addpath(fullfile(rootDir, '04_scripts', 'p3_supplement'));
expect = { ...
    'p3x_signal', thisDir; 'p3x_simulate', thisDir; 'p3x_make_signal', thisDir; ...
    'p3x_run_one', thisDir; 'p3x_freeze', thisDir; 'test_p3x_supplement', thisDir; ...
    'p3_policy', fullfile(rootDir, '04_scripts', 'p3_system'); ...
    'p3_simulate', fullfile(rootDir, '04_scripts', 'p3_system'); ...
    'p3_gen_trajectory', fullfile(rootDir, '04_scripts', 'p3_system'); ...
    'p3_default_params', fullfile(rootDir, '04_scripts', 'p3_system'); ...
    'p3_load_carbon', fullfile(rootDir, '04_scripts', 'p3_system'); ...
    'p3_write_run_artifacts', fullfile(rootDir, '04_scripts', 'p3_system'); ...
    'p3_validate_run', fullfile(rootDir, '04_scripts', 'p3_system'); ...
    'p3_sha256', fullfile(rootDir, '04_scripts', 'p3_system'); ...
    'test_p3x_contract', fullfile(rootDir, '04_scripts', 'p3_supplement')};
audit = '';
for k = 1:size(expect, 1)
    w = which(expect{k, 1}, '-all');
    if ischar(w), w = {w}; end
    audit = [audit expect{k, 1} sprintf(':\n')]; %#ok<AGROW>
    for j = 1:numel(w)
        audit = [audit '    ' w{j} sprintf('\n')]; %#ok<AGROW>
    end
    assert(~isempty(w), 'p3x:Path', 'function not found: %s', expect{k, 1});
    assert(strcmpi(fileparts(w{1}), expect{k, 2}), 'p3x:Path', ...
        '%s resolves to %s, expected %s (shadowing!)', expect{k, 1}, w{1}, expect{k, 2});
end
fid = fopen(fullfile(logRoot, 'path_audit.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, 'path audit %s\naddpath order: run dir, 04_scripts/p3_system, 04_scripts/p3_supplement\n', ...
    p3_now_iso());
fwrite(fid, audit, 'char');
fclose(fid);

% ---------- frozen protocol hashes (math member final X1-3 freeze) ----------
proto = {
    '00_PROTOCOL.md',           '3A0D23A973887819A8C773BA65A8296DDB26AC1E9FD9E7336A67E4F53FCF97A8'
    '01_PROTOCOL_AMENDMENT_X1.md', '29C459FB0B6BEE3B47DAD5BF3604D1D44CD28A346DB074211D471BF20850C119'
    'acceptance.md',            'E3FCBC62E92A82F6156B6A87F1D26556852BD04EACC2A14741A9367E9144C4DC'
    'params_freeze.csv',        'E74CE5B28B7F9251D497C7F7CBBD735454269356CBEB8C43967ABFDA05B6FFA1'
    'windows.csv',              '5CAEA05AFD6E8EDB989831039000D512A293AEAF82FB0C61DC41D874346BE4C2'
    'run_matrix.csv',           '958826085A8D0E87D7AFE280EE06A52E62AA7B4C7D959AA7183F06F5D03164C3'};
protoAudit = '';
for k = 1:size(proto, 1)
    fp = fullfile(thisDir, proto{k, 1});
    h = upper(p3_sha256(fp));
    protoAudit = [protoAudit sprintf('%s %s expect=%s match=%d\n', proto{k, 1}, ...
        h, proto{k, 2}, strcmp(h, proto{k, 2}))]; %#ok<AGROW>
    assert(strcmp(h, proto{k, 2}), 'p3x:ProtocolHash', ...
        'protocol file %s changed after the math freeze (%s != %s): re-coordinate before freeze', ...
        proto{k, 1}, h, proto{k, 2});
end
fid2 = fopen(fullfile(logRoot, 'protocol_hash_audit.txt'), 'w', 'n', 'UTF-8');
fwrite(fid2, protoAudit, 'char');
fclose(fid2);

% ---------- protected artifacts must be byte-identical ----------------------
prot = p3x_check_baseline(fullfile(logRoot, '..', 'captain', 'protected_artifacts_baseline.json'), rootDir);
pap = p3x_check_baseline(fullfile(logRoot, '..', 'captain', 'paper_readonly_baseline.json'), rootDir);
assert(prot.n_mismatch == 0, 'p3x:Protected', '%d protected artifacts changed', prot.n_mismatch);
assert(pap.n_mismatch == 0, 'p3x:Protected', '%d 09_paper artifacts changed', pap.n_mismatch);
p3_write_json(fullfile(logRoot, 'protected_check.json'), struct('protected', prot, 'paper', pap));

% ---------- contract + acceptance tests (failures kept on disk) -------------
tests = {'test_p3x_contract', 'test_p3x_signal_boundary', ...
    'test_p3x_causal_prefix_invariance', 'test_p3x_maxdefer_independent', ...
    'test_p3x_saturation', 'test_p3x_budget_unified', 'test_p3x_attribution', ...
    'test_p3x_demand_prefix'};
allRec = cell(numel(tests), 1);
for k = 1:numel(tests)
    nm = tests{k};
    t0 = tic;
    started = p3_now_iso();
    stamp = char(datetime('now', 'TimeZone', 'Asia/Shanghai', 'Format', 'yyyyMMdd_HHmmss'));
    try
        if strcmp(nm, 'test_p3x_contract')
            feval(nm);   % coordinator-written contract test (unmodified file)
        else
            feval(nm, rootDir, run_id);
        end
        st = 'passed'; msg = '';
    catch ME
        st = 'failed';
        msg = ME.message;
    end
    rec = struct('test', nm, 'status', st, 'message', msg, 'started_at', started, ...
        'finished_at', p3_now_iso(), 'elapsed_s', toc(t0), 'run_id', run_id, ...
        'matlab_version', version);
    p3_write_json(fullfile(recDir, sprintf('%s_%s.json', stamp, nm)), rec);
    allRec{k} = rec;
    fprintf('[%s] %s -> %s\n', rec.finished_at, nm, st);
    if strcmp(st, 'failed')
        p3_write_json(fullfile(logRoot, 'test_receipts.json'), struct('tests', {allRec}, ...
            'overall', 'FAILED', 'at', p3_now_iso()));
        error('p3x:Acceptance', 'test %s FAILED: %s', nm, msg);
    end
end

% ---------- dev artifact completeness (raw layers preserved) ----------------
devRoot = fullfile(outRoot, 'dev_acceptance');
need = {'per_request.csv','events.csv','budget_ledger.csv','execution_windows.csv', ...
    'carbon_segments.csv','decisions.csv','metrics.json','forecast_issuance.csv', ...
    'decisions_audit.csv','attribution.csv','supplement_metrics.csv','config.json', ...
    'receipt.json','run_raw.mat'};
[runDirs, nChecked] = p3x_check_artifacts(devRoot, need);
assert(nChecked >= 15, 'p3x:Artifacts', 'expected >=15 dev runs with full artifacts, got %d', nChecked);
fprintf('artifact completeness: %d dev run directories fully populated\n', nChecked);

% ---------- bounded runner demo (dev seed override ONLY; reuse/dedup) -------
demoRoot = fullfile(outRoot, 'runner_dev_demo');
cleanDemo = exist(fullfile(demoRoot, 'raw_manifest.csv'), 'file') ~= 2;
r1 = p3x_runner(run_id, struct('rootDir', rootDir, 'shardIdx', 1, 'shardCount', 1, ...
    'maxRuns', 2, 'seedMode', 'dev', 'outRoot', demoRoot, 'reuse', true, 'seed_dev', 20261018));
assert(size(r1, 1) == 2, 'p3x:Runner', 'demo must run exactly 2 bounded rows');
if cleanDemo
    assert(all(strcmp(r1(:, 7), 'success')), 'p3x:Runner', ...
        'first demo invocation on a clean directory must succeed');
else
    assert(all(strcmp(r1(:, 7), 'reused')), 'p3x:Runner', ...
        'existing config-hash matches must be reused, not re-run');
end
r2 = p3x_runner(run_id, struct('rootDir', rootDir, 'shardIdx', 1, 'shardCount', 1, ...
    'maxRuns', 2, 'seedMode', 'dev', 'outRoot', demoRoot, 'reuse', true, 'seed_dev', 20261018));
assert(all(strcmp(r2(:, 7), 'reused')), 'p3x:Runner', ...
    'second identical invocation must be config-hash REUSED, not re-run');
fprintf('runner bounded demo OK (statuses %s -> %s; raw_manifest.csv distinguishes success/failed/incomplete/reused)\n', ...
    strjoin(r1(:, 7)', ','), strjoin(r2(:, 7)', ','));

% ---------- final seeds must NOT have run ----------------------------------
finalSeeds = 2026101901:2026101908;
hits = p3x_scan_final_seeds(outRoot, finalSeeds);
assert(isempty(hits), 'p3x:FinalSeeds', 'final seeds already executed: %s', strjoin(hits, '; '));

% ---------- final freeze (independent SHA256 cross-check) -------------------
fm = p3x_freeze(run_id, struct('rootDir', rootDir));
assert(fm.final_seeds_run_flag, 'p3x:Freeze', 'freeze must record 8 final seeds as NOT run');
assert(fm.sources.all_match, 'p3x:Freeze', 'hash cross-check mismatch');
assert(fm.final_coverage.total_rows == 304, 'p3x:Freeze', ...
    'frozen matrix must contain exactly 304 rows, got %d', fm.final_coverage.total_rows);

p3_write_json(fullfile(logRoot, 'test_receipts.json'), struct('tests', {allRec}, ...
    'overall', 'P3X_SUPPLEMENT_ACCEPTANCE_PASS', 'at', p3_now_iso(), ...
    'dev_runs_checked', nChecked, 'dev_run_dirs', {runDirs}));
fprintf('P3X_SUPPLEMENT_ACCEPTANCE_PASS\n');
end

function res = p3x_check_baseline(file, rootDir)
% Re-hash every protected file against the captain's read-only baseline.
txt = fileread(file);
b = jsondecode(txt);
res = struct('baseline', file, 'n_files', numel(b.files), 'n_mismatch', 0, ...
    'n_missing', 0, 'mismatched', {{}});
for k = 1:numel(b.files)
    fp = fullfile(rootDir, strrep(b.files(k).path, '', filesep));
    if exist(fp, 'file') ~= 2
        res.n_missing = res.n_missing + 1;
        res.mismatched{end+1, 1} = ['MISSING ' b.files(k).path]; %#ok<AGROW>
        continue;
    end
    h = p3_sha256(fp);
    if ~strcmpi(h, b.files(k).sha256)
        res.n_mismatch = res.n_mismatch + 1;
        res.mismatched{end+1, 1} = ['CHANGED ' b.files(k).path]; %#ok<AGROW>
    end
end
res.n_mismatch = res.n_mismatch + res.n_missing;
end

function [runDirs, n] = p3x_check_artifacts(devRoot, need)
runDirs = {};
n = 0;
if exist(devRoot, 'dir') ~= 7, return; end
d = dir(devRoot);
for k = 1:numel(d)
    if ~d(k).isdir || any(strcmp(d(k).name, {'.', '..'}))
        continue;
    end
    sub = fullfile(d(k).folder, d(k).name);
    s2 = dir(sub);
    isRunDir = exist(fullfile(sub, 'receipt.json'), 'file') == 2;
    if isRunDir
        ok = true;
        for j = 1:numel(need)
            f = fullfile(sub, need{j});
            if exist(f, 'file') ~= 2 || dir(f).bytes == 0
                ok = false;
                fprintf('    MISSING/EMPTY: %s\n', f);
            end
        end
        assert(ok, 'p3x:Artifacts', 'incomplete artifact set in %s', sub);
        n = n + 1;
        runDirs{end+1, 1} = sub; %#ok<AGROW>
    else
        [r2, n2] = p3x_check_artifacts(sub, need);
        runDirs = [runDirs; r2]; %#ok<AGROW>
        n = n + n2;
    end
    clear s2;
end
end

function hits = p3x_scan_final_seeds(outRoot, seeds)
hits = {};
d = dir(outRoot);
for k = 1:numel(d)
    if d(k).isdir
        if any(strcmp(d(k).name, {'.', '..'})), continue; end
        h = p3x_scan_final_seeds(fullfile(d(k).folder, d(k).name), seeds);
        hits = [hits; h]; %#ok<AGROW>
    elseif strcmp(d(k).name, 'receipt.json')
        fp = fullfile(d(k).folder, d(k).name);
        try
            b = jsondecode(fileread(fp));
            if isfield(b, 'seed') && any(b.seed == seeds)
                hits{end+1, 1} = fp; %#ok<AGROW>
            end
        catch
        end
    elseif strcmp(d(k).name, 'raw_manifest.csv')
        fp = fullfile(d(k).folder, d(k).name);
        try
            T = readtable(fp, 'TextType', 'string');
            if any(ismember(str2double(T.seed), seeds))
                hits{end+1, 1} = fp; %#ok<AGROW>
            end
        catch
        end
    end
end
end
