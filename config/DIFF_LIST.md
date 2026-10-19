# p3x_simulate.m 与旧引擎 p3_simulate.m 的逐条差异清单

- 来源（只读）：`04_scripts/p3_system/p3_simulate.m`
- 来源 SHA256：`f9b8acb7253fb492147a6e5c955a0dfbaF75234371702d965420669e7ef40013`（复制前记录，旧文件未修改）
- 新文件：`04_scripts/p3_supplement/20261018_171608_963_p3_supplement/p3x_simulate.m`
- 复制方式：字节复制后仅做下列 D1–D7 修改；其余代码逐字符相同（`git diff --no-index` 全量差异仅含下述块）。

## 必须保留且确认保留的旧修复（数值 deadline R2 / S5r2 修复，未删改）

1. 反馈处修订可行性修复（`on_feedback`）：`est2 = max(tt2, min(mf)); est2 + dur2 > traj.d(i)` 时
   **丢弃升级 `UPGRADE_DROPPED_DEADLINE`，stage-1 答案保留**（不转为迟到、不计 stage-2 成本）。
2. 推迟时端到端松弛预留（`schedule_pass`）：`ls_e2e = jb_deadline - (jb_dur + P.delta_fb + maxDur2)`，
   推迟上界仍预留 `delta_fb + worst-case stage-2 时长`。
3. 反馈事件只由 stage-1 **实际完成时刻 + delta_fb** 触发（排队请求不会提前拿反馈）。
4. 预算账（`charge`）零额也记账、拒绝/失败尝试仍计 `rho_route` 开销、容量准入规则、排空规则等全部不变。

## D1 函数名

`p3_simulate` -> `p3x_simulate`（含头注释说明副本来源与本清单）。

## D2 opts.signal_fn 注入（信息边界）

`carbon_signal` 首部新增分支：若 `opts.signal_fn` 非空，直接返回其输出并做
长度=K、有限性断言；旧的 `gForecast=gActual+cn` 分支原样保留为 micro/兼容路径，
但所有补充实验都注入 signal_fn（`p3x_make_signal` -> `p3x_signal`）。
策略侧只见**发行时点可见的预测**；真实 `gActual` 只留在环境做评分（`opts.gActual` 设窗口真值切片）。

## D3 obs.carbon 携带发布/来源审计字段

`build_obs` 中 `carbon_signal` 改为三输出调用，`obs.carbon` 新增
`issue_s / latest_available / max_source_index`（不改其余 obs 字段）。

## D4 决策日志增加审计字段

两处 `decLog(end+1,1)=struct(...)`（arrival/feedback）新增
`issue_s / latest_available / max_source_index`，随 `decisions_audit.csv` 落盘。

## D5 独立等待上限 max_defer_s（不改截止期）

`schedule_pass` 推迟分支新增 `ls_upper = min(ls_e2e, traj.a(req) + opts.max_defer_s)`
（`max_defer_s=Inf` 时 `ls_upper=ls_e2e`，与旧行为一致）。
- `d = a + W_batch` 全程不动；
- `max_defer_s = 0` -> `ls_upper <= 到达时刻 <= tt2` -> 永不推迟（立即可调度，非零秒完成）；
- 推迟起点只在 `[tt2, ls_upper]` 的候选集里选碳最优（候选集与判定式其余部分不变）。

## D6 run.meta 合并 opts.meta_extra

补充元数据（predictor、information_class、config_hash、窗口索引、K、budget 等）写入
`run.meta`，不覆盖旧字段。`run.meta.information_class` 取值：
`CAUSAL_PERSISTENCE / CAUSAL_PREVIOUS_DAY / IDEAL_INFORMATION / IDEAL_INFORMATION_NOISY / UNUSED_IMMEDIATE`。

## D7 invariants 记录

`run.invariants` 新增 `max_defer_s`、`signal_source`（injected_causal_signal_fn / legacy_gActual_plus_noise）。

## 未修改、显式 addpath 复用的旧 helper（04_scripts/p3_system，只读）

`p3_default_params / p3_gen_trajectory / p3_load_carbon / p3_write_run_artifacts /
p3_validate_run / p3_carbon_index / p3_sha256 / p3_sha256_str / p3_source_hashes /
p3_write_csv / p3_write_json / p3_now_iso / p3_policy`。同名 shadow 检查见
`08_logs/20261018_171608_963_p3_supplement/xiaomi/path_audit.txt`（`which -all` 全量记录）。

## 新增文件（本目录）

`p3x_signal.m`（纯函数因果预测）、`p3x_make_signal.m`（决策时点信号闭包+发行审计）、
`p3x_simulate.m`、`p3x_extras.m`（利用率/排队/互斥主因归因）、`p3x_write_supplement_artifacts.m`、
`p3x_micro_traj.m`、`p3x_thin_traj.m`（按 Bernoulli 标记取子集，X1-2）、`p3x_demand_marks.m`
（独立子流 Bernoulli(0.5) 固定标记）、`p3x_resolve_budget.m`（X1-1 校准预算级解析）、
`p3x_config_hash.m`、`p3x_cfg_normalize.m`、
`p3x_cfg_from_row.m`、`p3x_run_one.m`、`p3x_runner.m`、`p3x_freeze.m`、
`test_p3x_signal_boundary.m`、`test_p3x_causal_prefix_invariance.m`、
`test_p3x_maxdefer_independent.m`、`test_p3x_saturation.m`、`test_p3x_attribution.m`、
`test_p3x_demand_prefix.m`、`test_p3x_supplement.m`、`DIFF_LIST.md`。

