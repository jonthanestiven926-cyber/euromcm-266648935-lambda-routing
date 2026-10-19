# 01_PROTOCOL_AMENDMENT_X1 — E2 可辨识性两项修订（结果前）

run_id: 20261018_171608_963_p3_supplement
修订人: 数学员（DeepSeek 数学复算）
修订时间: 2026-10-19 06:47:48 +08:00
触发: captain X1 补充说明（不改变 t1 的 PASS 结论，仅修订协议冻结内容）
性质: E2 可辨识性修正；由 304 行矩阵哈希匹配不代替，须实测验证。

## X1-1 E2A 预算轴不能以 1.5×N 断言宽松

核实（独立复算）：B=1.5×N（≈1.5/到达）是旧场景预算耗尽点，不是宽松。
证据：旧 M3 种子 2026101818 loc1，N=455，B=682.5=1.5×N，budget_used=682.4（remaining 0.1），n_rejected=194（42.6%）。
每服务请求成本 = 682.4/261 ≈ 2.615 单位；要服务 ~95% 到达需 B ≈ 0.95×900×2.615 ≈ 2232（≈2.5×N），而非 1350。
原协议 B_abs=1350@λ1 标“宽松”为错误。

修正（dev 实测门，结果前）：
1. 以 dev 种子 20261018 在每个 (lambda,C) 用宽松探针 B_probe=10×N 跑，实测全服务成本 C_full 与利用率。
2. 冻结 B_tight=0.5×C_full（紧）、B_high=1.2×C_full（宽松，>全服务成本）。
3. 门：若 B_high 实测仍紧（拒绝率>2% 或 budget_remaining<1%×B_high），结果前上调并重新冻结（不只改文字）。
4. 覆盖原型改为实测判定：lambda1+C1+B_high=预算宽松服务器饱和；lambda0.1+C4+B_tight=容量宽松预算紧；lambda1+C1+B_tight=双紧；lambda0.1+C4+B_high=双松。

## X1-2 E2B 偶数索引抽取是嵌套子集且破坏 Poisson（Erlang-2），改 Bernoulli 薄化

核实（独立复算）：基流 Poisson(2λ) 间隔 T_i~Exp(2λ)。偶数索引抽取 → 间隔 T_{2j-1}+T_{2j}~Erlang(2,2λ)，
均值=1/λ、方差=1/(2λ^2)、CV=1/√2≈0.707（比 Poisson 的 CV=1 更规则），与 Poisson(λ) 不同分布 → 需求增长与规则度效应混淆，破坏可辨识性。
偶数抽取是嵌套子集（d1 首到达=基流 S_2，非 S_1），不是“共同前缀”。

修正（选 Bernoulli 薄化保 Poisson）：
1. 基轨迹 Poisson(2λ)；对每到达预计算独立 Bernoulli(0.5) 固定标记 m_k（写入轨迹，不随策略漂移）。
2. demand_M=2=全量=Poisson(2λ)；demand_M=1={m_k=1}=Poisson(λ)（泊松薄化定理 2λ×0.5=λ，间隔 Exp(λ)）。
3. d1 ⊆ d2（嵌套子集），共享请求同基流索引全同可配对；d2 新增请求不与 d1 配对。
4. N1 随机（均值 λ*T_arr=90），逐种子记录 N1 与预算关系 B_d2_fixed=1.5×N1(seed)；B_d2_fixed 与 d1_scaled 同一绝对预算。

## 验收补强（新增/更新）

- test_p3x_demand_prefix：断言 d1 到达序列是 d2 到达序列子集，且 d1 间隔 CV≈1（Exp）非 0.707（Erlang-2）。
- test_p3x_saturation：E2A 实测利用率覆盖低/中/高、budget_remaining 覆盖紧/松，且 B_high 不紧（拒绝率≤2%）。

## 协调与边界

- 与小米协调 dev 实测校准（dev 种子 20261018），不运行 final、不写论文、不改旧源码/旧结果。
- t1 的 PASS 结论不变；本修订仅更新冻结协议（00_PROTOCOL.md §2、params_freeze.csv、run_matrix.csv、acceptance.md 已同步）。

## X1-3 预算必须同λ跨C统一（固定预算扫容量）— 精确规则

队长实读 budget_calibration/resolve 发现：按 (λ,C) 各自取 C_full 会得到按容量分档的预算（λ1: C1 high=1495.56/tight=623.15, C4 high=3469.8/tight=1445.75），违反固定预算扫容量（扫容量时预算必须同λ跨C不变）。

精确规则（唯一合法，替换 X1-1 中“每(λ,C)取 C_full”的表述）：
1. 对每个 λ，先以 dev 种子 20261018 在每个 C in {1,4} 用 B_probe=10×N 实测 C_full(λ,C) 与利用率。
2. 冻结（同λ跨C统一，不得按C分档）：
   B_tight(λ) = 0.5 × C_full(λ, C=1)   （min 容量参考：紧）
   B_high(λ)  = 1.2 × C_full(λ, C=4)   （max 容量参考：宽松）
3. 同一对 (B_tight, B_high) 用于该 λ 下的 C=1 与 C=4。
4. 示例（队长给的 λ1 dev 值）：B_tight(λ1)=0.5×C_full(λ1,C1)=623.15；B_high(λ1)=1.2×C_full(λ1,C4)=3469.8；二者统一用于 C1 与 C4。
5. 原型校验在数值矩阵层面（非仅探针利用率）：C1+B_high=预算宽松(budget_remaining>0)服务器饱和(util高)；C4+B_tight=容量宽松(util低)预算紧(budget_remaining≈0)；C1+B_tight=双紧；C4+B_high=双松。

验收新增断言：test_p3x_budget_unified —— 解析后的数值矩阵中，对每个 λ 与预算档位，B(λ,C=1)==B(λ,C=4)；且四个原型单元的 budget_remaining/utilization 落入预期区间。
