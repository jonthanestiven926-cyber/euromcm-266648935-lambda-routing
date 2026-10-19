function p3x_compare_old_joint(rootDir, run_id)
%P3X_COMPARE_OLD_JOINT X5: recompute the OLD 20-seed M4_joint vs M3 pairing
% STRICTLY from the SAVED metrics/metadata of the old p3_system runs.
% Nothing is re-executed; old result trees are opened read-only.
% Explicit caveats (written into old_joint_notes.md):
%   1. M4_joint is its OWN adaptive routing+scheduling policy run (label
%      M4_joint_routing_plus_scheduling, scheduler carbon_defer_batch). The
%      pairing is NOT a replay of M3 decisions through joint, NOT a mixed
%      counterfactual, and NOT a schedule swap.
%   2. the old runs' forecast is IDEAL (perfect) -- their absolute levels are
%      NOT comparable to the new causal-forecast supplement runs; this table is
%      old-vs-old only.
%   3. vintage: r2_finalshard_M4M5 holds the deadline-repair (R2) engine for
%      M4/M5 only; no r2 M3 exists, so the r2 variant of the pairing mixes
%      engine vintages and is flagged as such.
if nargin < 2, run_id = '20261018_171608_963_p3_supplement'; end
if nargin < 1, rootDir = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))); end
oldRoot = fullfile(rootDir, '06_results', '20261018_013944_988_p3_system');
outDir = fullfile(rootDir, '06_results', run_id, 'old_joint_comparison');
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

thetas = {'theta_005','theta_010','theta_020'};
metrics = {'quality_mean_per_arrival','carbon_per_arrival','resp_mean','resp_p95', ...
    'rate_completed','rate_rejected','budget_used','strong_share'};
variants = {'M4_joint', fullfile('finalshard_M4M5','M4','base_seed%s','M4_joint','metrics.json'); ...
            'M4_joint_r2', fullfile('r2_finalshard_M4M5','M4','base_seed%s','M4_joint','metrics.json')};

tidy = {};
for v = 1:size(variants, 1)
    for ti = 1:numel(thetas)
        for s = 1:20
            seedTag = sprintf('20261018%02d', s);
            % strrep, NOT sprintf: sprintf would eat backslash escapes (\b in
            % ase_seed) and corrupt the path
            m4f = fullfile(oldRoot, strrep(variants{v, 2}, '%s', seedTag));
            m3f = fullfile(oldRoot, 'finalshard_M3', 'M3', ...
                [thetas{ti} '_seed' seedTag], 'M3', 'metrics.json');
            if exist(m4f, 'file') ~= 2 || exist(m3f, 'file') ~= 2
                for mi = 1:numel(metrics)
                    tidy{end+1, 1} = {variants{v, 1}, thetas{ti}, seedTag, metrics{mi}, ...
                        'NaN', 'NaN', 'NaN', 'missing_saved_metrics'}; %#ok<AGROW>
                end
                continue;
            end
            a = jsondecode(fileread(m4f));
            b = jsondecode(fileread(m3f));
            for mi = 1:numel(metrics)
                va = getm(a.metrics, metrics{mi});
                vb = getm(b.metrics, metrics{mi});
                if isnan(va) || isnan(vb)
                    note = 'NaN_preserved_not_zeroed';
                    d = NaN;
                else
                    note = '';
                    d = va - vb;
                end
                tidy{end+1, 1} = {variants{v, 1}, thetas{ti}, seedTag, metrics{mi}, ...
                    fmtn(va), fmtn(vb), fmtn(d), note}; %#ok<AGROW>
            end
        end
    end
end
cols = cell(1, 8);
for j = 1:8
    col = cell(size(tidy, 1), 1);
    for i = 1:size(tidy, 1)
        col{i} = tidy{i}{j};
    end
    cols{j} = col;
end
p3_write_csv(fullfile(outDir, 'old_joint_paired_tidy.csv'), ...
    {'variant','theta','seed','metric','M4_joint_value','M3_value','delta_M4minusM3','note'}, cols);

