# P3 补充实验修订协议（E1/E2/E3 最小矩阵）— 冻结版

run_id: 20261018_171608_963_p3_supplement
审查角色: 数学员（DeepSeek 数学复算/协议规格）
来源依据: 37_给Dsh_恢复后补完实验_暂不写论文.txt；36_Codex实验缺口与图表补充清单_20261018.md
冻结时间: 2026-10-18 17:25:02 +08:00（结果生成前冻结）
状态: 需求/协议（requirements）。候选 brief 与 test_p3x_contract.m 只读审查；本协议为其修订替代，不得照搬 W_batch 期限扫描。
范围: 仅实验与可复现图表数据；绝不修改 09_paper；不读封存碳测试；不跑终评；不新增付费模型。

## 0. 候选 test_p3x_contract.m 数学审查结论

审查方式：对候选 p3x_signal 公式 latest = firstIndex + floor((issue_s-lag_s)/1800) - 1 逐断言手算。

| 断言 | 期望 | 手算 | 判定 |
|---|---|---|---|
| issue=0, lag=3600, first=200 | used==197, p=197 | latest=200+floor(-2)-1=197 | PASS |
| issue=1800 | used==198 | latest=200+floor(-1)-1=198 | PASS |
| seasonal, latest=197 | s=152:159 | 200..207-48=152..159 | PASS |
| oracle | =200:207 | history(200:207) | PASS |
| bias, issue=5400 | p(1)=200, 其余=240 | latest=200+floor(1)-1=200; t=200已知无偏; t>200持久200+40 | PASS |
| future-leak (改198:end) | persistence/seasonal不变 | 二者只读<=197 | PASS |

结论：核心索引数学正确且内部自洽。issue_s 为相对 interval[firstIndex] 起点的时间（秒），等价于仿真时间 0 对 firstIndex 起点；公式实现 interval END + lag 之后才可用的保守发布规则（旧 p3_simulate.carbon_signal 用 segStart<=tt2-lag 即 START+lag，少保守1段，本协议一律改 END+lag）。

### 必须修补的三处边界（作为验收测试补充，不改旧文件）
1. seasonal 越界：targetIndex-48 可 <1（如 firstIndex<49）。候选实现静默 clamp 到 1，与 brief require>=1 冲突，且已非昨日同时。本实验 firstIndex>=1345 不触发；契约必须显式：<1 时 error（拒绝）而非 clamp，并加边界测试。
2. latest 上限：brief 要求 clip no further than history length，候选未实现。测试范围无害（latest<lastTarget<=N），但须补 clip 到 N 的防御与测试。
3. 返回语义：max_source_index 对 persistence=latest、seasonal=实际最大源索引(159)、oracle=lastTarget(207>197)。审计不变量 max_source_index <= latest 只对 persistence/seasonal 成立，oracle 显式豁免（未来读取，标记 IDEAL_INFORMATION）。建议返回两个量 latest_available（发布前沿）与 max_source_index（实际读取上限），断言 persistence/seasonal 时 max_source_index<=latest_available、oracle 时 ==lastTarget。

## 1. E1 因果可用预测与多窗口（最高优先级）

目标：同一请求轨迹比较 立即处理 / 持续预测 / 昨日同时预测 / 完美预知，四个预固定非重叠碳窗口。

固定参数（每窗口同）：T_arr=7200, lambda=0.1, W_batch=1800（batch deadline d=a+1800）, d_int=10, C=4, B_per_request=1.5（预算随N），p_interactive=0.5, q_target=0.7, carbon_delta_h=1（lag=3600s），carbon_source 用 g_train+g_val 拼接 history（1344+672=2016）。

