function p3x_aggregate(rootDir, run_id)
%P3X_AGGREGATE X5 statistics over the frozen 304-run final matrix.
% Outputs (06_results/<run_id>/final_matrix_stats/):
%   tidy_runs.csv        one row per (matrix_run_id, seed) with factors + key
%                        metrics (NaN preserved; missing never becomes 0)
%   aggregate_ci.csv     per (block, case_id, metric): n_valid/n_missing, mean,
%                        sd, se, 95% CI (two-sided t, df = n_valid-1)
%   delta_boundary.csv   E3 scanned-axis paired deltas vs the common baseline
%                        cell E3_W1800 (same seeds = common potential outcomes),
%                        plus an HONEST crossing statement: when zero is never
%                        crossed across scanned levels the crossing column says
%                        "no_zero_crossing_observed" and NO critical value is
%                        produced; a crossing only yields a bracket, never an
%                        interpolated threshold (no densification here: that
%                        would need a frozen rule + new exploration version)
%   e1_windows.csv / e2_axes.csv   tidy contrast tables (paired by seed)
%   schema.md            column/units/NaN documentation
if nargin < 2, run_id = '20261018_171608_963_p3_supplement'; end
if nargin < 1, rootDir = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))); end
thisDir = fileparts(mfilename('fullpath'));
outRoot = fullfile(rootDir, '06_results', run_id);
statDir = fullfile(outRoot, 'final_matrix_stats');
if exist(statDir, 'dir') ~= 7, mkdir(statDir); end

T = readtable(fullfile(thisDir, 'run_matrix.csv'), 'TextType', 'string');
vn = T.Properties.VariableNames;
n = height(T);

tidy = {};
for i = 1:n
    s = struct();
    for k = 1:numel(vn)
        s.(vn{k}) = T.(vn{k})(i);
    end
    cfg = p3x_cfg_from_row(s);
    runDir = fullfile(outRoot, 'runs', cfg.case_id, sprintf('seed_%d', cfg.seed));
    row = base_row(cfg, runDir);
    if exist(fullfile(runDir, 'metrics.json'), 'file') == 2
        m = jsondecode(fileread(fullfile(runDir, 'metrics.json')));
        mm = m.metrics;
        row = [row, metric_vals(mm), supp_vals(runDir), attrib_vals(runDir)]; %#ok<AGROW>
    else
        row = [row, metric_vals(struct()), supp_vals(''), attrib_vals('')]; %#ok<AGROW>
    end
    tidy{end+1, 1} = row; %#ok<AGROW>
end

hdr = [base_hdr(), metric_hdr(), supp_hdr(), attrib_hdr()];
cols = cell(1, numel(hdr));
for j = 1:numel(hdr)
    col = cell(size(tidy, 1), 1);
    for i = 1:size(tidy, 1)
        col{i} = loc_str(tidy{i}{j});
    end
    cols{j} = col;
end
p3_write_csv(fullfile(statDir, 'tidy_runs.csv'), hdr, cols);

% ---- aggregate CI (long format) ------------------------------------------
metricNames = {'rate_completed','rate_late','rate_rejected','quality_mean_per_arrival', ...
    'resp_mean','resp_p95','carbon_per_arrival','budget_used','budget_remaining', ...
    'budget_remaining_frac','rho_total','stage1_wait_mean','utilization_over_0_to_T_arr', ...
    'max_concurrency_in_horizon','n_rejected_budget','n_upgrade_dropped_deadline', ...
    'n_attrib_budget','n_attrib_deadline','n_attrib_horizon','n_attrib_none','N_arr'};
ciRows = {};
blocks = {};
cases = {};
seeds = [];
for i = 1:size(tidy, 1)
    blocks{end+1, 1} = tidy{i}{2}; %#ok<AGROW>
    cases{end+1, 1} = tidy{i}{3}; %#ok<AGROW>
    seeds(end+1, 1) = tidy{i}{5}; %#ok<AGROW>
