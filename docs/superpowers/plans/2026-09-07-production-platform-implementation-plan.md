# 轻食记正式上线版实施计划

日期：2026-09-07

依据：[正式上线版产品与技术设计](../specs/2026-09-04-production-platform-design.md)

## 1. 执行原则

- 按可运行的业务闭环交付，不先堆完全部后端或全部页面。
- 每项功能先写失败测试，再实现最小代码让测试通过，最后整理代码。
- 每次数据库变化只新增 Flyway 迁移，不修改已经发布的迁移。
- 每个阶段结束时依次执行后端测试、Flutter 测试、真实环境联调、密钥扫描和 Git 状态检查。
- 每个阶段只在用户验收后进入下一阶段。
- Web 保持轻量；完整健康业务只在 Flutter App 中实现。
- 当前优先交付 Android；iOS 保持源码兼容，待具备 Mac 和 Apple Developer 账号后完成签名与真机能力。
- 开发环境使用模拟短信、支付和 AI 适配器；生产凭据只能通过环境变量或密钥服务提供。

## 2. 当前基线

已完成：

- 品牌官网与响应式样式。
- 可交互的浏览器本地饮食记录原型。
- Spring Boot 4.1.1、Java 17、Maven Wrapper。
- MySQL 8.4 Docker 环境与 Flyway V1。
- `/api/v1/system/ping`、Actuator、CORS、统一错误基础和默认登录保护。
- 本地、测试环境基础配置与后端集成测试。

开发机现状：

- Java、Docker 和 Git 可用。
- Flutter、Dart、Android SDK 与 ADB 尚未安装或未加入 PATH。
- 没有 Mac 和 Apple Developer 账号。
- `C:\Users\Li\.m2\settings.xml` 当前是 0 字节空文件，会导致标准 Maven Wrapper 命令失败。阶段 0 在用户同意后先备份该文件并恢复为合法的最小 Maven 设置；修复前使用已验证的 Maven 安装设置文件显式运行。

## 3. 阶段 0：冻结并验证当前基线

### 任务 0.1：核对仓库安全与可重复启动

检查文件：

- `.gitignore`
- `.env.example`
- `docker-compose.yml`
- `backend/src/main/resources/application.yml`
- `README.md`

执行步骤：

1. 确认 `.env`、签名文件、IDE 缓存、Flutter 构建目录和 Android 本地配置均被忽略。
2. 确认 `.env.example` 只含变量名和无敏感性的示例。
3. 从空数据库启动 MySQL，并验证 Flyway 可自动初始化。
4. 启动 Spring Boot，验证 ping、健康检查、CORS 与未登录 401。
5. 启动静态官网，验证首页和饮食记录页返回 200。
6. 备份空的 Maven 用户设置文件，恢复合法配置并验证普通 Maven Wrapper 命令。
7. 更新 `README.md`，写明 Windows 开发机的准确命令。

验证命令：

```powershell
docker compose up -d mysql
docker compose ps
cd backend
.\mvnw.cmd -s E:\java_relate\maven_relate\apache-maven-3.6.3\conf\settings.xml test
.\mvnw.cmd -s E:\java_relate\maven_relate\apache-maven-3.6.3\conf\settings.xml spring-boot:run
```

验收标准：

- 后端测试全部通过。
- MySQL 为 healthy。
- `/api/v1/system/ping` 返回 `status: ok`。
- `/actuator/health` 返回 `UP`。
- `.env` 不出现在 `git status`。

### 任务 0.2：建立发布前检查脚本

新增文件：

- `scripts/check.ps1`

脚本只编排现有命令，依次检查 Git、后端测试、前端静态文件和敏感文件名，不引入新的任务框架。

验收：运行一次命令即可得到明确成功或失败结果，失败时返回非零退出码。

### 阶段 0 提交

```text
Stabilize project development baseline
```

## 4. 阶段 1：Flutter 与 Android 开发环境

### 任务 1.1：安装开发工具

需要用户允许安装：