窗口（预固定，见 windows.csv）：firstIndex = 1345 + offset；offset in {0,96,192,288}。目标段 [firstIndex, firstIndex+K-1]，K=ceil((max(traj.a)+W_batch+2*1800)/1800)+2。issue_s=0 时 latest_available = firstIndex-3（=1342/1438/1534/1630），全部目标段在未来 -> 纯因果预测。四窗口互不重叠，全落在 validation 区（1345..2016）；训练=窗口前已发布历史（扩展窗），不读封存测试。四窗口非 i.i.d.（历史重叠递增），跨窗口聚合仅描述性，统计单位=窗口内8种子。

变体（4）：
- imm：adaptive_gain, carbon_sched=false（edf_immediate，预测不参与调度，立即处理基线）。
- persist：adaptive_gain, carbon_sched=true, predictor=persistence。
- seasonal：adaptive_gain, carbon_sched=true, predictor=seasonal（昨日同时因果基线，非 Ridge 声明）。
- oracle：adaptive_gain, carbon_sched=true, predictor=oracle（IDEAL_INFORMATION，禁部署参照）。

发布规则：interval n 值在 END+lag 后才可用；预测起报 issue_s、可见截止 latest_available、目标时距 全部落盘审计。未来扰动验收：仅要求不可见前缀不变（同一已发布历史前缀、改未来实际值，决策/预测不变），不要求未来已可见后仍不变。

运行数：4 窗口 × 8 种子 × 4 变体 = 128。

## 2. E2 预算与容量瓶颈分离

拒绝分解（旧 M3 种子 2026101818 loc1 实证）：194 REJECTED_BUDGET（plan unaffordable）+ 1 REVISION_FAILED_BUDGET，0 容量拒绝、0 deadline 拒绝、0 late、0 drain。当前引擎唯一请求级拒绝原因是预算；容量只会排队->迟到（completed_late），从不拒绝。因此服务器饱和必须由 排队等待(stage1_wait) + 迟到率 + 利用率 证明，不得把容量等待写成拒绝。

互斥终态归因（主因唯一，关联因素另列不重复计数）：completed（c_final<=d）；completed_late（c_final>d）；rejected_budget；drain_violation/undrained_violation。主因规则：有 rejected_budget 记预算；未拒绝但 c_final>d 记 deadline（关联因素：容量排队 stage1_wait>0、预算降级 degraded）；drain 未完成记 horizon。容量压力证据：stage1_wait_mean/p95、max_concurrency、utilization_over_0_to_T_arr、late 率。

### E2A 预算×容量饱和网格（adaptive_gain, carbon_sched=false, offset=96, T_arr=900, W_batch=300）
轴：lambda in {0.1, 1.0}；C in {1, 4}；B_abs in {B_tight, B_high}（绝对资源单位，固定预算，不随N）。
预算校准（结果前，dev 实测门，见 01_PROTOCOL_AMENDMENT_X1.md）：B=1.5×N（≈1.5/到达）是旧场景预算耗尽/拒绝约半的水平（旧 M3 2026101818 实证 used/available=682.4/682.5，reject 42.6%），不是宽松。先以 dev 种子 20261018 在每个 (lambda,C) 用宽松探针预算 B_probe=10×N 跑，实测全服务成本 C_full 与利用率；取 B_tight=0.5×C_full（紧）、B_high=1.2×C_full（宽松，>全服务成本）。若 B_high 实测仍紧（拒绝率>2% 或 budget_remaining<1%×B_high），结果前上调并重新冻结，不只改文字。
- 覆盖原型（实测判定，非名义断言）：lambda1+C1+B_high=预算宽松服务器饱和；lambda0.1+C4+B_tight=容量宽松预算紧；lambda1+C1+B_tight=双紧；lambda0.1+C4+B_high=双松。
- 饱和度以实测 utilization/queue/budget_remaining 证明，不以名义 lambda/C 断言。
运行数：2×2×2×8 = 64（B 轴数值在 dev 校准后冻结）。

