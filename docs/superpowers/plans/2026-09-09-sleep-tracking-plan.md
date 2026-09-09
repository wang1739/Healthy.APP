# 轻食记「睡眠管理」实施计划

日期：2026-09-09

依据：[睡眠管理设计规格](../specs/2026-09-09-sleep-tracking-design.md)

## 实施原则

- 继续使用“健康饮食”项目内已有的后端、Flutter、QA 三个任务，不创建新对话。
- 三个任务分别创建新的睡眠工作树和分支，统一从确认后的 `origin/main` 精确提交开始。
- 后端复用 `JdbcTemplate`、认证、统一错误、Flyway、计划读取与 Today 单模块降级。
- Flutter 复用 Dio、Riverpod、会话权限闭环、日期缓存、`shared_preferences` 和已有本地通知调度能力。
- 服务端是睡眠记录、时长、归档日期和统计的唯一权威；设备只负责页面、缓存与提醒。
- 先写失败测试，再实现使测试通过的最小代码。
- 不新增依赖、ORM、本地数据库、图表库、后台推送或健康平台同步框架。
- 不顺带实现任务管理、周期报告、闹钟、睡眠阶段或医疗分析。
- 需要改变确认规格时先停止并重新确认。

## 三个既有任务与分支

### 后端任务

继续使用已有“运动管理后端开发”对话，并在开始时改名为“睡眠管理后端开发”。新工作树 `E:\Healthy-worktrees\sleep-backend`，分支 `codex/sleep-backend`。负责 V8、睡眠记录/标签、日与 7 天汇总、计划状态和 Today 接入。

### Flutter 任务

继续使用已有“运动管理 Flutter 开发”对话，并在开始时改名为“睡眠管理 Flutter 开发”。新工作树 `E:\Healthy-worktrees\sleep-flutter`，分支 `codex/sleep-flutter`。负责模型、API、控制器、页面、缓存、本地提醒和 Today 入口。

### QA 任务

继续使用已有“运动管理 QA 集成”对话，并在开始时改名为“睡眠管理 QA 集成”。新工作树 `E:\Healthy-worktrees\sleep-qa`，分支 `codex/sleep-qa`。先建立验收矩阵和基线，等待两个候选后完成集成、模拟器验收和最终 APK。

三个任务均不得直接推送 `main`。QA 形成唯一候选，主任务复核后合并并推送。

## 任务 1：V8 数据库迁移

新增：

- `backend/src/main/resources/db/migration/V8__create_sleep_tracking.sql`
- `backend/src/test/java/com/lightbite/healthy/SleepMigrationTests.java`

步骤：

1. 写 V7→V8 升级测试，确认账号、档案、计划、饮食、饮水和运动数据不变。
2. 写空库迁移测试，确认 `sleep_records`、`sleep_record_tags`、外键、约束和索引存在。
3. 记录表保存用户、类型、UTC 开始/结束时间、时区、醒来日期、服务端时长、质量、备注、来源、外部来源、幂等键和软删除时间。
4. 标签表使用 `(sleep_record_id, tag_code)` 唯一约束。
5. 为记录类型、时长、质量、备注长度和标签代码添加数据库约束。
6. 建立用户醒来日期、时间区间和未删除查询所需最小索引。
7. SQL 同时兼容 MySQL 8.4 与 H2 MySQL 模式。

阶段验证：

```powershell
cd E:\Healthy-worktrees\sleep-backend\backend
.\mvnw.cmd test -Dtest=SleepMigrationTests
```

## 任务 2：后端睡眠记录与校验

新增：

- `backend/src/main/java/com/lightbite/healthy/sleep/SleepDtos.java`
- `backend/src/main/java/com/lightbite/healthy/sleep/SleepService.java`
- `backend/src/main/java/com/lightbite/healthy/sleep/SleepController.java`
- `backend/src/test/java/com/lightbite/healthy/sleep/SleepServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/SleepIntegrationTests.java`

步骤：

1. 写夜间睡眠与小睡新增测试，确认服务端计算分钟数和醒来日期。
2. 写夜间 30 分钟/16 小时、小睡 5 分钟/4 小时边界及越界测试。
3. 写结束早于开始、超过服务器当前时间 5 分钟和历史补录测试。
4. 写跨午夜、IANA 时区、固定偏移和无效时区测试。
5. 写同日第二条夜间睡眠、夜间与小睡重叠、小睡互相重叠测试。
6. 写 1–5 质量、空质量、固定标签、未知/重复标签和 500 字备注边界测试。
7. 写创建幂等的串行、并发和跨用户测试。
8. 写编辑时排除自身后重新检查归档、时长、重复和重叠的测试。
9. 写本人软删除、重复删除、跨用户访问和不存在记录测试。
10. 控制器只从认证主体获取用户身份，所有失败返回现有中文错误结构。