% ---- paired CI -----------------------------------------------------------
ci = {};
for v = 1:size(variants, 1)
    for ti = 1:numel(thetas)
        for mi = 1:numel(metrics)
            d = [];
            va = [];
            vb = [];
            for i = 1:size(tidy, 1)
                r = tidy{i};
                if strcmp(r{1}, variants{v, 1}) && strcmp(r{2}, thetas{ti}) && strcmp(r{4}, metrics{mi})
                    x = str2double(r{7});
                    if ~isnan(x)
                        d(end+1) = x; %#ok<AGROW>
                        va(end+1) = str2double(r{5}); %#ok<AGROW>
                        vb(end+1) = str2double(r{6}); %#ok<AGROW>
                    end
                end
            end
            if isempty(d)
                mu = NaN; sdv = NaN; lo = NaN; hi = NaN;
            else
                mu = mean(d);
                if numel(d) > 1
                    sdv = std(d, 0);
                    tc = t_crit(numel(d));
                    lo = mu - tc * sdv / sqrt(numel(d));
                    hi = mu + tc * sdv / sqrt(numel(d));
                else
                    sdv = NaN; lo = NaN; hi = NaN;
                end
            end
            ci{end+1, 1} = {variants{v, 1}, thetas{ti}, metrics{mi}, ...
                sprintf('%d', numel(d)), sprintf('%d', 20 - numel(d)), ...
                fmtn(mean(va)), fmtn(mean(vb)), fmtn(mu), fmtn(sdv), fmtn(lo), fmtn(hi)}; %#ok<AGROW>
        end
    end
end
cols2 = cell(1, 11);
for j = 1:11
    col = cell(size(ci, 1), 1);
    for i = 1:size(ci, 1)
        col{i} = ci{i}{j};
    end
    cols2{j} = col;
end
p3_write_csv(fullfile(outDir, 'old_joint_paired_ci.csv'), ...
    {'variant','theta','metric','n_pairs','n_missing','mean_M4_joint','mean_M3', ...
     'mean_delta','sd_delta','ci95_lo','ci95_hi'}, cols2);

notes = sprintf(['# Old 20-seed M4_joint vs M3 direct pairing -- scope and caveats\n\n' ...
    'Source (READ-ONLY, nothing re-executed): 06_results/20261018_013944_988_p3_system/ ' ...
    'finalshard_M3 (M3/theta_005|010|020 x 20 seeds), finalshard_M4M5 and r2_finalshard_M4M5 ' ...
    '(M4/base_seed* /M4_joint), saved metrics.json + metadata only.\n\n' ...
    '1. M4_joint is its own adaptive joint routing+scheduling run (meta.label = ' ...
    'M4_joint_routing_plus_scheduling, meta.scheduler = carbon_defer_batch, meta.policy = adaptive_gain). ' ...
    'The pairing is a DIRECT paired comparison of two separately executed policies per seed: ' ...
    'NOT a replay of M3 decisions under joint, NOT a mixed replay/adaptive hybrid, NOT a schedule swap.\n' ...
    '2. The old runs used an IDEAL (perfect) forecast. Their absolute metric levels are therefore NOT ' ...
    'comparable to the new causal-forecast supplement runs (E1 multi-window issuance/source audits); ' ...
    'this table is old-vs-old only and is not used as a final-score claim.\n' ...
    '3. M3 is adaptive_gain + edf_immediate; the theta_* conditions are the saved M3 parameter conditions ' ...
    '(005/010/020); all three are reported so no condition is silently selected.\n' ...
    '4. Engine vintage: r2_finalshard_M4M5 holds the deadline-repair (R2/S5r2) engine for M4/M5 only; ' ...
    'no r2 M3 exists, so variant=M4_joint_r2 pairs M4_joint_r2 with the original-vintage M3 and is ' ...
    'flagged as MIXED_VINTAGE. Variant=M4_joint pairs same-vintage (finalshard) runs.\n' ...
    '5. Statistical unit = seed (n=20); deltas are per-seed paired (M4_joint - M3); ' ...
    '95%% CI is a two-sided t interval over the paired deltas. Missing metrics stay NaN, never 0.\n' ...
    '6. All old scenarios are CONSTRUCTED_SCENARIO/DEVELOPMENT on the validation carbon slice ' ...
    '(meta.scenario_label / meta.carbon_source); carbon is a relative carbon index, not measured gCO2.\n']);
fid = fopen(fullfile(outDir, 'old_joint_notes.md'), 'w', 'n', 'UTF-8');
fwrite(fid, notes, 'char');
fclose(fid);
fprintf('P3X_OLD_JOINT_COMPARE_DONE %s\n', outDir);
end

function v = getm(s, name)
if isfield(s, name)
    v = double(s.(name));
else
    v = NaN;
end
end

function s = fmtn(x)
if isnan(x)
    s = 'NaN';
else
    s = sprintf('%.17g', x);
end
end

function tc = t_crit(n)
tab = [12.706,4.303,3.182,2.776,2.571,2.447,2.365,2.306,2.262,2.228, ...
    2.201,2.179,2.160,2.145,2.131,2.120,2.110,2.101,2.093,2.086, ...
    2.080,2.074,2.069,2.064,2.060,2.056,2.052,2.048,2.045,2.042];
if n <= 1
    tc = NaN;
elseif n - 1 <= numel(tab)
    tc = tab(n - 1);
else
    tc = 1.96;
end
end