### E2B 需求倍增：固定总预算 vs 随N预算（adaptive_gain, carbon_sched=false, offset=96, T_arr=900, W_batch=300, C=4, lambda=0.1）
共同到达（嵌套子集，非前缀）：对每种子先按 lambda_base=2*lambda 生成 Poisson(2λ) 基轨迹；对每个到达预计算独立 Bernoulli(0.5) 固定标记 m_k（写入轨迹，不随策略漂移）。demand_M=2=全量=Poisson(2λ)；demand_M=1={m_k=1 的到达}=Poisson(λ)（泊松薄化定理 2λ×0.5=λ，间隔仍 Exp(λ)，CV=1，非 Erlang-2）。共享请求（同一基流索引）到达时间/特征/质量全同 -> 可配对；demand_M=2 新增请求不与 d1 请求配对。
- 禁止偶数索引抽取：偶数抽取产生 Erlang-2 间隔（CV=1/√2≈0.707，比 Poisson 更规则），与 Poisson(λ) 混淆，破坏需求增长可辨识性。
- d1_scaled：demand_M=1, B=1.5*N1（N1 随机，均值=λ*T_arr=90，逐种子记录）。
- d2_scaled：demand_M=2, B=1.5*N2。
- d2_fixed：demand_M=2, B=1.5*N1(seed)（与 d1_scaled 同一绝对预算；预算关系 B_d2_fixed=1.5×N1(seed) 逐种子记录，N1 随机性显式入账）。
去重：(d1,fixed)=(d1,scaled) 只跑一次。运行数：3 唯一 × 8 = 24（原 brief 的 32 含重复，去重不增加 n）。
目的：总碳/质量增长分解为需求增长与预算扩张，防止把扩预算造成的总碳增长全归因反弹/拥塞。

## 3. E3 策略切换边界（独立 max_defer_s，d 不变）

修正：候选 brief 用 W_batch=[0,300,900,1800] 作等待轴，会同时改 batch deadline d=a+W_batch，属被 37 号明令禁止的期限扫描伪装等待机制。本协议改为独立 max_defer_s（碳调度可推迟上限），W_batch=1800 与 d=a+1800 全程固定；max_defer_s=0=立即调度（非零秒完成）。

固定参数：offset=96, T_arr=7200, lambda=0.1, C=4, W_batch=1800, d_int=10, q_target=0.7, B_per_request=1.5, carbon_sched=true, predictor=seasonal（噪声轴除外）。有效推迟 = min(max_defer_s, 截止期松弛 ls_e2e)。

独立轴（每轴单独扫，其余取基线值；基线= max_defer_s=1800, rho_route=0, bias=0, seasonal）：
- 轴W 等待上限：max_defer_s in {0,300,900,1800}（4 水平）。
- 轴R 路由资源开销：rho_route in {0,0.02,0.1,0.5}（tau_route=0，纯资源），基线 rho=0 复用。
- 轴E-bias 因果预测已知偏差：bias in {-40,0,+40} gCO2/kWh（加在 seasonal 预测上，确定性），基线 bias=0 复用。
- 轴E-noise 受控 ideal 噪声：predictor=oracle_noise, carbon_sigma in {0,10,40}（σ=0 即 oracle，复用 E1 oracle w96）。
误差噪声与因果偏差分离：oracle_noise 标 IDEAL_INFORMATION_NOISY，绝不称因果；seasonal+bias 才是因果。
每轴输出相对基线（imm, E1 w96 同种子）的配对增益/质量/拒绝/延迟曲线；区间内无跨零则如实报告测试范围内未见交点，不制造临界点。
运行数：(4+3+2+2)=11 唯一条件 × 8 = 88（含基线1次、oracle σ=0 复用，不重复计 n）。

## 4. 统计口径与缺失值（冻结）

