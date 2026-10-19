function traj = p3x_micro_traj(a, d, gtype)
%P3X_MICRO_TRAJ Hand-checkable deterministic micro trajectory (dev acceptance).
% Potential outcomes are fixed constants so that budget / deadline / conservation
% expectations can be verified by hand. No RNG.
n = numel(a);
traj = struct();
traj.a = a(:);
traj.d = d(:);
traj.gtype = cell(n, 1);
if ischar(gtype), traj.gtype(:) = {gtype}; else, traj.gtype = gtype(:); end
traj.x = 0.5 * ones(n, 1);
traj.q_light = 0.5 * ones(n, 1);
traj.q_strong = 0.9 * ones(n, 1);
traj.gain = 0.1 * ones(n, 1);
traj.extra_fail = false(n, 1);
traj.qhat_light = traj.q_light;
traj.qhat_strong = traj.q_strong;
traj.qhat_gain = traj.gain;
traj.truth_unsat = traj.q_light < 0.7;
traj.verdict_unsat = traj.truth_unsat;
traj.fb_missing = false(n, 1);
traj.u_route = 0.5 * ones(n, 1);
traj.c_noise = zeros(64, 1);
traj.N = n;
traj.meta = struct('seed', NaN, 'generator', 'p3x_micro_traj', ...
    'generated_at', p3_now_iso(), 'note', 'fixed micro instance (dev acceptance)');
end