- Flutter stable SDK。
- Android Studio。
- Android SDK Platform、Build Tools、Command-line Tools 和 Emulator。
- 一个 Android 模拟器镜像。

执行步骤：

1. 将 Flutter 安装到稳定、无中文和无空格的路径。
2. 配置 Flutter 与 Android SDK 路径。
3. 接受 Android licenses。
4. 创建 Android 模拟器。
5. 运行 `flutter doctor -v`。
6. 解决除 iOS 和 macOS 之外的阻断项。

验证命令：

```powershell
flutter --version
dart --version
adb version
flutter doctor -v
flutter devices
```

验收：Flutter、Android toolchain、Android Studio 和至少一个设备状态正常；iOS 在 Windows 上显示不可用属于预期。

### 任务 1.2：创建 Flutter 工程

新增目录：

```text
mobile/
├─ lib/
├─ test/
├─ integration_test/
├─ android/
├─ ios/
└─ pubspec.yaml
```

包名：`com.lightbite.healthy`。

创建后立即验证默认测试和 Android debug 构建，不先加入业务代码。

```powershell
flutter test
flutter build apk --debug
```

### 任务 1.3：建立最小 App 架构

建议依赖：

- `go_router`：路由与登录守卫。
- `flutter_riverpod`：用户、计划和页面状态。
- `dio`：统一 HTTP、Token 和错误处理。
- `flutter_secure_storage`：Refresh Token 等敏感本地数据。
- `shared_preferences`：非敏感界面偏好。

新增结构：

```text
mobile/lib/
├─ app/
│  ├─ app.dart
│  ├─ router.dart
│  └─ bootstrap.dart
├─ core/
│  ├─ api/
│  ├─ auth/
│  ├─ errors/
│  ├─ storage/
│  └─ theme/
├─ features/
└─ shared/
```

测试先覆盖：

- App 可启动。
- 未登录路由进入登录页。
- 已登录路由进入今日页。
- API 基址根据环境切换。
- 401 触发一次 Token 刷新而非无限重试。

### 任务 1.4：建立设计系统

新增文件：

- `mobile/lib/core/theme/app_colors.dart`
- `mobile/lib/core/theme/app_spacing.dart`
- `mobile/lib/core/theme/app_typography.dart`
- `mobile/lib/core/theme/app_theme.dart`
- `mobile/lib/shared/widgets/`

约束：

- 主要容器圆角 6px。
- 颜色、字号、间距和阴影禁止散落硬编码。
- 按钮、输入框、卡片、提示、加载、空状态和错误状态使用公共组件。
- 支持系统字体放大和深色模式的基础可读性。

### 任务 1.5：完成五项导航壳

新增页面：

- `features/today/presentation/today_page.dart`
- `features/nutrition/presentation/nutrition_page.dart`
- `features/plan/presentation/plan_page.dart`
- `features/report/presentation/report_page.dart`
- `features/account/presentation/account_page.dart`

先用空状态卡片，不写模拟业务数据。实现手机底部导航，并为宽屏预留可展开、可固定侧栏。

验收：

- 五个页面切换正常。
- 页面切换保留各自滚动位置。
- 底部栏不遮挡系统手势区。
- 小屏、横屏和大字体不溢出。
- App 可请求后端 ping 并显示服务状态。

### 阶段 1 提交

```text
Build Flutter application foundation
```

## 5. 阶段 2：账户与认证闭环

### 任务 2.0：增加 Redis 本地环境

修改 `docker-compose.yml` 与 `.env.example`，增加固定版本的 Redis、健康检查和只供本机开发使用的端口。验证码、限流计数和可撤销会话通过一个小型缓存接口访问 Redis；测试环境使用内存替身，不让普通单元测试依赖 Docker。

验收：MySQL 与 Redis 同时为 healthy，Redis 停止时认证接口返回明确的服务暂不可用错误，不错误放行验证码或限流。

### 任务 2.1：增加认证数据库

新增迁移：

- `backend/src/main/resources/db/migration/V2__create_auth_tables.sql`

