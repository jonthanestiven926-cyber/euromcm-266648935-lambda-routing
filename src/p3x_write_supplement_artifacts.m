function p3x_write_supplement_artifacts(dirPath, run, ex, attr, issLog, cfg, cfgHash)
%P3X_WRITE_SUPPLEMENT_ARTIFACTS Per-run supplement export (E1/E2/E3 audit).
% Adds to p3_write_run_artifacts:
%   forecast_issuance.csv  - every decision-time forecast issuance (issue_s,
%                            latest_available, max_source_index, n_clamped)
%   decisions_audit.csv    - decision rows incl. the release/source audit fields
%   attribution.csv        - per-request terminal state + single primary cause
%                            + associated factors (never double counted)
%   supplement_metrics.csv - full-precision (%.17g) numeric table; NaN preserved
%   config.json            - frozen run config + config_hash (reuse/dedup key)
if exist(dirPath, 'dir') ~= 7
    mkdir(dirPath);
end

% ---- forecast issuance audit ----
m = numel(issLog.issue_s);
ic = (1:m)';
p3_write_csv(fullfile(dirPath, 'forecast_issuance.csv'), ...
    {'call_index','issue_s','latest_available','max_source_index','n_clamped','predictor_mode'}, ...
    {ic, issLog.issue_s, issLog.latest_available, issLog.max_source_index, ...
     issLog.n_clamped, repmat({issLog.mode}, m, 1)});

% ---- decisions incl. release/source audit ----
dl = run.decisions;
n = numel(dl);
dt = zeros(n, 1); dr = zeros(n, 1); dv = false(n, 1);
diss = nan(n, 1); dla = nan(n, 1); dmsi = nan(n, 1);
dp = cell(n, 1); da0 = cell(n, 1); da2 = cell(n, 1); dre = cell(n, 1);
for i = 1:n
    dt(i) = dl(i).time; dr(i) = dl(i).req; dv(i) = logical(dl(i).revise);
    dp{i} = dl(i).phase; da0{i} = dl(i).action0; da2{i} = dl(i).action2;
    dre{i} = dl(i).reason;
    if isfield(dl, 'issue_s'), diss(i) = dl(i).issue_s; end
    if isfield(dl, 'latest_available'), dla(i) = dl(i).latest_available; end
    if isfield(dl, 'max_source_index'), dmsi(i) = dl(i).max_source_index; end
end
p3_write_csv(fullfile(dirPath, 'decisions_audit.csv'), ...
    {'time_s','request_id','phase','action0','revise','action2','reason', ...
     'issue_s','latest_available','max_source_index'}, ...
    {dt, dr, dp, da0, dv, da2, dre, diss, dla, dmsi});

% ---- attribution ----
n = numel(attr);
rid = zeros(n, 1); swq = nan(n, 1); aq = false(n, 1); ad = false(n, 1);
arf = false(n, 1); aud = false(n, 1); afb = false(n, 1); ont = false(n, 1);
cf = nan(n, 1); dd = nan(n, 1); qr = nan(n, 1);
tstat = cell(n, 1); cause = cell(n, 1); det = cell(n, 1);
for i = 1:n
    rid(i) = attr(i).request_id; tstat{i} = attr(i).terminal_status;
    cause{i} = attr(i).primary_cause; det{i} = attr(i).primary_reason_detail;
    swq(i) = attr(i).stage1_wait_s; aq(i) = logical(attr(i).assoc_capacity_queue);
    ad(i) = logical(attr(i).assoc_degraded); arf(i) = logical(attr(i).assoc_revision_failed_budget);
    aud(i) = logical(attr(i).assoc_upgrade_dropped); afb(i) = logical(attr(i).assoc_fb_missing);
    ont(i) = logical(attr(i).on_time); cf(i) = attr(i).c_final_s;
    dd(i) = attr(i).deadline_s; qr(i) = attr(i).q_realized;
end
p3_write_csv(fullfile(dirPath, 'attribution.csv'), ...
    {'request_id','terminal_status','primary_cause','primary_reason_detail', ...
     'stage1_wait_s','assoc_capacity_queue','assoc_degraded', ...
     'assoc_revision_failed_budget','assoc_upgrade_dropped','assoc_fb_missing', ...
     'on_time','c_final_s','deadline_s','q_realized'}, ...
    {rid, tstat, cause, det, swq, aq, ad, arf, aud, afb, ont, cf, dd, qr});

% ---- full-precision numeric metrics table (NaN kept as NaN) ----
fn = fieldnames(ex);
fid = fopen(fullfile(dirPath, 'supplement_metrics.csv'), 'w', 'n', 'UTF-8');
if fid < 0, error('p3x:IO', 'cannot write supplement_metrics.csv'); end
fprintf(fid, 'name,value,unit_note\n');
for k = 1:numel(fn)
    v = ex.(fn{k});
    if isnumeric(v) && isscalar(v)
        fprintf(fid, '%s,%.17g,supplement metric (NaN preserved)\n', fn{k}, v);
    elseif ischar(v)
        fprintf(fid, '%s,,"%s"\n', fn{k}, strrep(v, '"', '""'));
    end
end
fclose(fid);

% ---- config + hashes ----
p3_write_json(fullfile(dirPath, 'config.json'), struct('config_hash', cfgHash, ...
    'config', cfg, 'meta', run.meta, 'generated_at', p3_now_iso()));
end
