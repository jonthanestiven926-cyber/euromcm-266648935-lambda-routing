function [forecast, latest_available, max_source_index, n_clamped] = p3x_signal(history, firstIndex, K, issue_s, lag_s, mode, bias, carbon_sigma, noise)
%P3X_SIGNAL Pure causal carbon forecast for the P3 supplement (E1/E3).
% Frozen semantics (00_PROTOCOL.md sec.0-3, X1 review PASS, X2 review PASS):
%   * history     : concatenated SAFE train+validation actual series (1344+672),
%                   never sealed test. Values are whole 30-min intervals.
%   * firstIndex  : 1-based index of the FIRST target interval (sim t=0 starts
%                   at the start of interval firstIndex).
%   * K           : number of target intervals (targets = firstIndex..firstIndex+K-1).
%   * issue_s     : forecast issue time in seconds relative to interval
%                   firstIndex start (simulation decision time).
%   * lag_s       : publication latency; interval m is fully published only at
%                   its END + lag_s  (conservative END+lag rule).
%   * mode        : 'persistence' | 'seasonal' | 'oracle' | 'oracle_noise'.
%   * bias        : deterministic known bias added ONLY to forecast/unknown cells.
%   * carbon_sigma: recorded noise level (gCO2/kWh) for 'oracle_noise'.
%   * noise       : OPTIONAL precomputed exogenous noise vector (already scaled
%                   to gCO2/kWh by the caller; simulator NEVER calls RNG here).
%
% Outputs:
%   forecast          : K x 1 forecast for the target intervals (>= 0).
%   latest_available  : publication frontier index at issue_s (clipped to N).
%   max_source_index  : LARGEST history index actually read (audit; oracle modes
%                       read the future and are explicitly EXEMPT from the
%                       max_source_index <= latest_available invariant).
%   n_clamped         : count of cells clamped to >= 0 (documented clamp rule).
%
% Publication rule (X1 hand-verified): interval m spans
%   [(m-firstIndex)*1800, (m-firstIndex+1)*1800) s in issue_s coordinates,
%   so it is visible iff (m-firstIndex+1)*1800 + lag_s <= issue_s, i.e.
%   latest = firstIndex + floor((issue_s - lag_s)/1800) - 1.
% Known target cells (targetIndex <= latest_available) use the ACTUAL value and
% are NEVER biased. Unknown cells use the mode forecast + bias.
% Errors (never silent clamps): seasonal source < 1, seasonal source beyond the
% publication frontier (future leak refused), missing history, bad arguments.
if nargin < 8 || isempty(carbon_sigma), carbon_sigma = 0; end
if nargin < 9, noise = []; end
seg = 1800;
history = history(:);
N = numel(history);
if ~isnumeric(history) || N == 0 || any(~isfinite(history))
    error('p3x:BadHistory', 'history must be a non-empty finite numeric vector');
end
if ~(isnumeric(firstIndex) && isscalar(firstIndex) && firstIndex == fix(firstIndex) && firstIndex >= 1)
    error('p3x:BadFirstIndex', 'firstIndex must be a positive integer');
end
if ~(isnumeric(K) && isscalar(K) && K == fix(K) && K >= 1)
    error('p3x:BadK', 'K must be a positive integer');
end
if ~(isnumeric(issue_s) && isscalar(issue_s) && isfinite(issue_s) && issue_s >= 0)
    error('p3x:BadIssueTime', 'issue_s must be finite and >= 0');
end
if ~(isnumeric(lag_s) && isscalar(lag_s) && isfinite(lag_s) && lag_s >= 0)
    error('p3x:InvalidLag', 'lag_s must be finite and >= 0 (END+lag publication rule)');
end
if ~(isnumeric(bias) && isscalar(bias) && isfinite(bias))
    error('p3x:BadBias', 'bias must be a finite scalar');
end
if ~(isnumeric(carbon_sigma) && isscalar(carbon_sigma) && isfinite(carbon_sigma) && carbon_sigma >= 0)
    error('p3x:BadSigma', 'carbon_sigma must be a finite scalar >= 0');
end
if isstring(mode), mode = char(mode); end
if ~ischar(mode), error('p3x:BadMode', 'mode must be a string'); end
mode = lower(strtrim(mode));
targets = (firstIndex : firstIndex + K - 1)';
if targets(end) > N
    error('p3x:HistoryTooShort', 'last target %d exceeds history length %d', targets(end), N);
end
% publication frontier (X1 boundary fix #2: clip no further than history length)
latest_raw = firstIndex + floor((issue_s - lag_s) / seg) - 1;
latest_available = min(latest_raw, N);
if latest_available < 1
    error('p3x:NoPublishedHistory', ...
        'nothing published at issue_s=%.3f lag_s=%.3f (latest_raw=%d): cannot initialize', ...
        issue_s, lag_s, latest_raw);
end
known = targets <= latest_available;
forecast = nan(K, 1);
if any(known)
    forecast(known) = history(targets(known));   % known actuals: unbiased
end
switch mode
    case 'persistence'
        base = history(latest_available);
        forecast(~known) = base + bias;
        max_source_index = max([latest_available; targets(known)]);   % reads history(latest)
    case 'seasonal'
        src = targets - 48;                        % previous-day same slot (48 x 30min)
        if any(src < 1)
            error('p3x:SeasonalRange', ...
                'targetIndex-48 < 1: previous-day value outside history (no clamp allowed)');
        end
        if any(src(~known) > latest_available)
            error('p3x:SeasonalUnavailable', ...
                'previous-day source %d beyond publication frontier %d (future read refused)', ...
                max(src(~known)), latest_available);
        end
        forecast(~known) = history(src(~known)) + bias;
        % seasonal never reads history(latest): the audited max is over the
        % indices actually read (published targets + previous-day sources)
        max_source_index = max([targets(known); src(~known)]);
    case 'oracle'
        % IDEAL_INFORMATION: reads future actuals by construction (deployment-forbidden
        % reference). Explicitly exempt from the source-index audit.
        forecast(:) = history(targets);
        max_source_index = targets(end);
    case 'oracle_noise'
        % IDEAL_INFORMATION_NOISY: future actuals + controlled exogenous noise.
        % Never a causal predictor; the noise axis is kept separate from the
        % causal bias axis (X1 correction #3).
        if isempty(noise)
            if carbon_sigma > 0
                error('p3x:NoiseVectorRequired', ...
                    'oracle_noise with carbon_sigma>0 needs a precomputed noise vector (no RNG here)');
            end
            nz = zeros(K, 1);
        else
            noise = noise(:);
            if numel(noise) < K
                error('p3x:NoiseLength', 'noise vector shorter than K=%d', K);
            end
            nz = noise(1:K);
        end
        forecast(:) = history(targets) + nz;
        max_source_index = targets(end);
    otherwise
        error('p3x:UnknownMode', 'unknown predictor mode: %s', mode);
end
% documented clamp rule (candidate brief): carbon intensity is non-negative
n_clamped = sum(forecast < 0);
forecast = max(forecast, 0);
end