API：

- `GET /api/v1/sleep/days/{date}?timezone=Asia/Shanghai`
- `GET /api/v1/sleep/weeks/{date}?timezone=Asia/Shanghai`
- `POST /api/v1/sleep/records`
- `PUT /api/v1/sleep/records/{id}`
- `DELETE /api/v1/sleep/records/{id}?timezone=Asia/Shanghai`

实现约束：

- 创建必须携带 `Idempotency-Key`。
- 客户端不得提交时长、醒来日期或目标达标结果。
- 重叠检查只查当前用户未删除记录，并在编辑时排除当前 ID。
- 标签采用固定枚举/集合校验，不建设可配置标签后台。

阶段验证：

```powershell
cd E:\Healthy-worktrees\sleep-backend\backend
.\mvnw.cmd test -Dtest=SleepServiceTests,SleepIntegrationTests
```

## 任务 3：后端日汇总、7 天统计与目标

继续修改睡眠服务和测试。

步骤：

1. 写所选醒来日期的夜间睡眠、小睡列表和总时长测试。
2. 写所选日期及之前 6 天的范围边界测试。
3. 写平均夜间时长、小睡总时长和同日汇总测试。
4. 写质量只统计已评价夜间记录的测试。
5. 写夜间记录少于 3 条为 `hasEnoughTrendData=false`，达到 3 条后为真的测试。
6. 写活动计划睡眠目标和达标天数测试。
7. 写无计划、暂停、待重算和风险阻断时目标为空/不可执行测试。
8. 所有汇总只复用睡眠记录与当前计划，不复制计划计算公式。

## 任务 4：Today 接入真实睡眠状态

修改：

- `backend/src/main/java/com/lightbite/healthy/today/TodayDtos.java`
- `backend/src/main/java/com/lightbite/healthy/today/TodayService.java`
- `backend/src/test/java/com/lightbite/healthy/today/TodayServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/TodayIntegrationTests.java`

步骤：

1. 写无记录 `EMPTY`、有记录 `READY`、未建档 `PROFILE_INCOMPLETE` 测试。
2. 写夜间分钟、目标差值、质量、小睡分钟和趋势充分状态映射测试。
3. 写无计划、暂停、待重算和风险状态测试。
4. 写睡眠查询异常时仅 sleep 返回 `ERROR`，其他 Today 模块继续返回的测试。
5. Today 只调用睡眠服务只读汇总，不复制 SQL、时区或目标规则。

后端候选完成前运行：

```powershell
cd E:\Healthy-worktrees\sleep-backend\backend
.\mvnw.cmd test

cd E:\Healthy-worktrees\sleep-backend
.\scripts\check.ps1
git diff --check
```

## 任务 5：Flutter 模型、API 与控制器

新增：

- `mobile/lib/features/sleep/domain/sleep_data.dart`
- `mobile/lib/features/sleep/application/sleep_controller.dart`
- `mobile/test/features/sleep/sleep_data_test.dart`
- `mobile/test/features/sleep/sleep_controller_test.dart`
- `mobile/test/core/api/api_client_sleep_test.dart`

修改：

- `mobile/lib/core/api/api_client.dart`

步骤：

1. 写记录、质量、标签、日汇总、7 天统计和计划状态的解析测试。
2. 写日/周读取、新增、编辑和删除请求契约测试。
3. 写创建生成幂等键、失败重试复用同一键的测试。
4. 写按账户＋日期缓存隔离、刷新、日期切换和缓存标记测试。
5. 写旧请求不能覆盖新数据、页面销毁与账号切换丢弃迟到响应测试。
6. 写失败时保留完整表单草稿、编辑重试仍保持编辑语义的测试。
7. 复用现有 Riverpod 模式，不新增仓储接口或本地数据库。

## 任务 6：Flutter 睡眠页面与权限闭环

新增：

- `mobile/lib/features/sleep/presentation/sleep_page.dart`
- `mobile/lib/features/sleep/presentation/sleep_record_page.dart`
- `mobile/lib/features/sleep/presentation/sleep_reminder_sheet.dart`
- 对应 `mobile/test/features/sleep/` Widget 测试。

修改：

- `mobile/lib/app/app_shell.dart`
- `mobile/lib/features/today/domain/today_data.dart`
- `mobile/lib/features/today/presentation/today_page.dart`
- 对应 AppShell 和 Today 测试。

步骤：

