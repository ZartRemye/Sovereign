# Sovereign — 个人健康趋势监控与 AI 运动恢复分析系统

Sovereign 是一个基于 Apple 生态的个人健康分析中枢，运行在 macOS 上，未来将接入 iPhone HealthKit 和 Apple Watch 实时运动数据。

## 项目定位

Sovereign 不是医疗诊断工具，不是医疗级实时生命体征监护仪。它是基于 Apple Watch / Apple Health 数据的个人健康趋势监控、运动状态分析、恢复状态分析和 AI 健康教练系统。

所有建议谨慎、可解释、低风险。不能替代医生，不能诊断疾病，不能给药物建议。

## 当前阶段

**Mac 端先实现**，作为未来 iPhone / Apple Watch 数据同步后的核心分析中心。

### 已实现功能

- Dashboard 健康总览
- Live Monitor 实时监控（Mock 数据模拟）
- Trends 趋势分析（7/30/90天，Swift Charts）
- Sleep & Recovery 睡眠与恢复分析
- Workouts 运动记录分析
- AI Coach（本地规则引擎 + DeepSeek V4 可选）
- Reports 健康报告（日报/周报/月报）
- Alerts 异常提醒
- Apple Health export.xml / ZIP 导入
- MenuBarExtra 菜单栏常驻
- Settings 设置页面
- 后台分析调度器
- macOS 通知提醒

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

## 导入 Apple Health 数据

1. 在 iPhone 上打开「健康」App
2. 点击右上角头像
3. 点击「导出所有健康数据」
4. 通过 AirDrop、iCloud 或邮件发送到 Mac
5. 在 Sovereign 中：数据导入 → 拖放 export.zip 或 export.xml

Sovereign 解析以下数据类型：
- 步数、心率、静息心率、HRV
- 活动能量、运动时间、步行+跑步距离
- 最大摄氧量 (VO2Max)
- 睡眠分析
- 运动记录

## 隐私

- 原始健康数据仅保存在本地（SwiftData）
- 发送给 DeepSeek 的仅是匿名摘要，不包含完整原始数据
- API Key 存储在 macOS Keychain 中
- AI 分析不是医疗诊断

## 健康建议免责声明

Sovereign 不是医疗设备。所有恢复评分、训练建议和 AI 分析均基于行为数据模式分析，仅供个人参考。如有健康疑虑，请咨询持证医生。

## 目前限制

- 没有实时 HealthKit 数据（Mac 限制）
- 没有 iPhone / Watch 实时同步（未来阶段）
- Mock 数据仅供开发演示
- DeepSeek 非流式响应（接口已预留）
- 恢复评分不能伪装成医学诊断