- 统计单位：种子=独立样本（每窗口/每单元 8 个）；E1 四窗口不 i.i.d.，跨窗口仅描述；E2/E3 单元=种子。重复基线（E3 基线、E2B d1、oracle σ=0）复用，不增加 n。
- deadline 状态（互斥完备）：completed / completed_late / rejected_budget / drain_violation / undrained_violation。
- quality_target_met_per_arrival = (status==completed 且 q_real>=q_target) 的到达数 / N。分母恒为 N（到达数），拒绝/迟到/未排空计为未达标，永不 NaN。
- quality_per_completed = quality_total / n_completed_total（completed+completed_late）；n_completed_total=0 时=NaN（不是0）。
- response_p95_conditional = 完成者响应时间 p95（条件于未拒绝且已排空）；空集=NaN。拒绝不当作零延迟。
- stage1_wait = jb_startT - arrival（stage-1 排队），stage1_wait_mean/p95 空集=NaN。
- 利用率：utilization_over_0_to_T_arr = 积分[0,T_arr] 并发数 dt / (C*T_arr)；execution_windows 裁切到 [0,T_arr]（start=max(start,0), stop=min(stop,T_arr)），容量取常数 C（dev_main 无 C_schedule）；max_concurrency 另分全排空期峰值与[0,T_arr]内峰值两列。
- 缺失反馈 fb_missing：无 revision 可能，stage-1 答案保留，非错误。

## 5. 旧策略与图表修正口径（本协议只定口径，不跑图、不写论文）

- M4_joint = adaptive_gain + carbon_sched=true + offline_diagnostic=false（自身决策，非回放）；M4_iso / M5b = replay（冻结路由）。oracle 预测标 IDEAL_INFORMATION。论文中把 M4_iso/M4_joint/M5b 统称离线回放为措辞错误，须按运行 meta 更正（本轮不改论文，仅登记口径）。
- 图2：绘图用 mean 却写 total,20 seeds -> 改为每运行总量在20种子上的均值，SD 不是均值置信区间。
- 图5：质量/碳/秒 三个面板分单位，删除 CI跨0=adds nothing 等价结论，跨零不等于等价。
- 图6：备注数值改回由原始 metrics 重建的完整精度数值列，不靠解析四舍五入文字。
- 数据层：逐种子/逐任务原记录 -> 整洁数值 CSV -> 聚合与区间表 -> 绘图.m/PNG/FIG(+可选SVG/PDF)；字段单位、样本量、误差条定义、缺失规则、来源路径随图保存。

## 6. 实现路径与验收命令规格（供实现员，本轮不执行）

新代码目录 04_scripts/p3_supplement/<run>/；旧源码与旧结果只读。p3x_simulate.m 为 p3_simulate 隔离副本（仅函数名+signal_fn 注入），p3x_signal 为纯函数，其余复用 p3_default_params/p3_gen_trajectory/p3_load_carbon/p3_write_run_artifacts。

先测后跑：信息边界、任务守恒、预算、服务器占用、期限标记、小实例 -> 断言失败非零退出；再跑矩阵。负结果与程序错误分开保留。

验收命令（matlab -batch，cd 到本目录）：
1. test_p3x_contract（保留原断言，补充第0节三处边界断言后须 PASS）。
2. test_p3x_signal_boundary：issue=0/lag=0/lag=900/lag<0；seasonal firstIndex<49 应 error；latest 裁剪到 N；oracle 豁免审计。
3. test_p3x_causal_prefix_invariance：同已发布历史前缀+改未来实际值 -> 决策/预测不变（仿真级）。
4. test_p3x_maxdefer_independent：max_defer_s=0 与 1800 时 d 完全相同（a+1800），仅调度推迟不同。
5. test_p3x_saturation：E2A 各原型单元实测 utilization 覆盖低/中/高、budget_remaining 覆盖紧/松。
6. test_p3x_attribution：终态互斥完备、主因唯一、拒绝/迟到/排空不重复计数。
7. test_p3x_demand_prefix：E2B 共同到达前缀成立（d1 到达序列 是 d2 到达序列子集，共享请求全同）。

冻结文件（本目录）：00_PROTOCOL.md（本文）、params_freeze.csv、windows.csv、run_matrix.csv、acceptance.md。