创建用户、登录身份、密码、验证码、Refresh Token、设备、协议同意和注销申请表。为手机号、第三方身份、Token 哈希和状态字段建立唯一约束与索引。

先写迁移测试，验证空库升级、约束和重复身份拒绝。

### 任务 2.2：建立认证领域模型

新增包：

```text
backend/src/main/java/com/lightbite/healthy/auth/
├─ api/
├─ application/
├─ domain/
└─ infrastructure/
```

实现：

- 用户注册与查询。
- 密码哈希与验证。
- 验证码创建、过期、错误次数和单次使用。
- Access Token 和 Refresh Token。
- 设备会话与撤销。

优先使用 Spring Security 标准能力，不自行设计加密算法。

### 任务 2.3：实现模拟短信适配器

接口：

```text
POST /api/v1/auth/sms/send
POST /api/v1/auth/sms/login
```

`local` 和 `test` 使用模拟短信适配器；验证码只在开发日志的专用安全输出或测试响应中可用，`prod` 禁止启用模拟实现。

测试覆盖手机号、用途、过期、错误次数、重复使用和频率限制。

### 任务 2.4：实现密码、Token 与退出

接口：

```text
POST /api/v1/auth/password/login
POST /api/v1/auth/token/refresh
POST /api/v1/auth/logout
GET  /api/v1/account
GET  /api/v1/account/devices
DELETE /api/v1/account/devices/{id}
```

测试覆盖正确登录、错误密码、撤销会话、Token 过期、Refresh Token 轮换和跨用户访问。

### 任务 2.5：Flutter 登录流程

新增：

```text
mobile/lib/features/auth/
├─ data/
├─ domain/
└─ presentation/
```

页面包括手机号、验证码、密码、协议确认、设备和退出。Token 保存在安全存储；Access Token 过期时只允许一次并发刷新，其余请求等待结果。

Widget 与集成测试覆盖注册、登录、失败提示、重新打开 App、退出和网络失败保留输入。

### 任务 2.6：第三方登录适配边界

先建立 `WechatIdentityProvider` 和 `AppleIdentityProvider` 接口、配置校验和测试替身。只有申请到平台资质后才接生产 SDK，不在代码中伪造“已接入”。

### 阶段 2 验收

- 新用户可通过模拟验证码注册。
- 登录后重启 App 仍保持会话。
- 未登录访问健康接口返回统一 401。
- A 用户无法访问 B 用户账户或设备。
- 单设备和全部设备退出有效。
- 真实 MySQL 联调通过。

提交：

```text
Implement account authentication flow
```

## 6. 阶段 3：健康档案

### 任务 3.1：数据库与领域模型

新增迁移：

- `V3__create_health_profile_tables.sql`

创建健康档案、身体测量、目标、饮食偏好、风险答案和健康授权表。

测试唯一当前档案、测量历史顺序、用户隔离和档案版本。

### 任务 3.2：分步保存 API

实现：

```text
GET  /api/v1/profile
PUT  /api/v1/profile
POST /api/v1/profile/measurements
GET  /api/v1/profile/measurements
PUT  /api/v1/profile/preferences
POST /api/v1/profile/risk-assessment
GET  /api/v1/profile/completeness
```

后端验证出生日期、身高、体重、目标日期、过敏信息和枚举，不接受仅通过前端校验的数据。

### 任务 3.3：Flutter 分步建档

新增 `mobile/lib/features/profile/`，实现基础资料、身体数据、生活方式、饮食偏好、目标、风险和结果七步流程。

要求：

- 每步保存到后端。
- 退出后从最后完成步骤继续。
- 前进与返回不丢数据。
- 校验失败聚焦具体字段。
- 风险命中时显示清楚边界，不进入自动减脂计划。

### 阶段 3 验收

- 首次登录强制进入建档。
- 完成后进入计划预览。
- 修改关键数据触发“计划需重新计算”标记。
- 风险用户不会收到普通减脂目标。

提交：

```text
Build health profile onboarding
```

## 7. 阶段 4：个性计划引擎

### 任务 4.1：计划数据与规则版本

新增迁移：

- `V4__create_health_plan_tables.sql`

