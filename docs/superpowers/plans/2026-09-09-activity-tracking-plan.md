# 轻食记「运动管理」实施计划

日期：2026-09-09

依据：[运动管理设计规格](../specs/2026-09-09-activity-tracking-design.md)

## 实施原则

- 三个任务并行：后端与数据库、Flutter 页面与状态、独立 QA 与最终集成。
- 三个任务都从同一个 `origin/main` 提交开始，均不得直接推送或修改 `main`。
- 先写失败测试，再实现使测试通过的最小代码。
- 后端复用现有 `JdbcTemplate`、Bearer Token、统一错误结构、Flyway、计划读取和 Today 聚合。
- Flutter 复用现有 Dio、Riverpod、`SessionController`、日期缓存、渐进式权限闭环和系统日期时间选择器。
- 服务端是运动类型、热量计算、记录、每日汇总和每周进度的唯一权威。
- 不引入 ORM、本地数据库、图表库、同步框架或新的状态管理方案。
- 不实现 Health Connect、HealthKit、实时计时、GPS、心率、训练课程、社交或离线写入队列。
- 任何实现若需要改变已确认规格，先停止并重新确认。

## 并行任务与交付关系

### 任务 A：后端与数据库

分支 `codex/activity-backend`。负责 V7 迁移、运动类型、运动记录、热量计算、日/周汇总和 Today 接入。必须用独立自动化测试固定 API 契约，并给 Flutter 提供最终请求/响应样例。

### 任务 B：Flutter 页面与状态

分支 `codex/activity-flutter`。负责数据模型、API 客户端、控制器、运动管理页、记录/编辑页、缓存、权限闭环和 Today 入口。开发期使用 Fake API 固定交互，不等待后端完成。

### 任务 C：独立 QA 与最终集成

分支 `codex/activity-qa`。先建立验收矩阵和主线基线，再等待 A、B 候选提交；合并后独立复核契约、修复真实集成缺陷，并完成 Android API 36 模拟器触控验收。不得直接推送 `main`。

最终由主任务复核 QA 唯一候选，合并到 `main`，运行主线检查并推送私有 GitHub。

## 任务 1：V7 数据库迁移与内置运动

新增：

- `backend/src/main/resources/db/migration/V7__create_activity_tracking.sql`
- `backend/src/test/java/com/lightbite/healthy/ActivityMigrationTests.java`

步骤：

1. 写 V6→V7 升级测试，确认账号、档案、计划、饮食和饮水数据保持不变。
2. 写空库迁移测试，确认 `activity_types`、`activity_records`、外键、唯一约束和索引存在。
3. 建立系统类型与用户自定义类型的规范化名称唯一规则。
4. 建立记录表的用户、发生时间、软删除和幂等约束。
5. 为时长、MET、体重快照、估算热量和最终热量加入数据库边界约束。
6. 用迁移写入 14 个中文内置运动及低、中、高三档 MET；种子写入必须可重复验证。
7. SQL 同时兼容 MySQL 8.4 与 H2 MySQL 模式。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=ActivityMigrationTests
```

## 任务 2：后端运动类型与热量计算

新增：

- `backend/src/main/java/com/lightbite/healthy/activity/ActivityDtos.java`
- `backend/src/main/java/com/lightbite/healthy/activity/ActivityService.java`
- `backend/src/main/java/com/lightbite/healthy/activity/ActivityController.java`
- `backend/src/test/java/com/lightbite/healthy/activity/ActivityServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/ActivityIntegrationTests.java`

步骤：

1. 写系统运动完整性、中文搜索和空查询测试。
2. 写自定义类型创建、名称规范化重名、无效参考类型和跨用户隔离测试。
3. 写低、中、高 MET 选择及 `MET × kg × 小时` 计算测试。
4. 写整数 kcal 四舍五入、体重/MET 快照和计算版本测试。
5. 写自动估算、人工覆盖、恢复估算和 0–10000 kcal 边界测试。
6. 写未完成档案、缺失有效体重、时长越界和未来时间中文错误测试。
7. 直接复用现有健康档案/体重读取逻辑；若缺少共享查询，只提取一个最小公共读取方法，不建设通用指标框架。

API：

- `GET /api/v1/activity/types?query=`
- `POST /api/v1/activity/types/custom`

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=ActivityServiceTests,ActivityIntegrationTests
```

## 任务 3：后端记录、汇总、计划与时区

继续修改任务 2 的服务、控制器和测试。

步骤：

