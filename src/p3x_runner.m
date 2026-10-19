function manifest = p3x_runner(run_id, opts)
%P3X_RUNNER Bounded single-shard matrix runner for the supplement experiments.
% opts fields (all optional):
%   rootDir    : project root (default derived from this file's location)
%   matrixFile : frozen matrix CSV (default <run dir>/run_matrix.csv)
%   shardIdx, shardCount : 1-based shard selection over matrix rows (default 1,1)
%   maxRuns    : hard bound on runs started in this invocation (default 1)
%   seedMode   : 'matrix' (frozen final seeds) | 'dev' (replace seed with
%                opts.seed_dev, ONLY for development acceptance; final seeds
%                must not run before the freeze is reviewed)
%   outRoot    : results root (default <root>/06_results/<run_id>)
%   reuse      : config-hash reuse/dedup switch (default true)
% Every run appends one raw manifest row: success | failed | incomplete | reused.
% The runner is serial and bounded; a failure is recorded and the shard stops.
if nargin < 2, opts = struct(); end
thisDir = fileparts(mfilename('fullpath'));
rootDir = def(opts, 'rootDir', fileparts(fileparts(fileparts(thisDir))));
matrixFile = def(opts, 'matrixFile', fullfile(thisDir, 'run_matrix.csv'));
shardIdx = def(opts, 'shardIdx', 1);
shardCount = def(opts, 'shardCount', 1);
maxRuns = def(opts, 'maxRuns', 1);
seedMode = def(opts, 'seedMode', 'matrix');
outRoot = def(opts, 'outRoot', fullfile(rootDir, '06_results', run_id));
reuse = def(opts, 'reuse', true);
seedDev = def(opts, 'seed_dev', 20261018);

T = readtable(matrixFile, 'TextType', 'string');
n = height(T);
sel = find(mod((1:n)' - 1, shardCount) == shardIdx - 1);
if strcmp(seedMode, 'dev')
    sel = sel(1:min(numel(sel), maxRuns));
end
if isempty(sel)
    error('p3x:Runner', 'empty shard %d/%d', shardIdx, shardCount);
end
manifestFile = fullfile(outRoot, 'raw_manifest.csv');
if exist(outRoot, 'dir') ~= 7, mkdir(outRoot); end
rows = cell(0, 11);
started = 0;
for q = 1:numel(sel)
    if started >= maxRuns
        break;
    end
    i = sel(q);
    s = struct();
    vn = T.Properties.VariableNames;
    for k = 1:numel(vn)
        s.(vn{k}) = T.(vn{k})(i);
    end
    cfg = p3x_cfg_from_row(s);
    if strcmp(seedMode, 'dev')
        cfg.seed = seedDev;
        cfg.note = ['runner dev demo (seed overridden to ' num2str(seedDev) ...
            '; NOT a final-matrix run)'];
    end
    cfgHash = p3x_config_hash(cfg);
    outDir = fullfile(outRoot, 'runs', cfg.case_id, sprintf('seed_%d', cfg.seed));
    started = started + 1;
    try
        [runOut, ~, rec] = p3x_run_one(cfg, rootDir, outDir, struct('reuse', reuse, 'run_id', run_id)); %#ok<ASGLU>
        if isfield(rec, 'reused') && rec.reused
            st = 'reused';
        else
            st = rec.status;
        end
        rows(end+1, :) = {cfg.run_id, cfg.case_id, cfg.block, num2str(cfg.seed), ...
            num2str(shardIdx), cfgHash, st, char(string(logical(rec.reused))), ...
            outDir, rec.started_at, rec.finished_at}; %#ok<AGROW>
    catch ME
        rows(end+1, :) = {cfg.run_id, cfg.case_id, cfg.block, num2str(cfg.seed), ...
            num2str(shardIdx), cfgHash, 'failed', 'false', outDir, ...
            p3_now_iso(), p3_now_iso()}; %#ok<AGROW>
        p3x_write_manifest(manifestFile, rows);
        rethrow(ME);
    end
end
p3x_write_manifest(manifestFile, rows);
manifest = rows;
end

function p3x_write_manifest(file, rows)
% MERGE with any existing manifest: bounded foreground shards run in separate
% MATLAB invocations and each invocation contributes its own rows. Key =
% (matrix_run_id, seed); the newest row wins so re-verified partial failures
% replace the old record while earlier shard rows are preserved.
hdr = {'matrix_run_id','case_id','block','seed','shard','config_hash', ...
    'status','reused','out_dir','started_at','finished_at'};
if exist(file, 'file') == 2
    try
        E = readtable(file, 'TextType', 'string');
        vn = E.Properties.VariableNames;
        for i = 1:height(E)
            r = cell(1, 11);
            for k = 1:11
                r{k} = char(E.(vn{k})(i));
            end
            rows(end+1, :) = r; %#ok<AGROW>
        end
    catch
        % unreadable old manifest is left untouched; the new rows still land
    end
end
key = cell(size(rows, 1), 1);
for i = 1:size(rows, 1)
    key{i} = sprintf('%s|%s', rows{i, 1}, rows{i, 4});
end
[~, ia] = unique(key, 'stable');
ia = sort(ia);
rows = rows(ia, :);
cols = cell(1, 11);
for k = 1:11
    cols{k} = rows(:, k);
end
p3_write_csv(file, hdr, cols);
end

function v = def(opts, name, default)
if isfield(opts, name) && ~isempty(opts.(name))
    v = opts.(name);
else
    v = default;
end
end
