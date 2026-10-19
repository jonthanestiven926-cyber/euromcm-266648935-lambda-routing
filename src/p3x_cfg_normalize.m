function cfg = p3x_cfg_normalize(cfg)
%P3X_CFG_NORMALIZE Fill defaults and validate one supplement run config.
reqf = {'block','case_id','seed','offset','first_index','strategy','carbon_sched', ...
    'predictor','lambda','C','budget_mode','T_arr','W_batch','d_int','lag_s', ...
    'rho_route','bias','carbon_sigma','demand_M'};
for k = 1:numel(reqf)
    if ~isfield(cfg, reqf{k})
        error('p3x:Config', 'missing config field: %s', reqf{k});
    end
end
if ~isfield(cfg, 'run_id') || isempty(cfg.run_id), cfg.run_id = 'DEV'; end
if ~isfield(cfg, 'note') || isempty(cfg.note), cfg.note = 'dev acceptance'; end
if ~isfield(cfg, 'B_per_request') || isempty(cfg.B_per_request), cfg.B_per_request = NaN; end
if ~isfield(cfg, 'B_abs') || isempty(cfg.B_abs), cfg.B_abs = NaN; end
if ~isfield(cfg, 'max_defer_s') || isempty(cfg.max_defer_s)
    cfg.max_defer_s = inf;
elseif ischar(cfg.max_defer_s) || isstring(cfg.max_defer_s)
    s = char(cfg.max_defer_s);
    if strcmpi(s, 'full') || isempty(strtrim(s))
        cfg.max_defer_s = inf;
    else
        cfg.max_defer_s = str2double(s);
        if isnan(cfg.max_defer_s)
            error('p3x:Config', 'bad max_defer_s: %s', s);
        end
    end
end
if ischar(cfg.carbon_sched) || isstring(cfg.carbon_sched)
    cfg.carbon_sched = strcmpi(char(cfg.carbon_sched), 'true');
end
cfg.carbon_sched = logical(cfg.carbon_sched);
if strcmp(cfg.budget_mode, 'scaled') && ~(cfg.B_per_request > 0)
    error('p3x:Config', 'scaled budget needs B_per_request > 0');
end
if strcmp(cfg.budget_mode, 'fixed_abs') && isnumeric(cfg.B_abs) && ~isempty(cfg.B_abs) ...
        && ~isnan(cfg.B_abs) && ~(cfg.B_abs > 0)
    error('p3x:Config', 'fixed_abs budget needs B_abs > 0');
end
if ~any(strcmp(cfg.budget_mode, {'scaled','fixed_abs'}))
    error('p3x:Config', 'unknown budget_mode: %s', cfg.budget_mode);
end
if ~(cfg.lag_s >= 0), error('p3x:Config', 'lag_s must be >= 0'); end
end