1. 写 Today 睡眠卡进入管理页、“记录睡眠”直接进入记录页的测试；不新增底部导航。
2. 写游客进入登录、未建档进入建档、完成后恢复原操作测试。
3. 写日期导航、昨晚主卡、7 天摘要、简单时长条和记录列表测试。
4. 写夜间/小睡切换及 8 小时/30 分钟默认草稿测试。
5. 写系统日期与时间选择、自动时长和未来/边界中文提示测试。
6. 写五级质量、七个影响标签、备注折叠和 500 字限制测试。
7. 写编辑、中文删除确认、保存中防重复和失败保留表单测试。
8. 使用现有 6 px 主题和原生控件，不增加图表或 UI 依赖。

## 任务 7：Flutter 本地睡前提醒

新增：

- `mobile/lib/features/sleep/application/sleep_reminder_scheduler.dart`
- `mobile/test/features/sleep/sleep_reminder_scheduler_test.dart`

步骤：

1. 写纯函数测试：提醒时间、重复星期、当前时间、时区和下一次触发日期。
2. 写无重复星期拒绝、关闭提醒清空任务、设置变化重新安排测试。
3. 写按账号保存到 `shared_preferences`，账号之间互不污染测试。
4. 写通知 ID 只覆盖本账号睡眠提醒，不影响饮水提醒测试。
5. 只有用户开启时申请权限；拒绝不影响记录并显示系统设置入口。
6. 使用已有 `flutter_local_notifications` 非精确调度，不申请精确闹钟权限。
7. 应用启动/恢复和时区变化时按需重排；退出登录取消当前账号睡眠提醒。

Flutter 候选完成前运行：

```powershell
cd E:\Healthy-worktrees\sleep-flutter\mobile
dart format lib test
flutter analyze
flutter test
flutter build apk --debug

cd E:\Healthy-worktrees\sleep-flutter
.\scripts\check.ps1
git diff --check
```

## 任务 8：独立 QA 与最终集成

新增：

- `docs/qa/sleep-tracking-acceptance.md`

步骤：

1. 从相同主线提交创建 QA 工作树，先提交验收矩阵和基线结果。
2. 等待 `codex/sleep-backend` 与 `codex/sleep-flutter` 完成，不提前合并未完成改动。
3. 合并两个候选，修复真实契约或状态缺陷，不修改无关功能。
4. 独立复测迁移、时间区间、跨午夜、归档、重叠、幂等、用户隔离和 7 天统计。
5. 独立复测账户/日期缓存、迟到响应、权限闭环、提醒隔离和 Today 降级。
6. 运行后端全量、Flutter 全量、静态分析、格式、APK 和仓库检查。
7. 使用 H2 测试配置启动后端，在 Android API 36 模拟器安装最终 APK。
8. 触控验收夜间睡眠、小睡、质量、标签、备注、编辑、删除、历史补录和错误拦截。
9. 验收睡前提醒权限允许/拒绝、时间/星期、退出登录取消和饮水提醒不受影响。
10. 验证 720×1600、1.3 倍字体、键盘、安全区域和减少动画；结束后恢复设备设置。
11. 记录 Debug APK 路径、大小、SHA-256、环境遗留和能否合并结论。
12. 最终工作树必须干净，不推送 `main`。

## 任务 9：主线复核与推送

1. 主任务确认 QA 候选包含后端、Flutter、必要修复和验收报告。
2. 复核未混入健康平台同步、闹钟、复杂图表或任务管理。
3. 将 QA 候选无冲突合并到 `main`。
4. 在主线运行 `scripts/check.ps1` 与 `git diff --check`。
5. 确认 Git 邮箱为 `3040503900@qq.com`。
6. 推送私有 GitHub 并核对 `origin/main`。
7. 需要体验时在 8080 启动 H2 测试后端并安装最终 APK。

## 最终完成标准

- 用户可记录、编辑和删除夜间睡眠与小睡，时长由服务端自动计算。
- 跨午夜按醒来日期稳定归档，未来、边界、重叠和重复夜间记录正确拦截。
- 五级质量、固定标签和可选备注可用。
- 当天汇总与最近 7 天统计准确，无可执行计划时不虚构目标。
- Today 展示同一权威睡眠摘要，睡眠故障不影响其他模块。
- 一组设备本地睡前提醒可按时间与星期安排，权限拒绝不影响记录。
- 游客、未建档、幂等、用户隔离、缓存和竞态测试通过。
- 全部文案中文，6 px 圆角、窄屏、大字体、键盘和安全区域通过。
- 后端、Flutter、静态分析、APK、仓库检查和 Android 模拟器验收全部通过。
- 最终提交推送到私有 GitHub，主工作树干净。
