# Sovereign — 个人健康趋势监控与 AI 运动恢复分析系统

Sovereign 是一个基于 Apple 生态的个人健康分析中枢，运行在 macOS 上，未来将接入 iPhone HealthKit 和 Apple Watch 实时运动数据。

## 项目定位

Sovereign 不是医疗诊断工具，不是医疗级实时生命体征监护仪。它是基于 Apple Watch / Apple Health 数据的个人健康趋势监控、运动状态分析、恢复状态分析和 AI 健康教练系统。

所有建议谨慎、可解释、低风险。不能替代医生，不能诊断疾病，不能给药物建议。

## 当前阶段

**Mac 端已实现**，作为未来 iPhone / Apple Watch 数据同步后的核心分析中心。

### 已实现功能

- **真实 Apple Health 数据分析**：导入 export.xml 或 ZIP，解析步数、心率、HRV、睡眠、运动等数据
- **Overview 健康概览**：恢复评分、训练负荷、睡眠、静息心率一站查看
- **Trends 趋势分析**：7/30/90天趋势图（Swift Charts）
- **Recovery 恢复分析**：基于睡眠、心率、HRV、训练负荷的综合恢复评分
- **Workouts 运动分析**：运动类型、时长、距离、强度、训练负荷统计
- **AI Coach**：本地规则引擎 + DeepSeek V4 可选，基于真实数据回答
- **MenuBarExtra 菜单栏**：快速查看今日状态
- **Import Diagnostics**：导入统计、跳过原因、数据范围诊断
- **Dedup 去重**：重复导入同一文件不会产生重复数据
- **Settings 设置**：数据源管理、清空数据、重建摘要
- **Demo Data**：开发演示数据（与真实数据完全隔离）

### 未来阶段

- iPhone HealthKit 数据同步（MultipeerConnectivity / iCloud）
- Apple Watch 实时运动数据
- DeepSeek 流式响应
- 月度深度报告

## 技术栈

- SwiftUI + SwiftData + Swift Charts
- macOS Keychain（API Key 安全存储）
- URLSession（DeepSeek API 通信）
- XMLParser（Apple Health 数据解析）
- UserNotifications（本地通知）
- 纯 Apple 原生技术栈，无第三方依赖

## 运行项目

### 方式 1：终端构建

```bash
cd Sovereign
swift build
swift test
```

### 方式 2：Xcode（图形界面）

```bash
open Sovereign.xcodeproj
```

然后在 Xcode 中：
1. 顶部 Scheme 选择 **Sovereign**
2. 运行目标选择 **My Mac**
3. 按 **Cmd+R** 运行

## 导入 Apple Health 真实数据

### 如何导出

1. 在 iPhone 上打开「健康」App
2. 点击右上角头像
3. 点击「导出所有健康数据」
4. 通过 AirDrop、iCloud 或邮件发送到 Mac
5. 在 Sovereign 中：数据导入 → 拖放 export.zip 或 export.xml

### 解析的数据类型

Sovereign 解析以下 Apple Health 数据类型：
- 步数 (Step Count)
- 心率 (Heart Rate)
- 静息心率 (Resting Heart Rate)
- 心率变异性 (HRV SDNN)
- 活动能量 (Active Energy Burned)
- 运动时间 (Exercise Time)
- 步行+跑步距离 (Distance Walking/Running)
- 骑行距离 (Distance Cycling)
- 最大摄氧量 (VO2Max)
- 体重 (Body Mass)
- 身高 (Height)
- 睡眠分析 (Sleep Analysis — 含 InBed / Asleep / Deep / REM / Awake)
- 运动记录 (Workouts — 含类型、时长、距离、能量消耗)

### Demo 数据 vs 真实数据

- **Demo 数据**：首次启动且无真实数据时可加载，所有 Demo 数据在 UI 中明确标记为「Demo Data」
- **真实数据**：导入 Apple Health export.xml 后自动切换为「Apple Health Import」
- Demo 数据与真实数据完全隔离，不会混在一起
- 设置中可随时清空 Demo 数据或已导入数据

### 导入诊断

导入页面可展开「导入诊断」，查看：
- 最近一次导入文件名和时间
- 每种类型的解析数量和保存数量
- 被跳过的原因（重复数据、不支持的类型、日期/数值解析失败）
- 数据日期范围
- 当前数据库中真实数据总量