1. 写创建记录后返回服务端权威日汇总和周汇总的测试。
2. 写同一用户同一幂等键串行与并发重试只创建一条记录的测试。
3. 写不同用户使用相同幂等键互不影响的测试。
4. 写编辑类型、强度、时长、时间和热量后重新保存快照的测试。
5. 写恢复自动估算、本人删除、重复删除、跨用户访问和不存在记录测试。
6. 写 UTC 保存、IANA 时区、固定偏移、跨午夜、周一和周日边界测试。
7. 写历史补录允许、未来时间拒绝和日期查询参数缺失/非法返回 400 的测试。
8. 写同一天多条记录只计一个运动日，时长与热量正确累计的测试。
9. 写活动计划目标、无计划空目标、暂停、待重算和风险阻断状态测试。

API：

- `GET /api/v1/activity/days/{date}?timezone=Asia/Shanghai`
- `GET /api/v1/activity/weeks/{date}?timezone=Asia/Shanghai`
- `POST /api/v1/activity/records`
- `PUT /api/v1/activity/records/{id}`
- `DELETE /api/v1/activity/records/{id}?timezone=Asia/Shanghai`

实现约束：

- 新增请求必须携带 `Idempotency-Key`。
- `occurredAt` 使用 ISO 8601 含偏移时间，服务端统一保存 UTC。
- 时区使用 Java `ZoneId` 验证；无效值返回中文字段错误。
- 编辑请求明确区分“自动估算”“人工覆盖”和“恢复估算”，不通过空值猜测用户意图。
- 日/周汇总只查询当前用户未删除记录，不从 Today 或 Flutter 反算。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=ActivityServiceTests,ActivityIntegrationTests
```

## 任务 4：Today 接入真实运动状态

修改：

- `backend/src/main/java/com/lightbite/healthy/today/TodayDtos.java`
- `backend/src/main/java/com/lightbite/healthy/today/TodayService.java`
- `backend/src/test/java/com/lightbite/healthy/today/TodayServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/TodayIntegrationTests.java`

步骤：

1. 写无记录 `EMPTY`、有记录 `READY`、未建档 `PROFILE_INCOMPLETE` 测试。
2. 写当天分钟、热量、次数和本周实际/目标映射测试。
3. 写无计划、暂停、待重算和风险状态目标为空或不可执行的测试。
4. 写运动查询异常时仅 activity 返回 `ERROR`，计划、体重、营养和饮水继续返回的测试。
5. Today 调用运动服务的只读汇总，不复制 SQL、热量公式或周统计规则。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=TodayServiceTests,TodayIntegrationTests
```

## 任务 5：Flutter 模型、API 与控制器

新增：

- `mobile/lib/features/activity/domain/activity_data.dart`
- `mobile/lib/features/activity/application/activity_controller.dart`
- `mobile/test/features/activity/activity_data_test.dart`
- `mobile/test/features/activity/activity_controller_test.dart`
- `mobile/test/core/api/api_client_activity_test.dart`

修改：

- `mobile/lib/core/api/api_client.dart`

步骤：

1. 写运动类型、记录、日汇总、周汇总、计划状态和未知扩展字段解析测试。
2. 写类型搜索、自定义类型、新增、编辑、删除、日查询和周查询请求契约测试。
3. 写新增生成幂等键，失败重试复用同一键的测试。
4. 写自动估算预览与服务端权威值覆盖测试。
5. 写首次加载、日期切换、刷新、账户＋日期缓存隔离测试。
6. 写旧响应不得覆盖新写入结果、页面销毁后丢弃迟到响应测试。
7. 写网络失败保留表单、缓存标记和无缓存错误状态测试。
8. 复用现有 Riverpod 自动释放模式，不新增仓储接口、本地数据库或通用表单框架。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/activity test/core/api/api_client_activity_test.dart
```

## 任务 6：Flutter 运动页面与权限闭环

新增：

- `mobile/lib/features/activity/presentation/activity_page.dart`
- `mobile/lib/features/activity/presentation/activity_record_page.dart`
- `mobile/test/features/activity/activity_page_test.dart`
- `mobile/test/features/activity/activity_record_page_test.dart`

修改：

- `mobile/lib/app/app_shell.dart`
- `mobile/lib/features/today/domain/today_data.dart`
- `mobile/lib/features/today/presentation/today_page.dart`
- 对应 Today 与 AppShell 测试。

步骤：

1. 写 Today “记录运动”和运动摘要卡进入运动页面的导航测试；不新增底部导航项。
2. 写游客点击记录进入登录、未建档进入建档、完成后恢复原操作的测试。
3. 写日期导航、当天汇总、本周进度、无计划、暂停、风险和空状态测试。
4. 写中文搜索、内置类型选择、自定义名称和相似运动选择测试。
5. 写低/中/高强度和 15/30/45/60 分钟快捷时长测试。
6. 写 1–1440 分钟键盘输入、系统日期时间选择和未来时间拦截测试。
7. 写自动估算展示、展开人工修改、恢复估算和中文边界提示测试。
8. 写编辑、中文删除确认、保存中防重复、失败保留表单和重新提交测试。
9. 所有新增主要控件使用 6 px 圆角，底部按钮避开键盘和系统手势区域。

界面约束：

- 运动管理页只保留一张本周进度卡和一组当天汇总，避免卡片堆叠。
- 使用 Flutter 原生搜索、输入和日期时间选择能力，不增加 UI 组件库或图表依赖。
- 热量输入默认收起，只有用户点击“修改”后显示。
- 周进度使用简单进度条和文字，不绘制复杂统计图。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/activity test/features/today test/app/app_shell_test.dart
flutter analyze
```

