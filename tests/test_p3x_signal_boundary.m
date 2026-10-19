function test_p3x_signal_boundary(rootDir, run_id) %#ok<INUSD>
%TEST_P3X_SIGNAL_BOUNDARY Release-rule / boundary / audit semantics of p3x_signal.
% Covers acceptance A2 and the three X1 boundary repairs:
%   (1) seasonal source < 1 -> error (never silent clamp)
%   (2) latest_available clipped no further than history length
%   (3) oracle explicit source-index exemption (IDEAL_INFORMATION)
if nargin < 2, run_id = '20261018_171608_963_p3_supplement'; end %#ok<NASGU>
h = (1:500)';
first = 200; K = 8;

% --- publication frontier: lag=0 and lag=900 hand-computed ---
[p, used] = p3x_signal(h, first, K, 0, 0, 'persistence', 0);
assert(used == 199 && all(p == 199), 'p3x:Boundary', 'lag=0 issue=0 must give latest=firstIndex-1=199');
[p, used] = p3x_signal(h, first, K, 0, 900, 'persistence', 0);
assert(used == 198 && all(p == 198), 'p3x:Boundary', 'lag=900 issue=0 must give latest=198');
[p, used] = p3x_signal(h, first, K, 0, 3600, 'persistence', 0);
assert(used == 197 && all(p == 197), 'p3x:Boundary', 'lag=3600 issue=0 must give latest=197');

% --- negative lag refused ---
ok = false;
try
    p3x_signal(h, first, K, 0, -1, 'persistence', 0);
catch ME
    ok = strcmp(ME.identifier, 'p3x:InvalidLag');
end
assert(ok, 'p3x:InvalidLag', 'negative lag must raise p3x:InvalidLag');

% --- negative issue refused ---
ok = false;
try
    p3x_signal(h, first, K, -5, 3600, 'persistence', 0);
catch ME
    ok = strcmp(ME.identifier, 'p3x:BadIssueTime');
end
assert(ok, 'p3x:BadIssueTime', 'negative issue_s must raise p3x:BadIssueTime');

% --- X1 boundary repair (1): seasonal source < 1 must error, never clamp ---
ok = false;
try
    p3x_signal(h, 10, K, 0, 3600, 'seasonal', 0);
catch ME
    ok = strcmp(ME.identifier, 'p3x:SeasonalRange');
end
assert(ok, 'p3x:SeasonalRange', 'seasonal source before history must error');
[s, used, msi] = p3x_signal(h, 49, K, 0, 3600, 'seasonal', 0);
assert(all(s == (1:8)') && used == 46 && msi == 8 && msi <= used, ...
    'p3x:Seasonal', 'seasonal at firstIndex=49 must read exactly indices 1..8');

% --- X1 boundary repair (2): latest clipped to history length ---
[~, used] = p3x_signal(h, first, K, 1e6, 3600, 'persistence', 0);
assert(used == 500, 'p3x:Clip', 'latest_available must clip at N=500');

% --- X1 boundary repair (3): oracle exemption, explicit and audited ---
[f, latest, msi] = p3x_signal(h, first, K, 0, 3600, 'oracle', 0);
assert(isequal(f, (200:207)') && msi == 207 && latest == 197 && msi > latest, ...
    'p3x:OracleExempt', 'oracle must read the future and be explicitly exempt');

% --- oracle_noise: noise vector required; sigma=0 == oracle ---
ok = false;
try
    p3x_signal(h, first, K, 0, 3600, 'oracle_noise', 0, 10);
catch ME
    ok = strcmp(ME.identifier, 'p3x:NoiseVectorRequired');
end
assert(ok, 'p3x:NoiseVectorRequired', 'oracle_noise with sigma>0 must require exogenous noise');
nz = (1:16)';
[f2, ~, msi2] = p3x_signal(h, first, K, 0, 3600, 'oracle_noise', 0, 10, nz);
assert(isequal(f2, (200:207)' + (1:8)') && msi2 == 207, ...
    'p3x:OracleNoise', 'oracle_noise must add the precomputed noise to future actuals');
% sigma=0: the caller-side noise stream is zero-scaled (p3_gen_trajectory
% generates c_noise = carbon_sigma*randn), so the point coincides with the oracle
[f3, ~, ~] = p3x_signal(h, first, K, 0, 3600, 'oracle_noise', 0, 0, zeros(16, 1));
assert(isequal(f3, (200:207)'), 'p3x:OracleNoise0', 'sigma=0 must reproduce the oracle point');

% --- causal modes never read the future (seasonal refusal instead of leak) ---
ok = false;
try
    p3x_signal(h, 100, 60, 0, 3600, 'seasonal', 0);   % src up to 111 > frontier 97
catch ME
    ok = strcmp(ME.identifier, 'p3x:SeasonalUnavailable');
end
assert(ok, 'p3x:SeasonalUnavailable', 'seasonal source beyond frontier must be refused');

% --- known actuals are never biased ---
[p4, ~, ~] = p3x_signal(h, first, K, 5400, 3600, 'persistence', 40);
assert(p4(1) == 200 && all(p4(2:end) == 240), 'p3x:Bias', 'bias must not alter published actuals');

% --- documented clamp rule (>= 0) with count ---
hh = ones(500, 1);
[p5, ~, ~, ncl] = p3x_signal(hh, first, K, 0, 3600, 'persistence', -40);
assert(all(p5 == 0) && ncl == K, 'p3x:Clamp', 'negative forecast cells clamp to 0 and are counted');

% --- bad inputs refused ---
ok = false;
try
    p3x_signal([1; NaN; 3], first, K, 0, 3600, 'persistence', 0);
catch ME
    ok = strcmp(ME.identifier, 'p3x:BadHistory');
end
assert(ok, 'p3x:BadHistory', 'non-finite history must error');
ok = false;
try
    p3x_signal(h, 500, K, 0, 3600, 'persistence', 0);   % last target 507 > 500
catch ME
    ok = strcmp(ME.identifier, 'p3x:HistoryTooShort');
end
assert(ok, 'p3x:HistoryTooShort', 'targets beyond history must error');

% --- audit invariant across issue times: causal max_source_index <= frontier ---
for t = [0, 1800, 5400, 20000]
    [~, latest, msi] = p3x_signal(h, first, K, t, 3600, 'persistence', 0);
    assert(msi <= latest, 'p3x:Audit', 'persistence source beyond frontier');
    [~, latest, msi] = p3x_signal(h, first, K, t, 3600, 'seasonal', 0);
    assert(msi <= latest, 'p3x:Audit', 'seasonal source beyond frontier');
end
fprintf('P3X_SIGNAL_BOUNDARY_PASS\n');
end
