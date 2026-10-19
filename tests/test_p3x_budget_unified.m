function test_p3x_budget_unified(rootDir, run_id)
%TEST_P3X_BUDGET_UNIFIED X1-3: fixed absolute budget sweeps capacity.
% The FINAL E2A grid (64 rows) must resolve to the SAME numeric absolute budget
% for C=1 and C=4 within each (seed, lambda, budget level) -- compared through
% the actual runner resolution path (p3x_cfg_from_row -> p3x_resolve_budget),
% bitwise on the resolved doubles, not on labels. Also checks that the four
% prototype cells' MEASURED budget_remaining / utilization (dev evidence from
% test_p3x_saturation) fall in the expected intervals.
if nargin < 2, run_id = '20261018_171608_963_p3_supplement'; end
outRoot = fullfile(rootDir, '06_results', run_id);
devDir = fullfile(outRoot, 'dev_acceptance', 'test_p3x_budget_unified');
if exist(devDir, 'dir') ~= 7, mkdir(devDir); end
thisDir = fileparts(mfilename('fullpath'));

T = readtable(fullfile(thisDir, 'run_matrix.csv'), 'TextType', 'string');
vn = T.Properties.VariableNames;
nE2A = 0;
rows = {};
groupKey = {};
groupB = {};
groupC = {};
for i = 1:height(T)
    s = struct();
    for k = 1:numel(vn)
        s.(vn{k}) = T.(vn{k})(i);
    end
    if ~strcmp(char(s.block), 'E2A')
        continue;
    end
    nE2A = nE2A + 1;
    cfg = p3x_cfg_from_row(s);
    assert(ischar(cfg.B_abs) || isstring(cfg.B_abs), 'p3x:BudgetUnified', ...
        'E2A row %s must carry a TBD budget token', cfg.case_id);
    tok = char(cfg.B_abs);
    level = erase(tok, 'TBD_');
    [B, cellRec] = p3x_resolve_budget(rootDir, run_id, cfg.lambda, cfg.C, level);
    assert(isfinite(B) && B > 0, 'p3x:BudgetUnified', 'resolved budget must be positive');
    gk = sprintf('seed=%d|lambda=%.17g|level=%s', cfg.seed, cfg.lambda, level);
    groupKey{end+1, 1} = gk; %#ok<AGROW>
    groupB{end+1, 1} = B; %#ok<AGROW>
    groupC{end+1, 1} = cfg.C; %#ok<AGROW>
    rows(end+1, :) = {cfg.run_id, sprintf('%d', cfg.seed), sprintf('%.17g', cfg.lambda), ...
        sprintf('%d', cfg.C), level, sprintf('%.17g', B), ...
        sprintf('%.17g', cellRec.C_full_C1), sprintf('%.17g', cellRec.C_full_C4), ...
        sprintf('%.17g', cellRec.gate_factor), p3x_config_hash(cfg)}; %#ok<AGROW>
end
assert(nE2A == 64, 'p3x:BudgetUnified', 'final grid must contain 64 E2A rows, got %d', nE2A);

% ---- bitwise cross-capacity identity per (seed, lambda, level) -------------
uk = unique(groupKey);
assert(numel(uk) == 32, 'p3x:BudgetUnified', ...
    'expected 32 (seed,lambda,level) groups x 2 capacities, got %d', numel(uk));
for g = 1:numel(uk)
    sel = strcmp(groupKey, uk{g});
    Cs = groupC(sel);
    Bs = groupB(sel);
    assert(numel(Bs) == 2 && numel(unique(cell2mat(Cs))) == 2, 'p3x:BudgetUnified', ...
        'group %s must contain exactly C=1 and C=4', uk{g});
    assert(isequal(Bs{1}, Bs{2}), 'p3x:BudgetUnified', ...
        'group %s: B(C=1)=%.17g ~= B(C=4)=%.17g -- capacity/budget confounding NOT removed', ...
        uk{g}, Bs{1}, Bs{2});
end
fprintf('  matrix resolution: 64 E2A rows -> 32 (seed,lambda,level) groups, cross-C budgets bitwise identical\n');

