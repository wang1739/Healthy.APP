# 轻食记「饮水管理」实施计划

日期：2026-09-08

依据：[饮水管理设计规格](../specs/2026-09-08-hydration-tracking-design.md)

## 实施原则

- 三个任务并行：后端与数据库、Flutter 页面与本地通知、独立 QA 与最终集成。
- 先写失败测试，再实现使测试通过的最小代码。
- 后端复用现有 `JdbcTemplate`、Bearer Token、统一错误结构、Flyway 和 Today 聚合，不新增 ORM、缓存或后台任务。
- Flutter 复用 Dio、Riverpod、`SessionController`、日期缓存和渐进式权限闭环。
- 服务端是饮水记录、设置和每日汇总的唯一权威；本地通知只负责提醒。
- 本地通知使用 `flutter_local_notifications`、`timezone` 和 `flutter_timezone`，采用非精确调度，不申请 Android 精确闹钟权限。
- 不顺带实现运动、睡眠、任务、报告、服务端推送或离线写入队列。
- 任何实现若需要改变已确认规格，先停止并重新确认。

## 并行任务与交付关系

### 任务 A：后端与数据库

分支 `codex/hydration-backend`。负责 V6 迁移、饮水设置、记录、汇总、目标优先级和 Today 接入。必须以独立自动化测试固定 API 契约。

### 任务 B：Flutter 页面与本地通知

分支 `codex/hydration-flutter`。负责数据模型、API 客户端、控制器、饮水页、设置页和本地通知。开发时使用 Fake API 与可替换时钟/调度函数，不等待真实后端。

### 任务 C：独立 QA 与最终集成

分支 `codex/hydration-qa`。先建立验收矩阵和基线，再等待 A、B 提交并集成；只修复真实契约或状态缺陷，完成 Android 模拟器触控验收。不得直接推送 `main`。

最终由主任务复核 QA 候选，合并到 `main`，运行主线检查并推送私有 GitHub。

## 任务 1：V6 数据库迁移

新增：

- `backend/src/main/resources/db/migration/V6__create_hydration_tracking.sql`
- `backend/src/test/java/com/lightbite/healthy/HydrationMigrationTests.java`

步骤：

1. 写 V5→V6 升级测试，确认账号、档案、计划、食物和餐食数据保持不变。
2. 写空库迁移测试，确认 `hydration_settings` 和 `hydration_entries` 表、外键、唯一约束及索引存在。
3. `hydration_settings.user_id` 设唯一约束；保存目标覆盖、默认杯量、提醒设置、目标来源、来源计划版本和乐观版本。
4. `hydration_entries` 保存用户、容量、UTC 发生时间、创建时区、来源、幂等键和软删除时间。
5. 对 `(user_id, idempotency_key)` 建唯一约束；为用户、发生时间和未删除查询建立必要索引。
6. 为容量、目标、杯量、提醒间隔和设置版本加入数据库边界约束。
7. SQL 同时兼容 MySQL 8.4 与测试使用的 H2 MySQL 模式。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=HydrationMigrationTests
```

## 任务 2：后端饮水设置与目标优先级

新增：

- `backend/src/main/java/com/lightbite/healthy/hydration/HydrationDtos.java`
- `backend/src/main/java/com/lightbite/healthy/hydration/HydrationService.java`
- `backend/src/main/java/com/lightbite/healthy/hydration/HydrationController.java`
- `backend/src/test/java/com/lightbite/healthy/hydration/HydrationServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/HydrationIntegrationTests.java`

步骤：

1. 写默认设置测试：默认杯量 250 ml、无计划时目标 2000 ml。
2. 写活动计划目标优先于系统默认的测试。
3. 写用户手动目标优先于计划目标的测试。
4. 写计划版本变化时返回 `planTargetChanged=true` 但不覆盖用户目标的测试。
5. 写采用计划目标后清除手动覆盖并记录来源版本的测试。
6. 写目标 500–6000 ml 且按 50 ml、杯量 50–2000 ml、提醒时间范围与间隔的中文字段校验测试。
7. 写设置版本冲突测试，返回明确的 `HYDRATION_SETTINGS_VERSION_CONFLICT`。
8. 使用现有 `JdbcTemplate` 实现读取、更新和采用计划目标，不建立通用设置框架。

API：

- `GET /api/v1/hydration/settings`
- `PUT /api/v1/hydration/settings`
- `POST /api/v1/hydration/settings/adopt-plan-target`

实现约束：

- 控制器只从认证主体获取用户身份。
- 返回有效目标、目标来源、当前计划目标和是否存在计划更新。
- 设置不存在时按读取规则构造默认值；首次写入才落库。
- 目标计算复用现有活动计划数据，不复制计划公式。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=HydrationServiceTests,HydrationIntegrationTests
```

## 任务 3：后端记录、汇总与时区

继续修改任务 2 的服务、控制器与测试。

步骤：

