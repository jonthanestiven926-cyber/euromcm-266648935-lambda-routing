function test_p3x_maxdefer_independent(rootDir, run_id)
%TEST_P3X_MAXDEFER_INDEPENDENT Acceptance A7 (E3 wait axis, deadline constant).
% The wait upper limit max_defer_s is INDEPENDENT of the deadline: d = a + W_batch
% must be bit-identical across all levels; max_defer_s=0 means immediately
% schedulable (no voluntary deferral), NOT zero-second completion.
if nargin < 2, run_id = '20261018_171608_963_p3_supplement'; end
outRoot = fullfile(rootDir, '06_results', run_id);
devDir = fullfile(outRoot, 'dev_acceptance', 'test_p3x_maxdefer_independent');
levels = [0, 300, 900, 1800];
runs = cell(numel(levels), 1);
exs = cell(numel(levels), 1);
for k = 1:numel(levels)
    cfg = struct('block', 'E3', 'seed', 20261018, 'offset', 96, 'first_index', 1441, ...
        'strategy', 'adaptive_gain', 'carbon_sched', true, 'predictor', 'seasonal', ...
        'lambda', 0.1, 'C', 4, 'budget_mode', 'scaled', 'B_per_request', 1.5, ...
        'T_arr', 7200, 'W_batch', 1800, 'd_int', 10, 'lag_s', 3600, ...
        'rho_route', 0, 'bias', 0, 'carbon_sigma', 0, 'demand_M', 1, ...
        'max_defer_s', levels(k), 'note', ...
        'E3 max_defer dev acceptance (dev seed; deadline d=a+1800 unchanged)');
    cfg.case_id = sprintf('DEV_E3_W%d', levels(k));
    [run, ex, rec] = p3x_run_one(cfg, rootDir, fullfile(devDir, cfg.case_id));
    assert(strcmp(rec.status, 'success'), 'p3x:DevRun', 'dev run %s failed', cfg.case_id);
    runs{k} = run;
    exs{k} = ex;
    assert(run.meta.max_defer_s == levels(k), 'p3x:MaxDefer', 'meta.max_defer_s wrong');
    assert(run.invariants.max_defer_s == levels(k), 'p3x:MaxDefer', 'invariant max_defer_s wrong');
end

% ---- deadline identical across all levels and equal to a + W_batch / a + d_int ----
d0 = [runs{1}.req.d]';
for k = 2:numel(levels)
    dk = [runs{k}.req.d]';
    assert(isequal(d0, dk), 'p3x:DeadlineConstant', ...
        'deadline d changed with max_defer_s level %d', levels(k));
end
for i = 1:numel(runs{1}.req)
    r = runs{1}.req(i);
    if strcmp(r.gtype, 'bat')
        want = r.a + 1800;
    else
        want = r.a + 10;
    end
    assert(abs(r.d - want) < 1e-9, 'p3x:DeadlineConstant', ...
        'request %d deadline %.3f != expected %.3f', i, r.d, want);
end

% ---- max_defer_s = 0 => immediately schedulable: NO voluntary deferral ----
r0 = runs{1};
assert(exs{1}.n_defer_events == 0, 'p3x:MaxDeferZero', ...
    'max_defer_s=0 must produce zero DEFER events (got %d)', exs{1}.n_defer_events);
assert(all_window_starts_after_arrival(r0), 'p3x:MaxDeferZero', ...
    'a job window must never start before its arrival');

% ---- finite levels: deferral stays within arrival + max_defer_s ----
for k = 2:numel(levels)
    rk = runs{k};
    assert(all_window_starts_after_arrival(rk), 'p3x:MaxDefer', 'window before arrival');
    md = levels(k);
    for e = 1:numel(rk.events)
        ev = rk.events(e);
        if ~strcmp(ev.type, 'DEFER')
            continue;
        end
        s_star = sscanf(ev.detail, 'carbon-optimal start at %f');
        assert(~isempty(s_star), 'p3x:MaxDefer', 'cannot parse DEFER detail: %s', ev.detail);
        i = ev.req;
        % the event detail stores %.3f seconds, so the parsed value only bounds
        % the true start to +-5e-4; the engine bound itself is exact
        assert(s_star <= rk.req(i).a + md + 1e-2, 'p3x:MaxDefer', ...
            'deferred start %.3f exceeds arrival+max_defer_s (%.3f+%.3f)', ...
            s_star, rk.req(i).a, md);
        assert(s_star >= ev.time - 1e-2, 'p3x:MaxDefer', 'deferred start before decision time');
    end
    fprintf('  max_defer_s=%d: DEFER events=%d, d identical\n', md, exs{k}.n_defer_events);
end
fprintf('P3X_MAXDEFER_INDEPENDENT_PASS\n');
end

function ok = all_window_starts_after_arrival(run)
ok = true;
if isempty(run.windows), return; end
for w = 1:numel(run.windows)
    i = run.windows(w).req;
    if run.windows(w).start < run.req(i).a - 1e-9
        ok = false;
        return;
    end
end
end
