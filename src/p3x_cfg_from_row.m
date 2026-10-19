function cfg = p3x_cfg_from_row(s)
%P3X_CFG_FROM_ROW Convert one run_matrix.csv row (struct of strings/numbers) to cfg.
% Matrix tokens: max_defer_s ''/'full' -> Inf; B_abs '' -> NaN;
% B_abs '1.5*N1(d1 realized)' stays text and is resolved at run time (E2B d2_fixed).
cfg = struct();
cfg.run_id = loc_str(s.run_id);
cfg.block = loc_str(s.block);
cfg.case_id = loc_str(s.case_id);
cfg.seed = loc_num(s.seed);
cfg.offset = loc_num(s.offset);
cfg.first_index = loc_num(s.first_index);
cfg.strategy = loc_str(s.strategy);
cfg.carbon_sched = strcmpi(loc_str(s.carbon_sched), 'true');
cfg.predictor = loc_str(s.predictor);
cfg.lambda = loc_num(s.lambda);
cfg.C = loc_num(s.C);
cfg.budget_mode = loc_str(s.budget_mode);
cfg.T_arr = loc_num(s.T_arr);
cfg.W_batch = loc_num(s.W_batch);
cfg.d_int = loc_num(s.d_int);
cfg.lag_s = loc_num(s.lag_s);
cfg.rho_route = loc_num(s.rho_route);
cfg.bias = loc_num(s.bias);
cfg.carbon_sigma = loc_num(s.carbon_sigma);
cfg.demand_M = loc_num(s.demand_M);
cfg.note = loc_str(s.note);
cfg.B_per_request = NaN;
cfg.B_abs = NaN;
cfg.max_defer_s = inf;
t = strtrim(loc_str(s.B_per_request));
if ~isempty(t), cfg.B_per_request = str2double(t); end
t = strtrim(loc_str(s.B_abs));
if ~isempty(t)
    v = str2double(t);
    if isnan(v)
        cfg.B_abs = t;      % e.g. '1.5*N1(d1 realized)'
    else
        cfg.B_abs = v;
    end
end
t = strtrim(loc_str(s.max_defer_s));
if ~isempty(t)
    v = str2double(t);
    if isnan(v)
        if ~strcmpi(t, 'full')
            error('p3x:Config', 'bad max_defer_s token: %s', t);
        end
        cfg.max_defer_s = inf;
    else
        cfg.max_defer_s = v;
    end
end
cfg = p3x_cfg_normalize(cfg);
end

function s = loc_str(v)
if isnumeric(v)
    s = sprintf('%.17g', v);
elseif isstring(v)
    if isscalar(v) && ismissing(v)
        s = '';               % empty CSV cell -> <missing> string -> ''
    else
        s = char(v);
    end
else
    s = char(v);
end
end

function v = loc_num(x)
v = str2double(loc_str(x));
end