1. 写 1 ml、快捷容量、3000 ml 和越界容量测试。
2. 写记录创建后返回完整服务端权威日汇总的测试。
3. 写相同用户和幂等键重复提交只创建一条记录的串行与并发测试。
4. 写不同用户使用相同幂等键互不影响的测试。
5. 写本人删除、重复删除、跨用户删除和不存在记录测试。
6. 写修改默认杯量不改变历史记录容量的测试。
7. 写 UTC 保存、用户本地日期、跨午夜、固定偏移和 IANA 时区测试。
8. 写未来时间拒绝、历史日期允许补录测试。
9. 实现按日读取、创建、软删除和汇总；成功写入返回同一日期完整响应。

API：

- `GET /api/v1/hydration/days/{date}?timezone=Asia/Shanghai`
- `POST /api/v1/hydration/entries`
- `DELETE /api/v1/hydration/entries/{id}?timezone=Asia/Shanghai`

实现约束：

- 新增请求必须携带 `Idempotency-Key`。
- `occurredAt` 使用 ISO 8601 含偏移时间；服务端转换并保存 UTC。
- 时区值必须由 Java `ZoneId` 验证；无效值返回中文字段错误。
- 当日响应包含记录、总量、有效目标、剩余量、实际完成比例、目标来源和缓存无关的页面状态。
- 完成比例可超过 100%，UI 绘制时自行封顶。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=HydrationServiceTests,HydrationIntegrationTests
```

## 任务 4：Today 接入真实饮水状态

修改：

- `backend/src/main/java/com/lightbite/healthy/today/TodayDtos.java`
- `backend/src/main/java/com/lightbite/healthy/today/TodayService.java`
- `backend/src/test/java/com/lightbite/healthy/today/TodayServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/TodayIntegrationTests.java`

步骤：

1. 写无记录返回 `EMPTY`、有记录返回 `READY` 的测试。
2. 写 `consumedMl`、`targetMl`、`remainingMl` 和 `progress` 映射测试。
3. 写档案未完成返回 `PROFILE_INCOMPLETE` 且不暴露旧记录的测试。
4. 写饮水查询异常时只让 hydration 模块返回 `ERROR`，计划、体重和营养继续返回的测试。
5. `TodayService` 调用 `HydrationService` 只读汇总，不复制 SQL、目标优先级或时区逻辑。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=TodayServiceTests,TodayIntegrationTests
```

## 任务 5：Flutter 模型、API 与控制器

新增：

- `mobile/lib/features/hydration/domain/hydration_data.dart`
- `mobile/lib/features/hydration/application/hydration_controller.dart`
- `mobile/test/features/hydration/hydration_data_test.dart`
- `mobile/test/features/hydration/hydration_controller_test.dart`
- `mobile/test/core/api/api_client_hydration_test.dart`

修改：

- `mobile/lib/core/api/api_client.dart`

步骤：

1. 写设置、目标来源、记录、日汇总和未知扩展字段的 JSON 解析测试。
2. 写读取日期、创建、删除、读取设置、更新设置和采用计划目标的请求契约测试。
3. 写新增操作生成并在失败重试中复用 `Idempotency-Key` 的测试。
4. 写首次加载、日期切换、刷新、用户＋日期缓存隔离和页面销毁测试。
5. 写旧读取响应不得覆盖新写入权威响应的测试。
6. 写跨日期在途写入只能更新对应日期缓存的测试。
7. 写预计进度、失败撤回、保留容量和重新添加测试。
8. 写设置版本冲突触发刷新且不丢弃用户草稿的测试。
9. 复用现有 Riverpod 自动释放方式，不新增第二套状态框架或持久数据库。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/hydration test/core/api/api_client_hydration_test.dart
```

## 任务 6：Flutter 饮水页面与权限闭环

新增：

- `mobile/lib/features/hydration/presentation/hydration_page.dart`
- `mobile/lib/features/hydration/presentation/hydration_progress.dart`
- `mobile/lib/features/hydration/presentation/hydration_settings_sheet.dart`
- `mobile/test/features/hydration/hydration_page_test.dart`
- `mobile/test/features/hydration/hydration_settings_sheet_test.dart`

修改：

- `mobile/lib/app/app_shell.dart`
- `mobile/lib/features/today/presentation/today_page.dart`
- 对应现有 AppShell 与 Today 测试。

步骤：

1. 写游客可浏览结构、写操作进入登录，以及未建档进入建档的测试。
2. 写日期导航、返回今天、空状态、缓存状态和网络失败测试。
3. 写进度、已喝、目标、剩余量和超出目标真实文案测试。
4. 写主按钮使用默认杯量，以及 100、200、250、300、500 ml 预设容量测试。
5. 写自定义 1–3000 ml 数字输入、键盘遮挡和中文校验测试。
6. 写记录按时间倒序、中文二次确认和删除失败测试。
7. 写设置目标、默认杯量、时间、间隔、勿扰和采用计划目标测试。
8. 替换 Today 中饮水 `COMING_SOON` 展示，让快捷入口进入同一饮水页面。
9. 所有新增主要控件使用 6 px 圆角；验证 720×1600 和 1.3 倍字体。

界面约束：

- 顶部只放一个饮水进度区，避免卡片堆叠。
- “+默认杯量”是单手可触达的主操作。
- 目标进度绘制上限为 100%，文字保留实际超过量。
- 设置使用现有底部弹层模式，不新增复杂路由。
- 只有自定义容量和目标数值需要键盘，时间使用系统时间选择器。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/hydration test/features/today test/app/app_shell_test.dart
```