end
uc = unique(cases);
for c = 1:numel(uc)
    sel = strcmp(cases, uc{c});
    for mi = 1:numel(metricNames)
        [vals, vidx] = col_num(cols, hdr, metricNames{mi});
        v = vals(sel);
        v = v(vidx(sel));
        nv = v(~isnan(v));
        nmiss = sum(isnan(v));
        if isempty(nv)
            mu = NaN; sdv = NaN; se = NaN; lo = NaN; hi = NaN;
        else
            mu = mean(nv);
            if numel(nv) > 1
                sdv = std(nv, 0);
                se = sdv / sqrt(numel(nv));
                tc = t_crit(numel(nv));
                lo = mu - tc * se;
                hi = mu + tc * se;
            else
                sdv = NaN; se = NaN; lo = NaN; hi = NaN;
            end
        end
        ciRows(end+1, :) = {blocks{find(sel, 1)}, uc{c}, metricNames{mi}, ...
            sprintf('%d', numel(v)), sprintf('%d', numel(nv)), sprintf('%d', nmiss), ...
            fmtn(mu), fmtn(sdv), fmtn(se), fmtn(lo), fmtn(hi)}; %#ok<AGROW>
    end
end
p3_write_csv(fullfile(statDir, 'aggregate_ci.csv'), ...
    {'block','case_id','metric','n_rows','n_valid','n_missing','mean','sd','se','ci95_lo','ci95_hi'}, ...
    cols_of(ciRows, 11));

% ---- E3 scanned axes: paired deltas vs common baseline E3_W1800 ------------
e3 = e3_axes(cols, hdr);
p3_write_csv(fullfile(statDir, 'delta_boundary.csv'), ...
    {'axis','level_case','level_value','reference_case','metric','n_pairs','n_missing', ...
     'mean_delta','sd_delta','ci95_lo','ci95_hi','sign_of_mean','crossing_statement'}, ...
    cols_of(e3.rows, 13));
write_text(fullfile(statDir, 'boundary_report.md'), e3.report);

% ---- E1 windows and E2 axes ----------------------------------------------
e1 = e1_table(cols, hdr);
p3_write_csv(fullfile(statDir, 'e1_windows.csv'), ...
    {'window_case','window_offset','mode','metric','n_valid','mean','sd','ci95_lo','ci95_hi'}, ...
    cols_of(e1, 9));
e2 = e2_table(cols, hdr);
p3_write_csv(fullfile(statDir, 'e2_axes.csv'), ...
    {'contrast','pair_a','pair_b','metric','n_pairs','n_missing','mean_delta','sd_delta','ci95_lo','ci95_hi'}, ...
    cols_of(e2, 10));

write_schema(fullfile(statDir, 'schema.md'));
rebuild_manifest(thisDir, outRoot, statDir, n);
fprintf('P3X_AGGREGATE_DONE %s (rows=%d)\n', statDir, n);
end

% ===================== helpers ============================================
function row = base_row(cfg, runDir)
st = '';
ch = '';
if exist(fullfile(runDir, 'receipt.json'), 'file') == 2
    rc = jsondecode(fileread(fullfile(runDir, 'receipt.json')));
    st = char(rc.status);
    ch = char(rc.config_hash);
end
row = {cfg.run_id, cfg.block, cfg.case_id, sprintf('%d', cfg.seed), cfg.seed, ...
    cfg.offset, cfg.first_index, cfg.strategy, sprintf('%d', cfg.C), ...
    cfg.lambda, cfg.max_defer_s, cfg.rho_route, cfg.bias, cfg.carbon_sigma, ...
    cfg.demand_M, cfg.T_arr, cfg.W_batch, cfg.budget_mode, st, ch, ...
    char(p3_now_iso())};
end

function h = base_hdr()
h = {'matrix_run_id','block','case_id','seed','seed_num','offset','first_index', ...
    'strategy','C','lambda','max_defer_s','rho_route','bias','carbon_sigma', ...
    'demand_M','T_arr_s','W_batch_s','budget_mode','run_status','config_hash','aggregated_at'};
end

function v = metric_vals(mm)
names = {'N_arr','n_completed','n_late','n_rejected','rate_completed','rate_late', ...
    'rate_rejected','quality_total','quality_mean_per_arrival','resp_mean','resp_p95', ...
    'resp_max','rho_total','B','budget_used','budget_remaining','carbon_total', ...
    'carbon_per_arrival','strong_share','n_upgrade_dropped_deadline'};