新增计划、计划版本、每日目标、规则版本和调整记录。

### 任务 4.2：实现纯计算核心

新增：

```text
backend/src/main/java/com/lightbite/healthy/plan/domain/
├─ BmiCalculator.java
├─ BmrCalculator.java
├─ TdeeCalculator.java
├─ NutritionTargetCalculator.java
├─ PlanSafetyPolicy.java
└─ PlanCalculationResult.java
```

计算代码保持无数据库和网络依赖，便于使用固定输入测试。覆盖性别、年龄、活动水平、目标速度、上下限、临界值和风险拒绝。

### 任务 4.3：计划预览和确认 API

实现：

```text
POST /api/v1/plans/preview
POST /api/v1/plans
GET  /api/v1/plans/current
GET  /api/v1/plans/history
POST /api/v1/plans/{id}/recalculate
PUT  /api/v1/plans/{id}/targets
POST /api/v1/plans/{id}/pause
POST /api/v1/plans/{id}/resume
```

预览不修改当前计划；确认后才创建新版本。历史计划保持可读。

### 任务 4.4：Flutter 计划流程

实现生成中、预览、营养、饮水、运动、睡眠、解释、调整、历史和暂停页面。所有核心数值显示计算依据，AI 文案缺失时仍能显示规则说明。

### 阶段 4 验收

- 固定档案得到固定结果。
- 不安全热量和减重速度被拒绝。
- 用户确认前当前计划不变化。
- 重算后历史版本仍可查看。
- 完成第一条核心闭环：注册、建档、生成计划、进入首页。

提交：

```text
Generate safe personalized health plans
```

## 8. 阶段 5：今日执行中心

### 任务 5.1：聚合接口

新增 `today` 应用服务与：

```text
GET /api/v1/today?date=YYYY-MM-DD
```

返回计划、营养、饮水、运动、睡眠、任务、体重、评分和下一步建议。单个模块缺少数据时返回空状态，不让整个响应失败。

### 任务 5.2：Flutter 今日页

实现轮播、进度卡、快捷记录、建议、打卡和消息入口。图片使用明确授权的本地或对象存储资源，不把临时外链作为生产素材。

### 任务 5.3：缓存与刷新

先展示最近缓存，再请求新数据；新增记录后局部刷新。跨天、时区变化和计划暂停均有测试。

提交：

```text
Build daily health dashboard
```

## 9. 阶段 6：饮食与饮水云端闭环

### 任务 6.1：数据库

新增：

- `V5__create_nutrition_tables.sql`
- `V6__create_hydration_tables.sql`

创建食物、份量、自定义食物、餐食、明细、每日汇总、收藏、模板、饮水和饮水设置。

### 任务 6.2：食物库与营养计算

实现分页搜索、份量换算和服务端营养汇总。用固定食物样本验证克数换算、小数精度和修改后重算。

### 任务 6.3：餐食 CRUD

实现设计文档中的 meals、items、daily 和 trend 接口。所有写请求支持唯一操作号，删除与修改进行用户隔离和状态冲突检查。

### 任务 6.4：饮水 API

按毫升保存，提供当天记录、增加、删除和设置。杯量修改不改变历史记录。

### 任务 6.5：迁移现有交互

将 `nutrition.js` 已验证的添加、编辑、删除、目标、建议和趋势体验迁移到 Flutter，不直接复制 DOM 代码。浏览器原型继续保留作视觉和功能参考。

### 任务 6.6：离线队列

App 本地保存未同步操作，联网后按操作号重试。测试断网添加、重复重试、服务端已成功但客户端超时和多设备冲突。

提交：

```text
Persist nutrition and hydration records
```

## 10. 阶段 7：运动、睡眠与系统健康数据

### 任务 7.1：手动运动与睡眠

新增迁移：

- `V7__create_activity_tables.sql`
- `V8__create_sleep_tables.sql`

先实现手动记录、编辑、删除、目标和趋势，确保拒绝系统权限时产品仍可完整使用。

### 任务 7.2：Android Health Connect

