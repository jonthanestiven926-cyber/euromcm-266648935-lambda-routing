function [trajS, idx] = p3x_thin_traj(traj, marks)
%P3X_THIN_TRAJ Subset a precomputed exogenous trajectory by Bernoulli demand marks.
% Per 01_PROTOCOL_AMENDMENT_X1 (X1-2) the subset is defined by independent
% Bernoulli(0.5) marks m_k (p3x_demand_marks, dedicated substream, fixed per seed,
% never drifting with the policy) applied to a Poisson(2*lambda) base stream, so
% the kept substream is Poisson(lambda) by the thinning theorem (CV=1, NOT the
% Erlang-2 CV=0.707 that even-index extraction would produce).
% Shared requests keep arrival time / features / potential outcomes EXACTLY as in
% the base stream (nested subset, same base-stream index -> pairable). The carbon
% noise stream is kept unchanged so paired runs share the same exogenous noise.
if islogical(marks)
    if numel(marks) ~= traj.N
        error('p3x:BadMarks', 'logical marks must have one entry per base arrival');
    end
    idx = find(marks(:));
else
    idx = marks(:);   % explicit index vector (acceptance helpers)
end
trajS = traj;
fn = {'a','d','x','q_light','q_strong','gain','extra_fail','qhat_light', ...
      'qhat_strong','qhat_gain','truth_unsat','verdict_unsat','fb_missing','u_route'};
for k = 1:numel(fn)
    v = traj.(fn{k});
    trajS.(fn{k}) = v(idx);
end
trajS.gtype = traj.gtype(idx);
trajS.N = numel(idx);
trajS.meta = traj.meta;
trajS.meta.thinned_from_N = traj.N;
trajS.meta.thinned_index_rule = 'independent Bernoulli(0.5) marks (Poisson thinning theorem)';
trajS.meta.thinned_indices = idx;
trajS.meta.base_marks = marks;   % marks written into the trajectory (policy-independent)
end