v = cell(1, numel(names) + 1);
for k = 1:numel(names)
    if isfield(mm, names{k})
        v{k} = double(mm.(names{k}));
    else
        v{k} = NaN;
    end
end
if isfield(mm, 'B') && isfield(mm, 'budget_used') && ~isnan(v{strcmp(names, 'B')}) && v{strcmp(names, 'B')} > 0
    v{end} = v{strcmp(names, 'budget_remaining')} / v{strcmp(names, 'B')};
else
    v{end} = NaN;
end
end

function h = metric_hdr()
h = {'N_arr','n_completed','n_late','n_rejected','rate_completed','rate_late', ...
    'rate_rejected','quality_total','quality_mean_per_arrival','resp_mean','resp_p95', ...
    'resp_max','rho_total','B','budget_used','budget_remaining','carbon_total', ...
    'carbon_per_arrival','strong_share','n_upgrade_dropped_deadline','budget_remaining_frac'};
end

function v = supp_vals(runDir)
names = {'stage1_wait_mean','stage1_wait_p95','stage1_wait_max','utilization_over_0_to_T_arr', ...
    'max_concurrency_in_horizon','n_rejected_budget','n_with_stage1_window'};
v = cell(1, numel(names));
for k = 1:numel(names)
    v{k} = NaN;
end
f = fullfile(runDir, 'supplement_metrics.csv');
if isempty(runDir) || exist(f, 'file') ~= 2
    return;
end
% manual parse: readtable auto-delimiter detection breaks on this file's
% heterogeneous unit_note text; name and value are always fields 1 and 2
txt = fileread(f);
lines = regexp(txt, '\r?\n', 'split');
for li = 1:numel(lines)
    ln = strtrim(lines{li});
    if isempty(ln) || strncmp(ln, 'name,', 5)
        continue;
    end
    p = strsplit(ln, ',');
    if numel(p) < 2
        continue;
    end
    nm = strrep(strtrim(p{1}), '"', '');
    tok = strrep(strtrim(p{2}), '"', '');
    for k = 1:numel(names)
        if strcmp(nm, names{k})
            v{k} = str2double(tok);
        end
    end
end
end

function h = supp_hdr()
h = {'stage1_wait_mean','stage1_wait_p95','stage1_wait_max','utilization_over_0_to_T_arr', ...
    'max_concurrency_in_horizon','n_rejected_budget','n_with_stage1_window'};
end

function v = attrib_vals(runDir)
v = {NaN, NaN, NaN, NaN};
f = fullfile(runDir, 'attribution.csv');
if isempty(runDir) || exist(f, 'file') ~= 2
    return;
end
A = readtable(f, 'TextType', 'string');
avn = A.Properties.VariableNames;
j = find(strcmp(avn, 'primary_cause'), 1);
if isempty(j)
    j = 3;   % frozen attribution.csv column order
end
pc = cellstr(A.(avn{j}));
v = {sum(strcmp(pc, 'budget')), sum(strcmp(pc, 'deadline')), ...
    sum(strcmp(pc, 'horizon')), sum(strcmp(pc, 'none'))};
end

function h = attrib_hdr()
h = {'n_attrib_budget','n_attrib_deadline','n_attrib_horizon','n_attrib_none'};
end

function [vals, valid] = col_num(cols, hdr, name)
j = find(strcmp(hdr, name), 1);
c = cols{j};
vals = nan(numel(c), 1);
valid = false(numel(c), 1);
for i = 1:numel(c)
    x = c{i};
    if isnumeric(x)
        vals(i) = x;
    else
        vals(i) = str2double(x);
    end
    valid(i) = ~isnan(vals(i));
end
end

function s = loc_str(x)
% p3_write_csv writes cell entries as char; numbers must be pre-formatted
if isnumeric(x)
    if isnan(x)
        s = 'NaN';
    else
        s = sprintf('%.17g', x);
    end
else
    s = char(x);
end
end

function s = fmtn(x)
if isnan(x)
    s = 'NaN';
else
    s = sprintf('%.17g', x);
end
end

function cols = cols_of(rows, k)
cols = cell(1, k);
for j = 1:k
    col = cell(size(rows, 1), 1);
    for i = 1:size(rows, 1)
        col{i} = rows{i, j};
    end
    cols{j} = col;