实现权限说明、按需授权、增量读取、来源 ID 去重、同步游标、取消授权和状态页面。只请求已展示用途的数据类型。

### 任务 7.3：HealthKit 兼容层

在 Flutter 侧保留同一领域接口和 iOS 配置说明；不在 Windows 上声称完成真机验证。具备 Mac 后单独执行签名、权限文案和真机测试任务。

### 任务 7.4：冲突处理

手动与系统数据时间重叠时标记冲突，由用户选择保留项。测试重复同步、权限撤销、时区变化和跨午夜睡眠。

提交：

```text
Track activity sleep and health data
```

## 11. 阶段 8：工作与生活计划

新增迁移：

- `V9__create_daily_task_tables.sql`
- `V10__create_notification_tables.sql`

实现每日任务、重复规则、完成、跳过、延期和提醒设置，并记录通知任务与送达状态。

Flutter 实现今日时间轴、新建与编辑、重复、提醒、延期、周概览和勿扰设置。健康计划生成任务与用户任务标明来源，但都允许用户调整。

Android 首先使用本地通知；服务端推送只在确有跨设备需求时接入。测试跨天、夏令时、重复任务边界、关闭提醒和勿扰时间。

提交：

```text
Schedule daily health and life tasks
```

## 12. 阶段 9：健康报告

新增迁移 `V11__create_health_report_tables.sql`，创建报告、指标、建议和导出记录。

执行步骤：

1. 实现可重复测试的周期统计服务。
2. 实现日报查询。
3. 实现周报、月报后台任务和唯一周期约束。
4. 实现报告列表、详情、指标趋势和体重趋势页面。
5. 实现图片或 PDF 导出。
6. AI 解释不可用时回退到规则模板。

验收：数字可追溯到原始记录；数据不足不生成确定性结论；任务重试不生成重复报告。

提交：

```text
Generate traceable health reports
```

## 13. 阶段 10：AI 食物识别

### 任务 10.1：服务选型验证

使用少量已获授权的测试图片评估候选服务的中国大陆可用性、食物覆盖、延迟、价格、数据保存条款和删除能力。验证结果形成单独记录后再决定供应商。

### 任务 10.2：私有文件上传

新增迁移 `V12__create_asset_and_ai_tables.sql`。实现临时上传凭证、格式和大小限制、所有权、生命周期和私有下载。

### 任务 10.3：异步识别任务

实现创建任务、轮询状态、失败重试、候选结果、置信度和用户确认。只有确认操作创建餐食记录。

### 任务 10.4：Flutter 拍照流程

实现权限说明、相机或相册、裁剪、压缩、上传、排队、识别、低置信度修改、失败和转手动模式。

### 任务 10.5：额度与成本

记录调用次数、耗时和失败分类；按会员权益限制每日额度，重复请求不重复扣减。

提交：

```text
Add confirmable AI food recognition
```

## 14. 阶段 11：会员、家庭与支付

新增迁移 `V13__create_membership_payment_tables.sql`。

执行顺序：

1. 建立免费、Pro、家庭版产品与权益模型。
2. 所有受限接口在服务端检查权益。
3. 实现家庭组、邀请、成员退出和最多五人限制。
4. 使用沙箱实现订单状态机。
5. 接入微信支付沙箱与回调验签。
6. 接入支付宝沙箱与回调验签。
7. 验证重复回调、超时、取消、退款和会员到期。
8. iOS 应用内购买保留适配边界，待 Apple 环境完成。

真实支付接入前需要用户提供已申请的商户和开放平台资质，凭据不进入 Git。

提交：

```text
Enforce membership and payment entitlements
```

## 15. 阶段 12：轻量 Web 与管理后台

### 任务 12.1：Web 用户端

在保留现有品牌官网的基础上增加登录、健康概览、报告、数据导出、账户安全、隐私授权和注销。修复所有 `href="#"`、空下载地址和演示性数据声明。

### 任务 12.2：管理后台

