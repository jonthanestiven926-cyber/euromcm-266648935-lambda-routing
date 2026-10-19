function [B, cellRec] = p3x_resolve_budget(rootDir, run_id, lambda, C, level)
%P3X_RESOLVE_BUDGET Resolve E2A budget levels per 01_PROTOCOL_AMENDMENT_X1 X1-3.
% UNIFIED absolute budget across capacities for each lambda and level:
%     B_tight(lambda) = 0.5 * C_full(lambda, C=1)     (min-capacity anchor)
%     B_high(lambda)  = 1.2 * C_full(lambda, C=4)     (max-capacity anchor)
% The same numeric B is used for C=1 and C=4 of that lambda, so the final grid
% sweeps capacity at FIXED budget (no capacity/budget confounding). Levels are
% dev-calibrated at seed 20261018 (pre-fixed rule, not final tuning); a raised
% gate factor re-freezes B_high BEFORE any final run (never a text-only change).
% The calibrated values live in the dev calibration artifact and are hash-bound
% by p3x_freeze; this function is the single resolution path used by the runner.
lvl = lower(char(level));
if ~strcmp(lvl, 'tight') && ~strcmp(lvl, 'high')
    error('p3x:BudgetLevel', 'level must be tight|high, got %s', char(level));
end
if ~any(C == [1, 4])
    error('p3x:BudgetLevel', 'X1-3 anchors assume C in {1,4}, got C=%d', C);
end
calFile = fullfile(rootDir, '06_results', run_id, 'dev_acceptance', ...
    'budget_calibration', 'budget_calibration.json');
if exist(calFile, 'file') ~= 2
    error('p3x:BudgetCalibration', ...
        'calibration artifact missing (run the dev calibration before any TBD-level run): %s', calFile);
end
cal = jsondecode(fileread(calFile));
key = sprintf('lambda=%.17g', lambda);
cellRec = [];
for k = 1:numel(cal.cells)
    if strcmp(cal.cells(k).key, key)
        cellRec = cal.cells(k);
        break;
    end
end
if isempty(cellRec)
    error('p3x:BudgetCalibration', 'no calibration cell for %s', key);
end
if strcmp(lvl, 'tight')
    B = cellRec.B_tight;
else
    B = cellRec.B_high_final;
end
% cross-capacity identity is a hard property of the resolution, not a label
if ~isequal(B, cellRec.B_tight) && ~isequal(B, cellRec.B_high_final)
    error('p3x:BudgetUnified', 'resolved budget not bound to a unified level');
end
end