end
end

function tc = t_crit(n)
% two-sided 95% t critical values (df = n-1), 1..30; 1.96 beyond
tab = [12.706,4.303,3.182,2.776,2.571,2.447,2.365,2.306,2.262,2.228, ...
    2.201,2.179,2.160,2.145,2.131,2.120,2.110,2.101,2.093,2.086, ...
    2.080,2.074,2.069,2.064,2.060,2.056,2.052,2.048,2.045,2.042];
if n <= 1
    tc = NaN;
elseif n - 1 <= numel(tab)
    tc = tab(n - 1);
else
    tc = 1.96;
end
end

function out = e3_axes(cols, hdr)
% paired deltas vs the common E3 baseline cell E3_W1800 (rho=0, bias=0,
% sigma=0, max_defer=1800), same seeds -> common potential outcomes
[ca, ~] = col_str(cols, hdr, 'case_id');
[seed, ~] = col_num(cols, hdr, 'seed_num');
out = struct('rows', {{}}, 'report', '');
axesDef = {
    'max_defer_s', {'E3_W0','E3_W300','E3_W900'}, 'E3_W1800', [0, 300, 900]
    'rho_route',   {'E3_R0.02','E3_R0.1','E3_R0.5'}, 'E3_W1800', [0.02, 0.1, 0.5]
    'bias',        {'E3_B-40','E3_B40'}, 'E3_W1800', [-40, 40]
    'carbon_sigma',{'E3_N10','E3_N40'}, 'E3_W1800', [10, 40]
};
metrics = {'quality_mean_per_arrival','carbon_per_arrival','resp_mean','budget_used','rate_completed'};
rep = sprintf('# E3 scanned-axis boundary honesty report\n\n');
rep = [rep sprintf('Paired deltas are per-seed (common seeds, common potential trajectories) against the single common baseline cell E3_W1800. ')];
rep = [rep sprintf('A zero crossing is claimed ONLY if the mean paired delta changes sign between two adjacent scanned levels; then only the bracket is reported. ')];
rep = [rep sprintf('No interpolated/critical value is produced anywhere; local densification was NOT performed (it would require a frozen rule and a new exploration version).\n\n')];
rows = {};
for a = 1:size(axesDef, 1)
    axisName = axesDef{a, 1};
    lvCases = axesDef{a, 2};
    refCase = axesDef{a, 3};
    lvVals = axesDef{a, 4};
    rep = [rep sprintf('## axis %s (reference %s)\n\n', axisName, refCase)]; %#ok<AGROW>
    rep = [rep sprintf('Scanned levels: [%s]. The reference cell has level 0 (delta=0 by construction). ', strjoin(arrayfun(@(x) sprintf('%g', x), lvVals, 'UniformOutput', false), ','))]; %#ok<AGROW>
    if any(lvVals < 0) && any(lvVals > 0)
        rep = [rep sprintf('NOTE: scanned levels lie on BOTH sides of the reference 0; a sign-change bracket spanning them contains the reference itself and is NOT a critical-threshold claim.')];
    end
    rep = [rep sprintf('\n\n')];
    for mi = 1:numel(metrics)
        [vals, ~] = col_num(cols, hdr, metrics{mi});
        refMap = containers.Map('KeyType', 'double', 'ValueType', 'double');
        for i = 1:numel(ca)
            if strcmp(ca{i}, refCase)
                refMap(seed(i)) = vals(i);
            end
        end
        means = nan(numel(lvCases), 1);
        for li = 1:numel(lvCases)
            d = [];
            nmiss = 0;
            for i = 1:numel(ca)
                if strcmp(ca{i}, lvCases{li})
                    if isKey(refMap, seed(i)) && ~isnan(vals(i)) && ~isnan(refMap(seed(i)))
                        d(end+1) = vals(i) - refMap(seed(i)); %#ok<AGROW>
                    else
                        nmiss = nmiss + 1;
                    end
                end
            end
            if isempty(d)
                mu = NaN; sdv = NaN; lo = NaN; hi = NaN;
            else
                mu = mean(d);
                if numel(d) > 1
                    sdv = std(d, 0);
                    tc = t_crit(numel(d));
                    lo = mu - tc * sdv / sqrt(numel(d));
                    hi = mu + tc * sdv / sqrt(numel(d));
                else
                    sdv = NaN; lo = NaN; hi = NaN;
                end
            end
            means(li) = mu;
            rows(end+1, :) = {axisName, lvCases{li}, sprintf('%.17g', lvVals(li)), ...
                refCase, metrics{mi}, sprintf('%d', numel(d)), sprintf('%d', nmiss), ...
                fmtn(mu), fmtn(sdv), fmtn(lo), fmtn(hi), sign_word(mu), 'pending'}; %#ok<AGROW>
        end
        stmt = crossing_stmt(lvVals, means);
        for r = size(rows, 1) - numel(lvCases) + 1:size(rows, 1)
            rows{r, 13} = stmt;
        end
        rep = [rep sprintf('- %s: %s\n', metrics{mi}, stmt)]; %#ok<AGROW>
    end
    rep = [rep sprintf('\n')]; %#ok<AGROW>
