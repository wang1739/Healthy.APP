# 轻食记 Healthy

轻食记是一套面向中国大陆普通成年用户的健康生活管理产品，覆盖健康档案、个性计划、饮食、饮水、运动、睡眠、每日任务、健康报告、AI 食物识别、会员和家庭协作。

本文按 v1.0.0 规划功能全部完成的最终交付形态编写。轻食记不是医疗产品，不提供疾病诊断、治疗、处方或急救服务；存在健康风险时，系统会停止普通减脂建议并提示用户咨询专业人员。

## 核心能力

- 手机验证码、密码、微信和 Apple 登录，支持设备会话与账号注销。
- 七步健康建档、身体测量历史、饮食偏好、目标与风险评估。
- 基于规则的 BMI、BMR、TDEE、营养、饮水、运动和睡眠计划。
- 今日执行中心以及饮食、饮水、运动、睡眠、工作生活任务记录。
- Health Connect 与 HealthKit 同步，支持权限撤回、去重和冲突处理。
- 日报、周报、月报、趋势分析及 PDF/图片导出。
- AI 食物图片识别；候选结果须经用户确认后才能写入记录。
- 免费、Pro、家庭版权益，微信、支付宝及 iOS 应用内购买。
- 品牌与用户 Web、运营管理后台、监控、审计、备份和恢复。

## 产品架构

```text
品牌/用户 Web ───────┐
Flutter Android/iOS ─┼─ HTTPS ─ Spring Boot API ─ MySQL
运营管理后台 ────────┘              ├─ Redis
                                    ├─ 私有对象存储
                                    ├─ 短信 / 微信 / Apple / 支付
                                    └─ AI / 推送 / 监控 / 审计
```

后端采用模块化单体，按 `auth`、`user`、`profile`、`plan`、`nutrition`、`hydration`、`activity`、`sleep`、`workplan`、`report`、`ai`、`membership`、`notification`、`admin` 和 `audit` 划分业务边界。核心健康数值由可测试、可版本化的规则生成，AI 只负责识别、解释和文字建议。

## 仓库结构

```text
Healthy.APP/
├─ backend/              Spring Boot API、数据库迁移和测试
├─ mobile/               Flutter Android/iOS 应用
├─ admin/                运营管理后台
├─ assets/               Web 静态资源
├─ docs/
│  ├─ project/           项目交付文档
│  └─ superpowers/       设计与实施计划
├─ scripts/              本地与 CI 检查脚本
├─ index.html             品牌 Web
├─ nutrition.html         饮食功能页/交互参考
├─ docker-compose.yml     本地依赖
└─ .env.example           环境变量示例
```

## 环境要求

- Java 17+
- Docker Desktop 与 Docker Compose
- Flutter 3.47+
- Android Studio / Android SDK 36+
- iOS 构建需要 macOS、Xcode 和 Apple Developer 账号

生产环境使用受控国内云、MySQL、Redis、私有对象存储和密钥服务；真实密钥不得写入仓库或 `.env.example`。

## 本地启动

### 1. 启动依赖

复制 `.env.example` 为 `.env`，只填入本地开发值，然后启动容器：

```powershell
docker compose up -d
docker compose ps
```

### 2. 启动后端

```powershell
cd backend
.\mvnw.cmd spring-boot:run
```

默认 API 地址为 `http://localhost:8080/api/v1`。可通过以下地址验证：

- `GET http://localhost:8080/api/v1/system/ping`
- `GET http://localhost:8080/actuator/health`

### 3. 启动 Flutter App

移动端已完成前两轮：统一主题、6px 圆角、今日/饮食/计划/报告/我的五项中文导航、宽屏可固定侧边栏、验证码与密码登录、安全 Token 持久化、会话自动恢复，以及可随时继续的七步健康建档。新用户可以先以游客身份浏览；保存记录或生成个人计划时会依次引导登录和完善档案。风险问卷会拦截未成年人、孕哺期、进食障碍风险、严重慢性病或不安全目标，不进入普通减脂流程。

```powershell
cd mobile
flutter pub get
flutter run
```

