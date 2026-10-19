# E3 scanned-axis boundary honesty report

Paired deltas are per-seed (common seeds, common potential trajectories) against the single common baseline cell E3_W1800. A zero crossing is claimed ONLY if the mean paired delta changes sign between two adjacent scanned levels; then only the bracket is reported. No interpolated/critical value is produced anywhere; local densification was NOT performed (it would require a frozen rule and a new exploration version).

## axis max_defer_s (reference E3_W1800)

Scanned levels: [0,300,900]. The reference cell has level 0 (delta=0 by construction). 

- quality_mean_per_arrival: no_zero_crossing_observed (scanned levels only; NO critical value produced)
- carbon_per_arrival: no_zero_crossing_observed (scanned levels only; NO critical value produced)
- resp_mean: no_zero_crossing_observed (scanned levels only; NO critical value produced)
- budget_used: zero crossing bracketed in [300,900] across scanned levels; 1 sign change(s); NO interpolated critical value; densification requires a frozen rule + new exploration version
- rate_completed: no_zero_crossing_observed (scanned levels only; NO critical value produced)

## axis rho_route (reference E3_W1800)

Scanned levels: [0.02,0.1,0.5]. The reference cell has level 0 (delta=0 by construction). 

- quality_mean_per_arrival: no_zero_crossing_observed (scanned levels only; NO critical value produced)
- carbon_per_arrival: no_zero_crossing_observed (scanned levels only; NO critical value produced)
- resp_mean: no_zero_crossing_observed (scanned levels only; NO critical value produced)
- budget_used: no_zero_crossing_observed (scanned levels only; NO critical value produced)
- rate_completed: no_zero_crossing_observed (scanned levels only; NO critical value produced)

## axis bias (reference E3_W1800)

Scanned levels: [-40,40]. The reference cell has level 0 (delta=0 by construction). NOTE: scanned levels lie on BOTH sides of the reference 0; a sign-change bracket spanning them contains the reference itself and is NOT a critical-threshold claim.

- quality_mean_per_arrival: zero crossing bracketed in [-40,40] across scanned levels; 1 sign change(s); NO interpolated critical value; densification requires a frozen rule + new exploration version; NOTE bracket spans both sides of reference 0 (delta=0 there by construction), so this is NOT a critical-threshold claim
- carbon_per_arrival: zero crossing bracketed in [-40,40] across scanned levels; 1 sign change(s); NO interpolated critical value; densification requires a frozen rule + new exploration version; NOTE bracket spans both sides of reference 0 (delta=0 there by construction), so this is NOT a critical-threshold claim
- resp_mean: zero crossing bracketed in [-40,40] across scanned levels; 1 sign change(s); NO interpolated critical value; densification requires a frozen rule + new exploration version; NOTE bracket spans both sides of reference 0 (delta=0 there by construction), so this is NOT a critical-threshold claim
- budget_used: zero crossing bracketed in [-40,40] across scanned levels; 1 sign change(s); NO interpolated critical value; densification requires a frozen rule + new exploration version; NOTE bracket spans both sides of reference 0 (delta=0 there by construction), so this is NOT a critical-threshold claim
- rate_completed: zero crossing bracketed in [-40,40] across scanned levels; 1 sign change(s); NO interpolated critical value; densification requires a frozen rule + new exploration version; NOTE bracket spans both sides of reference 0 (delta=0 there by construction), so this is NOT a critical-threshold claim

## axis carbon_sigma (reference E3_W1800)

Scanned levels: [10,40]. The reference cell has level 0 (delta=0 by construction). 

- quality_mean_per_arrival: no_zero_crossing_observed (scanned levels only; NO critical value produced)
- carbon_per_arrival: zero crossing bracketed in [10,40] across scanned levels; 1 sign change(s); NO interpolated critical value; densification requires a frozen rule + new exploration version
- resp_mean: zero crossing bracketed in [10,40] across scanned levels; 1 sign change(s); NO interpolated critical value; densification requires a frozen rule + new exploration version
- budget_used: no_zero_crossing_observed (scanned levels only; NO critical value produced)
- rate_completed: no_zero_crossing_observed (scanned levels only; NO critical value produced)

