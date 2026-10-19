function [fh, getlog] = p3x_make_signal(history, firstIndex, K, lag_s, mode, bias, carbon_sigma, noise)
%P3X_MAKE_SIGNAL Build the decision-time signal closure for p3x_simulate.
% The closure is the ONLY channel through which the policy-side observation
% receives carbon values (simulator environment keeps the true series for
% SCORING only). Every call is logged for the forecast-issuance audit:
%   (issue_s, latest_available, max_source_index, n_clamped, mode)
% Future-read guard: for causal modes a source index beyond the publication
% frontier raises p3x:FutureSource instead of silently leaking.
issT = zeros(0, 1); issLatest = zeros(0, 1); issMax = zeros(0, 1); issClamp = zeros(0, 1);
    function [gh, latest, msi] = sig(tt2)
        [gh, latest, msi, ncl] = p3x_signal(history, firstIndex, K, tt2, lag_s, mode, bias, carbon_sigma, noise);
        if numel(gh) ~= K || any(~isfinite(gh))
            error('p3x:SignalInvalid', 'signal must be finite length-K at t=%.3f', tt2);
        end
        if any(strcmp(mode, {'persistence', 'seasonal'})) && msi > latest
            error('p3x:FutureSource', 'causal source index %d beyond frontier %d at t=%.3f', ...
                msi, latest, tt2);
        end
        issT(end+1, 1) = tt2; issLatest(end+1, 1) = latest; ...
            issMax(end+1, 1) = msi; issClamp(end+1, 1) = ncl;
    end
    function L = get_log_impl()
        L = struct('mode', mode, 'issue_s', issT, 'latest_available', issLatest, ...
            'max_source_index', issMax, 'n_clamped', issClamp);
    end
fh = @sig;
getlog = @get_log_impl;
end