end
out.rows = rows;
out.report = rep;
end

function s = sign_word(mu)
if isnan(mu)
    s = 'NaN';
elseif mu > 0
    s = 'positive';
elseif mu < 0
    s = 'negative';
else
    s = 'zero';
end
end

function stmt = crossing_stmt(lv, means)
% HONEST crossing statement over the SCANNED levels only
ok = ~isnan(means);
if sum(ok) < 2
    stmt = 'insufficient_valid_levels';
    return;
end
sc = 0;
bracket = '';
for k = 2:numel(means)
    if isnan(means(k)) || isnan(means(k-1))
        continue;
    end
    if means(k-1) == 0 || means(k) == 0 || sign(means(k-1)) ~= sign(means(k))
        sc = sc + 1;
        bracket = sprintf('[%g,%g]', lv(k-1), lv(k));
    end
end
if sc == 0
    stmt = 'no_zero_crossing_observed (scanned levels only; NO critical value produced)';
else
    extra = '';
    if any(lv < 0) && any(lv > 0)
        extra = '; NOTE bracket spans both sides of reference 0 (delta=0 there by construction), so this is NOT a critical-threshold claim';
    end
    stmt = sprintf('zero crossing bracketed in %s across scanned levels; %d sign change(s); NO interpolated critical value; densification requires a frozen rule + new exploration version%s', bracket, sc, extra);
end
end

function t = e1_table(cols, hdr)
[ca, ~] = col_str(cols, hdr, 'case_id');
[off, ~] = col_num(cols, hdr, 'offset');
[seed, ~] = col_num(cols, hdr, 'seed_num');
metrics = {'rate_completed','quality_mean_per_arrival','carbon_per_arrival','resp_mean'};
t = {};
uc = unique(ca);
for c = 1:numel(uc)
    if isempty(strfind(uc{c}, 'E1_')) %#ok<STREMP>
        continue;
    end
    parts = strsplit(uc{c}, '_');
    mode = parts{end};
    for mi = 1:numel(metrics)
        [vals, ~] = col_num(cols, hdr, metrics{mi});
        v = [];
        for i = 1:numel(ca)
            if strcmp(ca{i}, uc{c}) && ~isnan(vals(i))
                v(end+1) = vals(i); %#ok<AGROW>
            end
        end
        if isempty(v)
            t(end+1, :) = {uc{c}, sprintf('%d', off(find(strcmp(ca, uc{c}), 1))), mode, ...
                metrics{mi}, '0', 'NaN', 'NaN', 'NaN', 'NaN'}; %#ok<AGROW>
        else
            mu = mean(v);
            if numel(v) > 1
                sdv = std(v, 0);
                tc = t_crit(numel(v));
                lo = mu - tc * sdv / sqrt(numel(v));
                hi = mu + tc * sdv / sqrt(numel(v));
            else
                sdv = NaN; lo = NaN; hi = NaN;
            end
            t(end+1, :) = {uc{c}, sprintf('%d', off(find(strcmp(ca, uc{c}), 1))), mode, ...
                metrics{mi}, sprintf('%d', numel(v)), fmtn(mu), fmtn(sdv), fmtn(lo), fmtn(hi)}; %#ok<AGROW>
        end
    end