Android 模拟器默认通过 `http://10.0.2.2:8080/api/v1` 访问本机后端。连接其他环境时：

```powershell
flutter run --dart-define=API_BASE_URL=https://example.com/api/v1
```

### 4. 启动 Web

使用任意本地静态服务器从仓库根目录提供 `index.html`。本地允许来源必须在后端配置中明确列出，不能在生产环境使用任意 CORS 通配符。

## 配置原则

- `local`：本地 MySQL/Redis、模拟短信和第三方测试替身。
- `test`：独立数据库、存储桶、密钥和支付沙箱。
- `prod`：正式短信、登录、支付、存储、监控和备份。
- 生产启动会拒绝默认密钥、模拟验证码和不安全调试配置。
- test 与 prod 不共享账号、数据、存储桶或签名密钥。

完整变量名和说明以 `.env.example` 及部署平台配置为准。

## API 约定

- 业务接口前缀：`/api/v1`
- JSON 字段：camelCase
- 时间格式：ISO 8601，存储标准时间并按用户时区展示
- 错误字段：`code`、`message`、`fieldErrors`、`timestamp`、`path`
- 所有用户数据由认证主体限定所有权，客户端不能指定其他用户
- 关键写入、后台任务和支付回调支持幂等和安全重试

## 测试与检查

```powershell
# 仓库基础检查
.\scripts\check.ps1

# 后端
cd backend
.\mvnw.cmd test

# Flutter
cd ..\mobile
flutter analyze
flutter test
flutter build apk --debug

# Git 格式检查
cd ..
git diff --check
```

正式发布还必须执行端到端、真机兼容、无障碍、性能、SAST、DAST、依赖、密钥、渗透、支付对账、备份恢复和回滚演练。测试结果必须绑定同一提交和制品摘要。

## 构建与发布

- Android：生成签名 AAB/APK，先内部测试，再灰度发布。
- iOS：通过 Xcode 归档、TestFlight 验证后提交 App Store。
- 后端/Web/后台：从同一 Git 提交构建不可变制品，按 test → 灰度 → prod 发布。
- 数据库迁移只前进；发布前完成备份并验证回滚路径。
- 灰度期间监控错误率、P95 延迟、登录、支付、同步和核心转化指标。

## 安全与隐私

- 健康信息取得单独同意，用户可撤回授权、导出或删除数据并注销账号。
- Token 使用轮换和撤销；密码、验证码、Token 只保存安全哈希或必要摘要。
- 图片和报告使用私有对象存储与短期授权访问。
- 管理后台遵循最小权限，高风险操作记录修改前后值。
- 日志不得包含密码、验证码、完整 Token、完整手机号或完整健康档案。
- 发现安全问题时请通过仓库所有者提供的私密安全渠道报告，不要创建公开 Issue。

## 项目文档

完整 14 项项目交付文档见 [项目文档索引](docs/project/README.md)：

- [项目建议书](docs/project/01-initiation/01-project-proposal.md)
- [可行性分析报告](docs/project/01-initiation/02-feasibility-study.md)
- [需求规格说明书](docs/project/02-requirements/03-software-requirements-specification.md)
- [项目计划书](docs/project/03-planning/04-project-plan.md)
- [Agent 文档](docs/project/03-planning/05-agent-guide.md)
- [项目开发日志](docs/project/04-execution/06-development-log.md)
- [版本更新日志](docs/project/04-execution/07-changelog.md)
- [项目质量计划书](docs/project/03-planning/08-quality-plan.md)
- [项目质量检查报告](docs/project/05-quality/09-quality-inspection-report.md)
- [代码评审报告](docs/project/05-quality/10-code-review-report.md)
- [安全评审报告](docs/project/05-quality/11-security-review-report.md)
- [测试用例与测试报告](docs/project/06-testing-acceptance/13-test-cases-and-report.md)
- [项目验收报告](docs/project/06-testing-acceptance/14-acceptance-report.md)

## 版本

当前交付基线：`v1.0.0`。版本变化见[版本更新日志](docs/project/04-execution/07-changelog.md)。