## 任务 7：独立 QA 与最终集成

新增：

- `docs/qa/activity-tracking-acceptance.md`

步骤：

1. 从相同 `origin/main` 建立 QA 分支，记录基线和 A、B 候选提交。
2. 候选合并前先写数据库、API、计算、权限、缓存、异常和设备验收矩阵。
3. 独立运行基线后端全量、Flutter 全量、静态分析、Debug APK 和仓库检查。
4. 合并 A、B 候选，解决真实契约差异，不修改无关功能。
5. 补测迁移升级、搜索重名、热量计算、快照、幂等、用户隔离、时区、周边界和 Today 降级。
6. 补测 Flutter 账户切换、日期切换、缓存隔离、迟到响应和失败表单恢复。
7. 使用 H2 测试配置启动后端，在 Android Emulator API 36 安装最终 APK。
8. 触控验收 Today 入口、内置运动、自定义运动、三档强度、快捷/手动时长、时间选择、热量覆盖、编辑和删除。
9. 验收游客、未建档、历史补录、未来拦截、断网缓存和重试。
10. 临时验证 720×1600、1.3 倍字体、键盘、底部安全区域和减少动画，结束后恢复设备设置。
11. 运行 `scripts/check.ps1`、`git diff --check`、敏感信息和构建产物扫描。
12. 记录 APK 路径、大小和 SHA-256，形成唯一最终候选，不推送 `main`。

## 任务 8：主线复核、推送与可体验环境

步骤：

1. 主任务确认 QA 分支和工作树干净，候选包含后端、Flutter、验收报告和必要修复。
2. 复核未混入 Health Connect、HealthKit、计时器、GPS、图表库或离线写入队列。
3. 将 QA 最终候选无冲突合并到 `main`。
4. 在 `main` 运行仓库总检查、后端全量、Flutter 全量和静态分析。
5. 确认 Git 作者邮箱为 `3040503900@qq.com`。
6. 推送 `origin/main` 并核对远端提交。
7. 使用 H2 测试配置在本机 8080 启动最终后端，确认模拟器可以登录和访问运动接口。

全量验证命令：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test

cd E:\Healthy\mobile
dart format lib test
flutter analyze
flutter test
flutter build apk --debug

cd E:\Healthy
.\scripts\check.ps1
git diff --check
git status --short --branch
```

## 最终完成标准

- 完成档案用户可以搜索或创建运动类型，并新增、编辑和删除运动记录。
- 低、中、高强度及快捷/手动时长可用，服务端热量计算和人工覆盖正确。
- 历史记录保存体重、MET 和计算版本快照，不随档案变化被改写。
- 当天次数、分钟、热量和本周天数/分钟统计准确。
- 有计划时展示真实目标；无计划、暂停、待重算和风险状态不伪造目标。
- Today 显示同一份权威运动摘要，运动模块失败不影响其他模块。
- 游客、未建档、用户隔离、时区、幂等、缓存和迟到响应通过测试。
- 全部用户可见文案为中文，6 px 圆角、窄屏、大字体、键盘和安全区域通过。
- 后端、Flutter、静态检查、APK、仓库检查与 Android 模拟器验收全部通过。
- 最终提交推送到私有 GitHub，主工作树干净。