end
end

function t = e2_table(cols, hdr)
[ca, ~] = col_str(cols, hdr, 'case_id');
[seed, ~] = col_num(cols, hdr, 'seed_num');
metrics = {'quality_mean_per_arrival','carbon_per_arrival','resp_mean','rate_rejected','budget_used'};
contrasts = {
    'E2A_budget_tight_vs_high_lambda0.1_C1', 'E2A_l0.1_C1_TBD_high', 'E2A_l0.1_C1_TBD_tight'
    'E2A_budget_tight_vs_high_lambda0.1_C4', 'E2A_l0.1_C4_TBD_high', 'E2A_l0.1_C4_TBD_tight'
    'E2A_budget_tight_vs_high_lambda1_C1',   'E2A_l1_C1_TBD_high',   'E2A_l1_C1_TBD_tight'
    'E2A_budget_tight_vs_high_lambda1_C4',   'E2A_l1_C4_TBD_high',   'E2A_l1_C4_TBD_tight'
    'E2A_capacity_C4minus_C1_lambda0.1_tight','E2A_l0.1_C4_TBD_tight','E2A_l0.1_C1_TBD_tight'
    'E2A_capacity_C4minus_C1_lambda0.1_high', 'E2A_l0.1_C4_TBD_high', 'E2A_l0.1_C1_TBD_high'
    'E2A_capacity_C4minus_C1_lambda1_tight',  'E2A_l1_C4_TBD_tight',  'E2A_l1_C1_TBD_tight'
    'E2A_capacity_C4minus_C1_lambda1_high',   'E2A_l1_C4_TBD_high',   'E2A_l1_C1_TBD_high'
    'E2B_demand_d2scaled_minus_d1scaled',     'E2B_d2_scaled',        'E2B_d1_scaled'
    'E2B_demand_d2fixed_minus_d1scaled',      'E2B_d2_fixed',         'E2B_d1_scaled'
};
t = {};
for ci = 1:size(contrasts, 1)
    for mi = 1:numel(metrics)
        [vals, ~] = col_num(cols, hdr, metrics{mi});
        d = [];
        nmiss = 0;
        seedsA = seed(strcmp(ca, contrasts{ci, 2}));
        for i = 1:numel(ca)
            if strcmp(ca{i}, contrasts{ci, 2})
                jb = find(strcmp(ca, contrasts{ci, 3}) & seed == seed(i), 1);
                if ~isempty(jb) && ~isnan(vals(i)) && ~isnan(vals(jb))
                    d(end+1) = vals(i) - vals(jb); %#ok<AGROW>
                else
                    nmiss = nmiss + 1;
                end
            end
        end
        if isempty(d)
            mu = NaN; sdv = NaN; lo = NaN; hi = NaN;
        else
            mu = mean(d);
            if numel(d) > 1
                sdv = std(d, 0);
                tc = t_crit(numel(d));
                lo = mu - tc * sdv / sqrt(numel(d));
                hi = mu + tc * sdv / sqrt(numel(d));
            else
                sdv = NaN; lo = NaN; hi = NaN;
            end
        end
        t(end+1, :) = {contrasts{ci, 1}, contrasts{ci, 2}, contrasts{ci, 3}, ...
            metrics{mi}, sprintf('%d', numel(d)), sprintf('%d', nmiss), ...
            fmtn(mu), fmtn(sdv), fmtn(lo), fmtn(hi)}; %#ok<AGROW>
    end
end
end

function [vals, valid] = col_str(cols, hdr, name)
j = find(strcmp(hdr, name), 1);
c = cols{j};
vals = cell(numel(c), 1);
valid = true(numel(c), 1);
for i = 1:numel(c)
    vals{i} = char(c{i});
end
end

function write_text(file, txt)
fid = fopen(file, 'w', 'n', 'UTF-8');
fwrite(fid, txt, 'char');
fclose(fid);
end

