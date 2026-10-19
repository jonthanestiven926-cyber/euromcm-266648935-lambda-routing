# Lambda routing study — code and data

Reproducibility package for the paper *When Is Switching Worthwhile? AI Routing under Quality, Capacity, and
Carbon Trade-offs* (control number 266648935). This repository contains **code and data only**: the MATLAB
implementation of the constructive layer, its acceptance tests, every frozen parameter, and the aggregates of
the 304 frozen runs that the paper reports.

## Layout

| Directory | Contents |
|---|---|
| `src/` | MATLAB implementation: signal generation, simulation core, budget resolution, run orchestration, aggregation, configuration hashing. |
| `tests/` | Acceptance tests shipped with that code: budget unification, causal prefix invariance, attribution, demand prefix behaviour, saturation, max-deferral independence, signal boundary. |
| `config/` | Frozen parameters, the 304-row run matrix, window definitions, the protocol and its single amendment, the acceptance specification, the diff list. |
| `results/system_aggregates/` | Aggregates of the 304 frozen runs: per-run tidy table, the 798-row aggregate table with mean / sd / se / 95% t-interval, the E1 window table, the E2 paired-contrast table, the E3 boundary table, the boundary report and the schema description. |
| `results/historical/` | Derived plot table for the historical comparison (three budgets × five series). |
| `MANIFEST.json` | SHA-256 and byte size for every file here. |

## What these numbers are

- The constructive layer **was executed**: 38 scenarios × 8 common seeds = 304 runs, sources hashed per run.
- The historical layer used **cached correctness labels** and frozen action tables; no model was re-queried for
  the paper, and no label was regenerated.
- The paper reports aggregates; nothing in the paper re-runs the simulator.

## Honest limits

The constructive layer is a **constructed mechanism**, not a measurement of a deployed service: quality, service
time, capacity and carbon are modelled quantities with assumed parameters. The carbon column is a **relative
execution-window index**, not grams of CO₂, and no emissions claim is made. The historical comparison is
**resolution-limited**: with 195 items the design cannot separate a 0.5-point difference, and the paper states
that rather than claiming equivalence. The forecast-bias axis of the E3 scans is **exactly degenerate** — its
paired differences are zero by construction, so it is a limitation, never a tolerance.

## Not included

Cached model responses, the 195 per-question correctness labels, the three per-budget result files that embed
local paths, and gateway configuration. Their redistribution status is not established; the derived tables here
are what the paper's numbers come from.
# euromcm-266648935-lambda-routing
