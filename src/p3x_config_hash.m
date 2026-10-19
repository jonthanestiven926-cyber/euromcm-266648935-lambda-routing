function h = p3x_config_hash(cfg)
%P3X_CONFIG_HASH Deterministic canonical hash of one run configuration.
% Fixed field order + full-precision values so that identical configs hash
% identically and reused outputs can be recognised (duplicate-baseline dedup).
f = {'block','case_id','run_id','seed','offset','first_index','strategy', ...
     'carbon_sched','predictor','lambda','C','budget_mode','B_per_request', ...
     'B_abs','T_arr','W_batch','d_int','lag_s','max_defer_s','rho_route', ...
     'bias','carbon_sigma','demand_M'};
c = struct();
for k = 1:numel(f)
    v = cfg.(f{k});
    if islogical(v), v = double(v); end
    if ischar(v), v = string(v); end
    c.(f{k}) = v;
end
h = p3_sha256_str(jsonencode(c));
end
