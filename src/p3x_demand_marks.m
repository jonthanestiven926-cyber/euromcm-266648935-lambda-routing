function marks = p3x_demand_marks(n, seed)
%P3X_DEMAND_MARKS Deterministic independent Bernoulli(0.5) demand marks.
% Per 01_PROTOCOL_AMENDMENT_X1 (X1-2): even-index extraction of a Poisson(2*lambda)
% stream yields Erlang-2 interarrivals (CV=1/sqrt(2)=0.707) and is NOT Poisson.
% Instead each base-stream arrival gets an independent Bernoulli(0.5) mark drawn
% from a DEDICATED substream (never the policy RNG), so the marks are fixed per
% seed and cannot drift with strategy decisions. Thinning a Poisson(2*lambda)
% stream at p=0.5 leaves Poisson(lambda) (thinning theorem: Exp interarrivals, CV=1).
n = double(n);
if n < 0 || n ~= floor(n)
    error('p3x:BadMarks', 'n must be a nonnegative integer');
end
if n == 0
    marks = false(0, 1);
    return;
end
% fixed dedicated substream seed offset (documented, reproducible)
s = RandStream('mt19937ar', 'Seed', mod(double(seed) + 777000003, 2^32));
marks = rand(s, n, 1) < 0.5;
end