% ---- prototype intervals from MEASURED dev evidence -----------------------
repFile = fullfile(outRoot, 'dev_acceptance', 'test_p3x_saturation', 'saturation_report.csv');
assert(exist(repFile, 'file') == 2, 'p3x:BudgetUnified', ...
    'saturation_report.csv missing: run test_p3x_saturation first');
R = readtable(repFile, 'TextType', 'string');
lv = cellstr(R.level);
lam = loc_num(R.lambda);
Cc = loc_num(R.C);
brem = loc_num(R.budget_remaining);
remf = loc_num(R.budget_remaining_frac);
util = loc_num(R.utilization_0_Tarr);
bAbsCol = loc_num(R.B_abs);
pick = @(l, c, p) find(abs(lam - l) < 1e-12 & Cc == c & strcmp(lv, p), 1);
i1 = pick(1, 1, 'high');    % C1 + B_high at lambda=1
i2 = pick(0.1, 4, 'tight'); % C4 + B_tight at lambda=0.1
i3 = pick(1, 1, 'tight');   % C1 + B_tight at lambda=1
i4 = pick(0.1, 4, 'high');  % C4 + B_high at lambda=0.1
assert(~isempty(i1) && ~isempty(i2) && ~isempty(i3) && ~isempty(i4), ...
    'p3x:BudgetUnified', 'prototype rows missing from saturation report');
assert(brem(i1) > 0 && util(i1) > 0.70, 'p3x:BudgetUnified', ...
    'C1+B_high (lambda=1): measured remaining>0 and util>0.70 required');
assert(util(i2) < 0.25 && remf(i2) < 0.10, 'p3x:BudgetUnified', ...
    'C4+B_tight (lambda=0.1): measured util<0.25 and remaining<10%% required');
assert(remf(i3) < 0.10, 'p3x:BudgetUnified', ...
    'C1+B_tight (lambda=1): measured budget tightness required');
assert(brem(i4) > 0 && util(i4) < 0.25, 'p3x:BudgetUnified', ...
    'C4+B_high (lambda=0.1): measured remaining>0 and util<0.25 required');
% the dev runs themselves must have used the same unified numbers as the matrix
bh1 = unique(bAbsCol(strcmp(lv, 'high') & abs(lam - 1) < 1e-12));
bh01 = unique(bAbsCol(strcmp(lv, 'high') & abs(lam - 0.1) < 1e-12));
bt1 = unique(bAbsCol(strcmp(lv, 'tight') & abs(lam - 1) < 1e-12));
bt01 = unique(bAbsCol(strcmp(lv, 'tight') & abs(lam - 0.1) < 1e-12));
assert(numel(bh1) == 1 && numel(bh01) == 1 && numel(bt1) == 1 && numel(bt01) == 1, ...
    'p3x:BudgetUnified', 'dev runs within a lambda/level must share one absolute budget');
[Bt1, ~] = p3x_resolve_budget(rootDir, run_id, 1, 1, 'tight');
[Bh1, ~] = p3x_resolve_budget(rootDir, run_id, 1, 4, 'high');
[Bt01, ~] = p3x_resolve_budget(rootDir, run_id, 0.1, 1, 'tight');
[Bh01, ~] = p3x_resolve_budget(rootDir, run_id, 0.1, 4, 'high');
assert(isequal(bt1, Bt1) && isequal(bh1, Bh1) && isequal(bt01, Bt01) && isequal(bh01, Bh01), ...
    'p3x:BudgetUnified', 'measured dev budgets must equal the matrix resolution values');

% ---- audit trail ----------------------------------------------------------
hdr = {'matrix_run_id','seed','lambda','C','level','resolved_B_abs', ...
    'C_full_C1','C_full_C4','gate_factor','config_hash'};
cols = cell(1, numel(hdr));
for j = 1:numel(hdr)
    cols{j} = rows(:, j);
end
p3_write_csv(fullfile(devDir, 'budget_resolution_audit.csv'), hdr, cols);
fprintf('P3X_BUDGET_UNIFIED_PASS\n');
end

function v = loc_num(x)
% numeric column robust to readtable type detection (text or numeric)
if isnumeric(x)
    v = x;
else
    v = str2double(x);
end
end