function rebuild_manifest(thisDir, outRoot, statDir, n)
% raw_manifest.csv merge across bounded foreground shard invocations is known
% to lose prior-invocation rows (per-invocation overwrites observed); the
% authoritative record is the 304 per-run receipts, so the manifest is REBUILT
% from them here and both files are kept.
T = readtable(fullfile(thisDir, 'run_matrix.csv'), 'TextType', 'string');
vn = T.Properties.VariableNames;
rows = {};
for i = 1:n
    s = struct();
    for k = 1:numel(vn)
        s.(vn{k}) = T.(vn{k})(i);
    end
    cfg = p3x_cfg_from_row(s);
    runDir = fullfile(outRoot, 'runs', cfg.case_id, sprintf('seed_%d', cfg.seed));
    rec = struct('status', 'missing', 'config_hash', '', 'started_at', '', ...
        'finished_at', '', 'reused', false, 'N_arr', NaN);
    if exist(fullfile(runDir, 'receipt.json'), 'file') == 2
        rec = jsondecode(fileread(fullfile(runDir, 'receipt.json')));
    end
    wall = NaN;
    if isfield(rec, 'started_at') && isfield(rec, 'finished_at')
        try
            a = char(rec.started_at);
            b = char(rec.finished_at);
            a = a(1:min(23, numel(a)));
            b = b(1:min(23, numel(b)));
            t0 = datenum(a, 'yyyy-mm-dd HH:MM:SS.FFF');
            t1 = datenum(b, 'yyyy-mm-dd HH:MM:SS.FFF');
            wall = (t1 - t0) * 86400;
        catch
            wall = NaN;
        end
    end
    rows(end+1, :) = {cfg.run_id, cfg.case_id, cfg.block, sprintf('%d', cfg.seed), ...
        sprintf('%d', mod(i - 1, 8) + 1), char(rec.config_hash), char(rec.status), ...
        lower(mat2str(logical(rec.reused))), ...
        ['06_results/' proj_id(outRoot) '/runs/' cfg.case_id '/seed_' sprintf('%d', cfg.seed)], ...
        char(rec.started_at), char(rec.finished_at), fmtn(wall), ...
        fmtn(rec.N_arr)}; %#ok<AGROW>
end
cols = cols_of(rows, 13);
p3_write_csv(fullfile(statDir, 'raw_manifest_rebuilt.csv'), ...
    {'matrix_run_id','case_id','block','seed','shard','config_hash','status','reused', ...
     'out_dir','started_at','finished_at','wall_seconds','N_arr'}, cols);
end

function id = proj_id(outRoot)
[~, id] = fileparts(outRoot);
end

function write_schema(file)
txt = sprintf([ ...
    '# final_matrix_stats schema\n\n' ...
    'Generated by p3x_aggregate.m from the frozen run_matrix.csv (304 rows) and the raw per-run artifacts under runs/<case_id>/seed_<seed>/.\n\n' ...
    '- tidy_runs.csv: one row per (matrix_run_id, seed). Factors are the frozen matrix columns; metrics mirror metrics.json + supplement_metrics.csv + attribution.csv.\n' ...
    '- aggregate_ci.csv: long format per (block, case_id, metric); mean/sd/se/95%% two-sided t-CI over the 8 common seeds; n_missing counts NaN (missing is NEVER replaced by 0).\n' ...
    '- delta_boundary.csv / boundary_report.md: E3 scanned-axis paired deltas vs the common baseline cell E3_W1800 (same seeds = common potential outcomes). crossing_statement is honest: ' ...
    '"no_zero_crossing_observed" means zero was never crossed on the scanned levels and NO critical value exists; a crossing yields only a bracket; no interpolation, no densification.\n' ...
    '- e1_windows.csv: per-window per-mode descriptive statistics (windows are NOT i.i.d.; cross-window aggregation is descriptive only).\n' ...
    '- e2_axes.csv: paired (by seed) contrasts; budget axis at FIXED absolute budget across C (X1-3), capacity axis at fixed budget, demand axis d1 subset of d2.\n' ...
    'NaN policy: empty/undefined statistics are written as NaN; count metrics of empty sets are NaN, not 0.\n' ...
    'Units: time seconds; carbon = relative carbon index (NOT measured gCO2); quality dimensionless; all scenarios are SUPPLEMENT DEVELOPMENT / MECHANISM CONSTRUCTED.\n']);
write_text(file, txt);
end