候选 `05_work/p3_supplement/experiment_brief.md` 与 `04_scripts/p3_supplement/test_p3x_contract.m`
均未修改、未照搬：brief 的 W_batch 期限扫描、B_per_request 预算轴、E2B 重复计数等缺陷按
X1/X2 审定协议改正（见 00_PROTOCOL.md）。

## 01_PROTOCOL_AMENDMENT_X1 的落地（结果前，非文字修改）

- **X1-1 E2A 预算轴**：不再使用 1.5×N（旧 M3 耗尽点）。dev 种子 20261018 以
  `B_probe = 10×N` 宽松探针实测全服务成本 `C_full`，冻结 `B_tight = 0.5×C_full`、
  `B_high = 1.2×C_full`，并执行实测门（拒绝率≤2% 且剩余≥1%×B_high，否则系数上调
  并重新冻结）。校准值写入
  `06_results/20261018_171608_963_p3_supplement/dev_acceptance/budget_calibration/`
  （budget_calibration.json/csv），由 `p3x_resolve_budget.m` 在 final 前按 (lambda,C) 解析
  矩阵 token `TBD_tight/TBD_high`，并在 `freeze_manifest.json.budget_calibration`
  绑定 SHA256。四原型为实测判定（容量轴用探针利用率，预算轴用 tight/high 运行）。
- **X1-2 E2B 薄化**：偶数索引抽取（Erlang-2, CV=0.707）已禁用。基流 Poisson(2λ)，
  每到达取独立 Bernoulli(0.5) 固定标记 `p3x_demand_marks`（专用 RandStream 子流，
  不与策略 RNG 共用、不随策略漂移）；demand_M=1 = 标记子集 = Poisson(λ)（薄化定理，
  CV=1）；d1 是 d2 的**嵌套子集**（同一基流索引 → 到达/特征/潜在结果全同可配对），
  d2 新增请求不配对。命名如实：这是嵌套子集配对（nested subset），不是“共同到达前缀”。
  引用的 CV=0.994（对照偶数抽取 0.738）只是 dev 种子 20261018 单样本一致性证据，不是分布
  证明；分布性质来自薄化定理（Poisson 薄化 → Exp 间隔），样本检查仅证明实现与定理一致、
  且与 Erlang-2 抽取不一致。
  `B_d2_fixed = 1.5×N1(seed)` 按逐种子实现的 N1 记录。
- **max_defer_s 语义**：只约束人为推迟（DEFER 目标起点 ≤ a+max_defer_s），不是容量
  排队上限；排队导致的实际窗口开始可以晚于该界限（测试按事件目标值判定，事件细节
  为 %.3f 秒精度，容差 1e-2）。截止期 d=a+W_batch 全程不变。
- E2A 宽松探针实测（dev 种子 20261018）：(0.1,1) C_full=293.2、(0.1,4) C_full=293.2、
  (1,1) C_full=1246.3、(1,4) C_full=2891.5。见 `test_p3x_saturation` 报告
  saturation_report.csv。**（此段按 (λ,C) 各自取 C_full 的预算级已被 X1-3 取代，见下节）**

## X3R（01_PROTOCOL_AMENDMENT_X1 X1-3）：同 λ 跨 C 统一绝对预算

**缺陷**：X1-1 原实现按 (λ,C) 各自取 C_full 分档定预算（λ1: C1 tight/high=623.15/1495.56，
C4=1445.75/3469.8），使 64 行最终网格在扫容量的同时预算也变——容量与预算混淆。
**新规则（数学员 X1-3 预先固定，非 final 调参）**：
`B_tight(λ)=0.5×C_full(λ,C=1)`（min 容量锚）、`B_high(λ)=1.2×C_full(λ,C=4)`（max 容量锚），
同一 (λ,档位) 的数值 B 对 C=1 与 C=4 完全相同；门控两 C 共同判宽松（拒绝率≤2% 且剩余≥1%×B_high），
不达则系数上调并重新冻结并记录，绝不改指标掩盖；若开发格出现相反成本顺序（C_full(C4)<C_full(C1)）
直接报错上报重审，不改锚规则。
实现：`p3x_resolve_budget` 改为按 λ 统一解析（唯一解析路径，runner/矩阵/冻结共用）；
`test_p3x_saturation` 按 X1-3 重校准并写 budget_calibration.{json,csv}（rule_version='X1-3'）；
新增 `test_p3x_budget_unified`：经实际 runner 解析路径（p3x_cfg_from_row→p3x_resolve_budget）
对 64 行 E2A 矩阵逐 (seed,λ,档位) 断言 B(C=1) 与 B(C=4) 双精度逐位相同（32 组），
并以 saturation 实测数断言四原型区间；`p3x_freeze` 的 final_coverage_list.csv 增 resolved_budget
列（解析后实际数字），freeze_manifest 增 data_hashes（train/validation split）与 protocol_hashes。
旧版（按 (λ,C) 分档）的代码/校准/测试/冻结产物已快照保存于
`06_results/20261018_171608_963_p3_supplement/snapshot_x3r_pre_repair_20261019_0715/`，
协议六文件（00_PROTOCOL/01_PROTOCOL_AMENDMENT_X1/acceptance/params_freeze/windows/run_matrix）
由数学员冻结 SHA256，实现只读并在验收中逐哈希断言。
