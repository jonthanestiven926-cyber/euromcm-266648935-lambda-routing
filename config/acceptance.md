# 验收标准（acceptance）与逐条验证

run_id: 20261018_171608_963_p3_supplement（requirements 冻结，结果生成前）

A1 E1多非重叠安全train/validation窗口预固定
   证据：windows.csv 四窗口 firstIndex=1345/1441/1537/1633 互不重叠、全在 validation；结果前冻结。
   验证：实现读取 windows.csv 且断言窗口非重叠、firstIndex>=1345、lastTarget<=2016。

A2 因果release规则与初始化/起报截止时距审计
   证据：END+lag 发布规则；latest_available、issue_s、max_source_index 落盘。
   验证：test_p3x_signal_boundary + 每决策点审计字段非空。

A3 未来扰动只要求不可见前缀不变
   验证：test_p3x_causal_prefix_invariance。

A4 E2固定预算扫容量固定容量扫预算含实际饱和设计
   证据：E2A B_abs in {B_tight,B_high}（固定绝对，dev 校准 B_tight=0.5*C_full(λ,C=1)/B_high=1.2*C_full(λ,C=4)，同λ跨C统一不按C分档，非 1.5*N 耗尽点）扫 C in {1,4}；饱和度实测利用率/排队/budget_remaining。
   验证：test_p3x_saturation + test_p3x_budget_unified（B(λ,C=1)==B(λ,C=4)，四原型 budget_remaining/utilization 落预期区间）。

A5 E2主因互斥归因
   验证：test_p3x_attribution（终态互斥完备、主因唯一、关联因素另列）。

A6 E2固定总预算与随N需求对照
   证据：E2B d2_fixed vs d2_scaled，Bernoulli(0.5) 固定标记薄化（保 Poisson），d1 为 d2 嵌套子集。
   验证：test_p3x_demand_prefix + 同种子 d1 到达序列是 d2 到达序列子集，且 d1 间隔 Exp(λ)(CV≈1) 非 Erlang-2(CV≈0.707)。

A7 E3独立max_defer_s且d不变
   验证：test_p3x_maxdefer_independent（d=a+1800 恒定）。

A8 E3资源开销与质量/碳误差少量水平，误差噪声不oracle伪装因果
   证据：轴R rho_route{0,.02,.1,.5}；轴E-bias{-40,0,40}因果+偏差；轴E-noise{0,10,40} ideal+受控噪声，分离。
   验证：predictor 标签区分 seasonal(causal) / oracle_noise(IDEAL_NOISY) / oracle(IDEAL)。

A9 8新种子统计精度/重复基线/窗口与种子统计单位明确
   证据：种子 2026101901..08（dev 用 20261018）；第4节口径；E3基线/E2B d1/oracle σ=0 复用去重。

A10 旧M4_joint实际策略/预测ideal分类、图2/5/6修正与数据层定义
   证据：协议第5节；本轮仅登记口径不改论文不改旧图。

A11 新实现路径/验收命令规格明确，无论文修改
   证据：协议第6节 + 本文件；09_paper 只读。

命令规格（实现员落地后逐条记录 status/exitCode/evidence）：
  matlab -batch cd(04_scripts/p3_supplement/20261018_171608_963_p3_supplement); test_p3x_contract -> PASS
  matlab -batch ... test_p3x_signal_boundary -> PASS
  matlab -batch ... test_p3x_causal_prefix_invariance -> PASS
  matlab -batch ... test_p3x_maxdefer_independent -> PASS
  matlab -batch ... test_p3x_saturation -> PASS
  matlab -batch ... test_p3x_attribution -> PASS
  matlab -batch ... test_p3x_demand_prefix -> PASS