## 任务 7：本地通知与时区调度

新增：

- `mobile/lib/features/hydration/application/hydration_reminder_scheduler.dart`
- `mobile/test/features/hydration/hydration_reminder_scheduler_test.dart`

修改：

- `mobile/pubspec.yaml`
- `mobile/android/app/src/main/AndroidManifest.xml`
- `mobile/ios/Runner/AppDelegate.swift` 或当前 iOS 初始化文件（仅在插件要求时）。
- App 启动和退出登录的最小接入点。

依赖：

- `flutter_local_notifications`：本地通知和计划调度。
- `timezone`：时区感知的触发时间。
- `flutter_timezone`：读取设备 IANA 时区。

步骤：

1. 写纯函数测试：开始/结束时间、间隔、勿扰、跨午夜、过去时间和次日时间的候选通知列表。
2. 写达标返回空列表、删除后重新低于目标恢复未来提醒的测试。
3. 写设置变化、日期变化和退出登录触发取消/重排的测试。
4. 初始化时不主动请求权限；只在用户打开提醒时请求 Android 13+/iOS 通知权限。
5. Android 仅声明 `POST_NOTIFICATIONS`、`RECEIVE_BOOT_COMPLETED` 和插件要求的调度接收器。
6. 使用非精确、允许低功耗模式的调度，不申请 `SCHEDULE_EXACT_ALARM` 或 `USE_EXACT_ALARM`。
7. 通知 ID 按账号摘要与时间槽稳定生成，退出登录只取消轻食记饮水提醒。
8. 使用中文非敏感文案；点击通知进入应用饮水页。
9. 通过构造函数传入时钟和通知调用函数作为测试缝隙，不建立只有一个实现的抽象接口层。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/hydration/hydration_reminder_scheduler_test.dart
flutter analyze
```

## 任务 8：独立 QA 与集成验收

新增：

- `docs/qa/hydration-tracking-acceptance.md`

步骤：

1. 从同一 `origin/main` 建立 QA 分支，记录基线和后端、Flutter 候选提交。
2. 候选合并前先写数据库、API、Flutter、权限、通知、异常和设备验收矩阵。
3. 合并 A、B 候选，解决真实契约差异，不修改无关功能。
4. 运行 V5→V6、后端全量、Flutter 全量、静态分析和格式检查。
5. 构建 Debug APK，记录路径、大小和 SHA-256。
6. 使用 H2 测试配置启动集成后端，在 Android Emulator API 36 安装 APK。
7. 验收登录、250 ml 快捷新增、预设、自定义、删除、日期切换、修改杯量、目标优先级和断网缓存。
8. 验收通知权限允许/拒绝、通知计划存在、达标取消及退出登录取消。
9. 临时设置 720×1600 与 1.3 倍字体，结束后恢复 1080×2400 与 1.0。
10. 运行 `scripts/check.ps1`、`git diff --check`、凭据和构建产物扫描。
11. 把实际结果、修复和环境遗留写入验收文档，形成唯一候选提交，不推送 `main`。

## 任务 9：主线复核、推送与可体验环境

步骤：

1. 主任务确认 QA 分支和工作树干净，候选包含后端、Flutter、验收报告和必要修复。
2. 复核没有混入运动、睡眠、任务、报告或服务端推送。
3. 将 QA 最终候选快进或无冲突合并到 `main`。
4. 在 `main` 运行仓库总检查与关键全量测试。
5. 确认 Git 作者邮箱为 `3040503900@qq.com`。
6. 推送 `origin/main` 并核对远端提交。
7. 使用 H2 测试配置在本机 8080 启动最终后端，确认模拟器可访问；明确提示 H2 重启后数据清空。

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

- 完成档案用户可按日期新增和删除饮水记录，跨设备读取一致。
- 默认杯量、预设容量和自定义容量路径均可用。
- 修改默认杯量不改写历史记录。
- 用户目标、活动计划目标和 2000 ml 默认目标优先级正确。
- Today 显示真实饮水量、目标、剩余量和进度，模块失败不影响其他内容。
- 本地通知按时间范围、间隔和勿扰设置安排，达标与退出登录后正确取消。
- 通知权限拒绝不影响记录功能。
- 用户隔离、时区、幂等、版本冲突和缓存状态通过测试。
- 全部用户可见文案为中文，6 px 圆角、窄屏和大字体通过。
- 后端、Flutter、静态检查、APK、仓库检查与 Android 模拟器验收全部通过。
- 最终提交推送至私有 GitHub，主工作树干净。