新增 `V14__create_admin_content_tables.sql`，建立管理员账户、角色、审计、反馈、轮播和运营配置。按最小范围实现用户支持、食物库、食谱、轮播、AI 统计、会员产品、订单、反馈、通知模板和配置。

管理操作默认脱敏；查看必要敏感信息需要更高权限并写审计记录。

提交：

```text
Build lightweight web and operations console
```

## 16. 阶段 13：安全、合规和生产基础设施

### 任务 13.1：安全加固

- 登录、验证码、上传和 AI 接口限流。
- Token 撤销与密钥轮换。
- 对象存储私有访问。
- 日志脱敏与请求追踪。
- 越权、注入、恶意文件、支付伪造和管理权限测试。
- Git 历史与依赖漏洞扫描。

### 任务 13.2：隐私功能

- 隐私政策与用户协议版本记录。
- 健康数据单独授权和撤回。
- 第三方 SDK 清单与个人信息收集清单。
- 个人数据导出。
- 记录删除和账号注销。
- 首次同意前不初始化非必要 SDK。

### 任务 13.3：生产环境

需要用户准备域名、国内云账号和备案主体。部署 HTTPS、MySQL、Redis、对象存储、备份、监控、告警和回滚流程。测试、生产环境使用独立资源和密钥。

### 任务 13.4：性能与恢复

执行首页、食物搜索、写记录、报告和登录压测；检查分页与慢查询。完成数据库备份恢复演练、服务回滚演练和第三方故障降级。

提交：

```text
Prepare secure production deployment
```

## 17. 阶段 14：Android 发布与 iOS 后续

### Android 发布

1. 确定最终应用名称、图标、启动图、包名和版本策略。
2. 创建并离线备份发布签名。
3. 构建 release AAB/APK。
4. 在真实设备进行安装、升级、权限、弱网和支付测试。
5. 准备应用截图、说明、隐私材料和客服信息。
6. 先内部测试，再小范围灰度，最后正式发布。

### iOS 后续前置条件

用户准备 Mac 与 Apple Developer 账号后：

1. 配置 Bundle ID、证书和 Provisioning Profile。
2. 验证 Apple 登录。
3. 验证 HealthKit 权限和数据。
4. 接入并验证应用内购买。
5. 完成 iPhone 尺寸与无障碍测试。
6. TestFlight 内测。
7. App Store 审核与发布。

## 18. 每阶段固定验证清单

```powershell
# 后端
cd E:\Healthy\backend
.\mvnw.cmd -s E:\java_relate\maven_relate\apache-maven-3.6.3\conf\settings.xml test

# Flutter
cd E:\Healthy\mobile
flutter analyze
flutter test
flutter build apk --debug

# 基础设施
cd E:\Healthy
docker compose ps

# 代码与密钥
git diff --check
git status --short
```

阶段涉及真实数据库时，再启动后端并请求健康检查和该阶段关键接口。阶段涉及 Android 原生权限时，必须在模拟器与至少一台真机测试。

## 19. 外部账号与用户配合节点

不需要立即准备全部账号。按以下时点提供：

- 阶段 2 生产化前：国内短信账号、微信开放平台应用。
- 阶段 7：Android Health Connect 真机；iOS 验证延后。
- 阶段 10：AI 服务和对象存储账号。
- 阶段 11：微信支付、支付宝商户；Apple 支付延后。
- 阶段 13：域名、云服务器、备案主体和正式客服信息。
- 阶段 14：安卓应用市场账号；之后准备 Mac 与 Apple Developer 账号。

## 20. 第一轮实施范围

获得本计划批准后，只执行阶段 0 和阶段 1：

1. 稳定并标记当前基线。
2. 安装 Flutter 与 Android 开发工具。
3. 创建 `mobile/` 工程。
4. 建立主题、路由、状态、API 和安全存储基础。
5. 建立五项导航空壳。
6. 连接 Spring Boot ping。
7. 完成测试、Android debug 构建、用户验收和 Git 提交。

第一轮不实现登录、健康档案或计划算法。阶段 1 验收后，再单独开始阶段 2，避免未经验证的基础上同时堆叠多个业务模块。