### 去重机制

重复导入同一 export.xml 不会产生重复数据。每条记录基于 `sourceName + type + date + value + unit` 生成指纹，保存前检查是否已存在。

## 配置 DeepSeek API Key

### 开发阶段（环境变量）

```bash
export DEEPSEEK_API_KEY="YOUR_DEEPSEEK_API_KEY"
```

### 正式使用（App Settings）

1. 打开 App → 设置 → AI 设置
2. 输入 API Key
3. 点击「保存到 Keychain」
4. 点击「测试连接」

### 为什么不能把 API Key 写进代码

绝对不要将 API Key 写入源码、README、测试文件、日志或 Git 提交中。API Key 必须通过环境变量或 Keychain 提供。如果 Key 泄露，请立即在 DeepSeek 控制台轮换。

## AI 分析说明

### 发送给 AI 的内容

Sovereign 只发送**结构化健康摘要**给 DeepSeek，不发送原始健康数据。摘要包括：
- 最近 7 天每日摘要（步数、睡眠、心率、恢复评分、训练负荷）
- 最近 30 天趋势（平均值、变化方向）
- 最近 10 次运动记录（类型、时长、强度）
- 本地规则引擎分析结果
- 数据质量信息（缺失指标、数据来源）

### AI 回答模式

- **Local Rules**：本地规则引擎，基于阈值判断，不发送任何数据到云端
- **DeepSeek V4**：可选云端 AI，发送结构化摘要，回答更智能
- **Fallback**：DeepSeek 失败时自动降级到本地规则

### 隐私

- 原始健康数据仅保存在本地（SwiftData）
- 发送给 DeepSeek 的仅是匿名摘要，不包含完整原始数据
- API Key 存储在 macOS Keychain 中
- AI 分析不是医疗诊断

## 健康建议免责声明

Sovereign 不是医疗设备。所有恢复评分、训练建议和 AI 分析均基于行为数据模式分析，仅供个人参考。如有健康疑虑，请咨询持证医生。

## 目前限制

- **没有实时 HealthKit 数据**：Mac 不能直接访问 iPhone HealthKit，必须手动导出导入
- **没有 iPhone / Watch 实时同步**：未来阶段计划通过 iPhone App 实现
- **Mock 数据仅供开发演示**：与真实数据完全隔离
- **DeepSeek 非流式响应**：接口已预留
- **恢复评分不能伪装成医学诊断**
- **不支持 Mac 直接读取 HealthKit**

## 项目结构

```
Sovereign/
├── Sources/SovereignMac/
│   ├── CoreImport/         # Apple Health 数据导入
│   │   ├── AppleHealthExportParser.swift  # XML 解析器（SAX 流式）
│   │   ├── AppleHealthZipImporter.swift   # ZIP 解压
│   │   ├── HealthDataNormalizer.swift     # 单位转换与标准化
│   │   └── HealthImportService.swift      # 完整导入流水线
│   ├── CoreModels/         # 数据模型（SwiftData）
│   ├── CoreServices/       # 核心服务
│   │   ├── DailySummaryBuilder.swift     # 每日摘要构建
│   │   ├── RecoveryAnalyzer.swift        # 恢复评分
│   │   ├── TrainingLoadAnalyzer.swift    # 训练负荷
│   │   ├── HealthContextBuilder.swift    # AI 上下文构建
│   │   ├── HealthPromptBuilder.swift     # AI Prompt 构建
│   │   ├── HealthSafetyGuard.swift       # 安全过滤器
│   │   ├── LocalRuleAIService.swift      # 本地规则引擎
│   │   └── DeepSeekClient.swift          # DeepSeek API 客户端
│   ├── Data/               # 数据层
│   │   ├── MacHealthStore.swift          # 中央数据存储
│   │   └── MockHealthDataProvider.swift  # Demo 数据生成
│   ├── Views/              # 视图
│   │   ├── Dashboard/      # 概览
│   │   ├── Trends/         # 趋势分析
│   │   ├── Sleep/          # 睡眠与恢复
│   │   ├── Workouts/       # 运动分析
│   │   ├── Coach/          # AI 教练
│   │   ├── Import/         # 数据导入与诊断
│   │   └── Settings/       # 设置
│   └── DesignSystem/       # 设计系统
└── Tests/
```
