# Sovereign Design Research

## 参考的商业健康产品

### Apple Health / Apple Fitness
- 克制、原生、清晰的视觉语言
- 三核心：Activity / Sleep / Mindfulness
- 每个指标有上下文解释
- 学习：信息克制、原生 macOS 风格、数据优先

### Oura Ring
- Readiness / Sleep / Activity 三大核心环
- 每天早晨给出一个明确结论
- 贡献因素分解到具体指标
- 学习：三核心架构、每日结论驱动、贡献因素分析

### WHOOP
- Recovery / Strain / Sleep Coach
- 训练负荷管理为核心差异化
- 急慢性负荷比解释训练风险
- 学习：训练负荷模型、恢复评分、睡眠教练

### Athlytic
- 训练负荷、恢复、HRV、趋势分析
- 运动处方建议
- 学习：训练负荷环、HRV 重要性

### Gentler Streak
- 温和训练建议、避免过载
- 强调可持续性而非极限
- 学习：安全第一的训练建议哲学

### Rise
- 睡眠债、能量趋势
- 展示了长期睡眠不足的累积效应
- 学习：睡眠债概念、长期趋势可视化

## 参考的开源项目（仅学习设计思路）

以下项目提供了 quantified-self、HealthKit、dashboard 的信息架构参考。
未复制任何代码。

- ActivityWatch: 时间追踪 dashboard
- HealthGPT: HealthKit + LLM 的探索
- CardinalKit: 健康研究平台架构
- awesome-quantified-self: 个人数据追踪工具汇总

## 我们学习的原则

1. **数据驱动决策** — 不以猜测替代数据
2. **每日结论** — 用户打开 App 应该得到一个清晰答案
3. **贡献因素分解** — 复杂评分要能追溯到具体指标
4. **安全第一** — 训练建议必须保守，不鼓励极限
5. **长期趋势** — 单日数据噪音大，趋势才有意义
6. **克制设计** — 少即是多，不堆砌卡片
7. **隐私优先** — 原始数据不离开设备

## 我们没有复制的

- 没有复制任何品牌 UI、图标、配色
- 没有复制任何专有算法
- 没有使用任何许可证不兼容的代码
- 所有功能基于 Apple Health 原生数据类型独立实现

## UI 改版原则

1. Today 页面是主入口 — 告诉用户今天该怎么做
2. Profile 是长期画像 — 不是每日指标堆砌
3. Recovery 聚焦恢复 — 不只是一个大数字
4. Training 替代 Workouts — 不只是流水账列表
5. Coach 是分析工作台 — 不是聊天玩具
6. Settings 充分利用空间 — 不用窄卡片

## 新增功能原则

1. 所有功能基于真实 Apple Health 数据
2. AI 辅助但不替代人的判断
3. 不做医疗诊断
4. 不确定性必须明确标注
5. 每个计算指标要能追溯到原始数据
