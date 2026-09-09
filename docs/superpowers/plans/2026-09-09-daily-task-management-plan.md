# 轻食记「每日工作与生活任务管理」实施计划

日期：2026-09-09

依据：[每日工作与生活任务管理设计规格](../specs/2026-09-09-daily-task-management-design.md)

## 实施原则

- 继续使用“健康饮食”项目内已有的后端、Flutter、QA 三个任务，不创建新对话。
- 计划确认并推送后，三个任务从同一个 `origin/main` 精确提交创建全新工作树，不复用睡眠阶段工作树。
- 后端沿用 `JdbcTemplate`、Flyway、认证主体、统一中文错误和 Today 单模块降级模式。
- Flutter 沿用 Dio、Riverpod、`shared_preferences`、现有会话权限闭环和本地通知依赖。
- 服务端是模板、实例、状态、统计和提醒设置的唯一权威；设备仅保存最近成功缓存并安排本地通知。
- 每一阶段先写会失败的最小测试，再写使其通过的最小实现；每个候选必须单独全量回归。
- 不新增 ORM、仓储接口层、工作流引擎、消息队列、本地数据库、图表库、日历依赖或通知依赖。
- 不建设月度/年度重复、复杂 RRULE、离线写入队列、服务器推送、第三方日历同步或 AI 自动排程。
- 不修改现有营养、饮水、运动、睡眠计算公式，只调用它们的权威只读汇总。
- 如实现需要改变已确认规格，停止开发并回到规格确认，不由任一任务自行扩展。

## 三个既有任务与分支

### 后端任务

继续使用现有后端任务，改名为“每日任务管理后端开发”。创建：

- 工作树：`E:\Healthy-worktrees\tasks-backend`
- 分支：`codex/tasks-backend`

负责 V9/V10、模板与实例、重复生成、状态操作、健康联动、7 天统计、提醒设置、通知事件和 Today 接入。

### Flutter 任务

继续使用现有 Flutter 任务，改名为“每日任务管理 Flutter 开发”。创建：

- 工作树：`E:\Healthy-worktrees\tasks-flutter`
- 分支：`codex/tasks-flutter`

负责数据模型、API、控制器、缓存、每日任务页面、任务表单、统计、勿扰、本地通知、权限闭环和 Today 入口。

### QA/集成任务

继续使用现有 QA 任务，改名为“每日任务管理 QA 集成”。创建：

- 工作树：`E:\Healthy-worktrees\tasks-qa`
- 分支：`codex/tasks-qa`

先独立建立验收矩阵和基线，等待两个候选完成后合并、处理真实契约问题、完成 API 36 模拟器触控验收并产出唯一最终候选。

三个任务均不得直接推送 `main`。后端和 Flutter 只提交各自候选；QA 合并候选；主任务最终复核、合并并推送私有 GitHub。

## 执行顺序与交接

1. 主任务推送已确认的规格与计划，记录精确基线 SHA。
2. QA 先创建工作树、提交独立验收矩阵并运行基线检查。
3. 后端与 Flutter 从相同基线并行开发；Flutter 使用已确认 API 契约和测试假数据，不等待后端进程。
4. 后端先提交候选 SHA；Flutter 随后提交候选 SHA，两者都保持工作树干净。
5. QA 合并两个候选，运行自动化、启动后端、安装 APK 并完成设备触控验收。
6. QA 只修复集成中证实的最小问题，提交唯一候选和验收报告。
7. 主任务复核 QA 候选、在 `main` 运行仓库检查、推送远程并核对一致性。

## 任务 1：QA 建立验收矩阵与共同基线

所有者：QA/集成任务。

新增：

- `docs/qa/daily-task-management-acceptance.md`

步骤：

1. 从计划推送后的精确 `origin/main` 创建 QA 工作树，记录基线 SHA、Java、Flutter、Android SDK 和模拟器版本。
2. 把规格第 18 节拆成可勾选矩阵：迁移、权限、重复、实例生成、状态、编辑范围、删除范围、健康联动、统计、通知、Today、缓存和可访问性。
3. 为每项标明验证层级：数据库、服务、HTTP、Dart 单元、Widget、Android 触控。
4. 在未合并任何候选前运行后端全量、Flutter 全量、静态分析和仓库检查，记录真实测试数量。
5. 检查 Android API 36 模拟器是否在线；不在线时记录环境阻断，但不阻止并行开发。
6. 提交仅包含验收文档的 QA 基线提交，并把 SHA 告知后端、Flutter 和主任务。

基线命令：

```powershell
cd E:\Healthy-worktrees\tasks-qa\backend
.\mvnw.cmd test

cd E:\Healthy-worktrees\tasks-qa\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

cd E:\Healthy-worktrees\tasks-qa
.\scripts\check.ps1
git diff --check
git status --short --branch
```

## 任务 2：V9 核心任务数据库迁移

所有者：后端任务。

新增：

- `backend/src/main/resources/db/migration/V9__create_daily_tasks.sql`
- `backend/src/test/java/com/lightbite/healthy/TaskMigrationTests.java`

步骤：

1. 先写 V8→V9 升级测试，确认账号、档案、计划、饮食、饮水、运动和睡眠数据不变。
2. 写空库迁移测试，确认 `task_templates`、`task_instances`、外键、唯一约束和查询索引存在。
3. 模板表保存用户、来源、计划/版本/任务代码、标题、备注、分类、优先级、全天/时间、重复规则、星期位图、提醒提前量、健康联动、生效/停用日期、用户覆盖和乐观锁版本。
4. 实例表保存原日期/当前日期、原截止/当前截止 UTC、时区、状态、完成来源、完成/跳过/延期信息、实例覆盖、软删除和乐观锁版本。
5. 为 `(template_id, original_local_date)` 建立唯一约束；延期只改变当前日期，不破坏唯一性。
6. 为计划模板建立用户、计划和稳定任务代码的唯一约束，防止同一版本健康模板重复生成。
7. 数据库约束覆盖来源、分类、优先级、重复类型、状态、完成来源、标题/备注长度、提醒枚举和全天任务时间一致性。
8. 索引只覆盖实际查询：用户＋当前日期＋删除状态、用户＋状态＋当前截止时间、用户＋模板生效区间。
9. SQL 同时兼容 MySQL 8.4 和 H2 MySQL 模式，不引入数据库特有调度功能。

阶段验证：

```powershell
cd E:\Healthy-worktrees\tasks-backend\backend
.\mvnw.cmd test -Dtest=TaskMigrationTests
```

## 任务 3：V10 勿扰设置与通知事件迁移

所有者：后端任务。

新增：

- `backend/src/main/resources/db/migration/V10__create_task_notification_settings.sql`

继续修改：

- `backend/src/test/java/com/lightbite/healthy/TaskMigrationTests.java`

步骤：

1. 写 V9→V10 升级测试，确认任务模板和实例完整保留。
2. 创建 `task_settings`，每个用户一行，默认开启勿扰，默认 22:30–07:00，并保存乐观锁版本。
3. 创建 `task_notification_events`，只允许 `SCHEDULED`、`CANCELLED`、`OPENED`。
4. 使用 `(user_id, idempotency_key)` 唯一约束确保批量重试稳定；设备只保存不可逆 `device_key_hash`。
5. 建立按用户、实例和发生时间审计所需索引，不建立通知送达字段。
6. 写从 V8 直接升级到 V10 的完整迁移测试。

阶段验证：

```powershell
cd E:\Healthy-worktrees\tasks-backend\backend
.\mvnw.cmd test -Dtest=TaskMigrationTests
```

## 任务 4：重复规则、时区与实例生成策略

所有者：后端任务。

新增：

- `backend/src/main/java/com/lightbite/healthy/tasks/package-info.java`
- `backend/src/main/java/com/lightbite/healthy/tasks/TaskSchedulePolicy.java`
- `backend/src/test/java/com/lightbite/healthy/tasks/TaskSchedulePolicyTests.java`

步骤：

1. 写 `NONE`、`DAILY`、`WEEKDAYS`、`WEEKENDS`、`WEEKLY_DAYS` 的命中日期测试。
2. 写星期位图为空、范围非法和一次性任务缺日期的中文校验测试。
3. 写今天与未来 7 天生成、重复读取不重复、历史查询不补造、未来超过 7 天拒绝测试。
4. 写有时间任务从本地日期/时间转换 UTC 的测试，覆盖 `Asia/Shanghai` 和固定偏移。
5. 写夏令时不存在时间和重复时间的明确字段错误测试，不静默选择偏移。
6. 写延期到次日后仍保留原计划日期和原截止时间的策略测试。
7. 实现无状态纯策略类，只使用 Java 时间库；不引入 RRULE 或日期依赖。

阶段验证：

```powershell
cd E:\Healthy-worktrees\tasks-backend\backend
.\mvnw.cmd test -Dtest=TaskSchedulePolicyTests
```

## 任务 5：后端模板、实例读取与用户任务创建

所有者：后端任务。

新增：

- `backend/src/main/java/com/lightbite/healthy/tasks/TaskDtos.java`
- `backend/src/main/java/com/lightbite/healthy/tasks/TaskService.java`
- `backend/src/main/java/com/lightbite/healthy/tasks/TaskController.java`
- `backend/src/test/java/com/lightbite/healthy/tasks/TaskServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/TaskIntegrationTests.java`

步骤：

1. 写未登录全部任务接口返回 401、用户身份只取认证主体的测试。
2. 写用户任务标题 1–80、备注 500、分类、优先级、全天/时间、提醒和重复规则边界测试。
3. 写 `POST /api/v1/tasks` 必须携带 `Idempotency-Key`、相同键重试返回同一资源、并发不重复和跨用户隔离测试。
4. 写模板创建后只生成今天至未来 7 天符合规则实例的测试。
5. 写 `GET /api/v1/tasks/days/{date}?timezone=` 的时间线、全天、折叠汇总、逾期动态计算和软删除过滤测试。
6. 写历史缺失实例不补造、今日/未来读取确保实例存在、同一模板同日不重复测试。
7. 写不存在、已删除和其他用户资源使用同一安全错误，不泄露存在性的测试。
8. 控制器统一使用现有错误结构；客户端不得提交 `userId`、完成率或健康条件结果。
9. 查询和事务直接复用 `JdbcTemplate` 与数据库约束，不增加一层单实现仓储接口。

API：

- `GET /api/v1/tasks/days/{date}?timezone=Asia/Shanghai`
- `POST /api/v1/tasks`

阶段验证：

```powershell
cd E:\Healthy-worktrees\tasks-backend\backend
.\mvnw.cmd test -Dtest=TaskSchedulePolicyTests,TaskServiceTests,TaskIntegrationTests
```

## 任务 6：状态、延期、编辑范围和删除范围

所有者：后端任务。

继续修改任务模块与测试。

步骤：

1. 写完成、重复完成、撤销完成、跳过、重复跳过和撤销跳过测试。
2. 写手动完成保存 `USER`、自动完成保存 `AUTO_HEALTH_DATA`、撤销后状态字段清理测试。
3. 写每个状态操作都要求 `Idempotency-Key`，同键重试结果稳定、不同账号互不影响测试。
4. 写“稍后 30 分钟”“明天”和自选时间延期测试；延期保持 `PENDING` 并累计次数。
5. 写延期只影响当前实例、延期跨日归入新日期、原计划日期用于统计测试。
6. 写 `PUT /tasks/instances/{id}` 只改当前实例覆盖、不影响模板和以后实例测试。
7. 写 `PUT /tasks/templates/{id}` 从当天起更新模板和未执行实例，历史完成/跳过/延期实例不变测试。
8. 写模板版本冲突返回中文 `409`，防止两台设备静默覆盖测试。
9. 写仅删除当前实例、停止当天及以后、历史执行记录保留和计划模板禁用覆盖测试。
10. 使用数据库事务和版本列完成并发保护，不新增事件溯源或通用工作流状态机。

API：

- `PUT /api/v1/tasks/instances/{id}`
- `PUT /api/v1/tasks/templates/{id}`
- `POST /api/v1/tasks/instances/{id}/complete`
- `POST /api/v1/tasks/instances/{id}/reopen`
- `POST /api/v1/tasks/instances/{id}/skip`
- `POST /api/v1/tasks/instances/{id}/postpone`
- `DELETE /api/v1/tasks/instances/{id}`
- `DELETE /api/v1/tasks/templates/{id}?effectiveDate=YYYY-MM-DD`

## 任务 7：健康计划模板和真实记录联动

所有者：后端任务。

新增：

- `backend/src/main/java/com/lightbite/healthy/tasks/TaskHealthLinkService.java`
- `backend/src/test/java/com/lightbite/healthy/tasks/TaskHealthLinkServiceTests.java`

必要时最小修改：

- `backend/src/main/java/com/lightbite/healthy/plan/PlanService.java`
- 各健康模块现有服务中缺少的只读汇总方法及对应测试。

步骤：

1. 写活动计划生成早餐 08:00、午餐 12:00、晚餐 18:00、饮水 20:00、睡眠记录 08:00 的测试。
2. 写运动每周 `n` 天按 `floor(i × 7 ÷ n)` 分布，周分钟整除并把余数分配给较早任务的测试。
3. 写用户、计划版本、稳定任务代码防止模板重复的测试。
4. 写未建档、无计划、暂停、待重算和风险阻断时不生成健康实例的测试。
5. 写计划恢复只生成当天与未来、不补暂停期历史测试。
6. 写饮食记录按餐次、饮水达到目标、运动分钟达到单次目标、夜间睡眠按醒来日期自动完成测试。
7. 写自动完成的原始记录被删除或降到阈值以下后恢复待完成测试。
8. 写用户手动完成、跳过或已延期时自动联动不覆盖；手动完成不因健康数据删除而撤销测试。
9. 写长期用户覆盖在计划更新后保留、`hasPlanUpdate=true`、明确采用默认后更新的测试。
10. 写“删除今天及以后”的计划任务不会在下一次读取时重建测试。
11. 只通过各健康模块公开只读汇总判断条件；不要复制 SQL 或目标计算公式到任务模块。

阶段验证：

```powershell
cd E:\Healthy-worktrees\tasks-backend\backend
.\mvnw.cmd test -Dtest=TaskHealthLinkServiceTests,TaskServiceTests,TaskIntegrationTests
```

## 任务 8：设置、通知事件和最近 7 天统计

所有者：后端任务。

继续修改：

- `backend/src/main/java/com/lightbite/healthy/tasks/TaskDtos.java`
- `backend/src/main/java/com/lightbite/healthy/tasks/TaskService.java`
- `backend/src/main/java/com/lightbite/healthy/tasks/TaskController.java`
- 对应服务与集成测试。

步骤：

1. 写首次读取返回勿扰开启、22:30–07:00 默认值的测试。
2. 写关闭勿扰、跨午夜范围、非法时间和版本冲突测试。
3. 写批量上报 `SCHEDULED`、`CANCELLED`、`OPENED` 和相同幂等键重试测试。
4. 写拒绝其他事件类型、原始设备标识和其他用户实例测试。
5. 写通知查询只返回未来最多 7 天、有具体时间且开启提醒的待完成实例测试。
6. 写提醒提前 0/5/15/30/60 分钟、落入勿扰时段直接跳过、不补发测试。
7. 写所选日期及之前 6 天边界、应出现/完成/跳过/延期/逾期数量测试。
8. 写完成率分母排除已删除实例、分母为零返回空、五类分类明细测试。
9. 写延期无论多次只按原计划日期计一次测试。
10. 写自动完成与手动完成都计入完成数且完成来源可追溯测试。

API：

- `GET /api/v1/tasks/weeks/{date}?timezone=Asia/Shanghai`
- `GET /api/v1/tasks/notifications?from=&to=&timezone=Asia/Shanghai`
- `GET /api/v1/tasks/settings`
- `PUT /api/v1/tasks/settings`
- `POST /api/v1/tasks/notification-events`
- `POST /api/v1/tasks/plan-updates/adopt`

## 任务 9：Today 接入真实任务摘要

所有者：后端任务。

修改：

- `backend/src/main/java/com/lightbite/healthy/today/TodayDtos.java`
- `backend/src/main/java/com/lightbite/healthy/today/TodayService.java`
- `backend/src/test/java/com/lightbite/healthy/today/TodayServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/TodayIntegrationTests.java`

步骤：

1. 把 tasks 从通用 `COMING_SOON` 改为专用任务摘要 DTO。
2. 写 `READY`、`EMPTY`、`ERROR`，以及总数、完成、待完成、逾期和下一任务映射测试。
3. 写未完成档案但存在自建任务时仍返回真实摘要测试，不把整个模块标成 `PROFILE_INCOMPLETE`。
4. 写无健康计划时自建任务仍可用，健康入口单独返回建档/计划引导测试。
5. 写下一任务只选可执行待完成项，有时间按当前截止时间优先、全天任务随后测试。
6. 写任务模块异常只令 tasks 为 `ERROR`，营养、饮水、运动、睡眠和计划继续返回测试。
7. Today 只调用任务服务的只读摘要，不复制任务 SQL、生成或健康联动规则。

后端候选完成前运行：

```powershell
cd E:\Healthy-worktrees\tasks-backend\backend
.\mvnw.cmd test

cd E:\Healthy-worktrees\tasks-backend
.\scripts\check.ps1
git diff --check
git status --short --branch
```

后端候选提交必须包含 V9/V10、全部任务模块、Today 接入和测试；不得包含 Flutter 或 QA 文件。

## 任务 10：Flutter 任务模型与 API 契约

所有者：Flutter 任务。

新增：

- `mobile/lib/features/tasks/domain/task_data.dart`
- `mobile/test/features/tasks/task_data_test.dart`
- `mobile/test/core/api/api_client_tasks_test.dart`

修改：

- `mobile/lib/core/api/api_client.dart`

步骤：

1. 写模板、实例、每日响应、7 天统计、设置和通知安排的完整/可选字段解析测试。
2. 写未知服务端枚举安全降级测试；未知分类显示“其他”，未知状态不可误判为完成。
3. 写每日、周统计、通知、创建、编辑、状态、删除、设置、事件和采用计划默认 API 契约测试。
4. 写日期固定为本地 `YYYY-MM-DD`、时区使用设备 IANA 标识测试。
5. 写所有创建和状态操作携带 `Idempotency-Key` 测试。
6. 写统一中文错误继续复用 `ApiClient.errorMessage` 测试，不建设第二套错误体系。
7. 实现最小不可变数据对象和现有 `ApiClient` 方法，不增加代码生成依赖。

阶段验证：

```powershell
cd E:\Healthy-worktrees\tasks-flutter\mobile
flutter test test/features/tasks/task_data_test.dart test/core/api/api_client_tasks_test.dart
```

## 任务 11：Flutter 控制器、缓存和并发保护

所有者：Flutter 任务。

新增：

- `mobile/lib/features/tasks/application/task_controller.dart`
- `mobile/test/features/tasks/task_controller_test.dart`

步骤：

1. 写按账号＋本地日期读取与缓存隔离测试，退出或切换账号不得显示旧账号任务。
2. 写日期切换、分类筛选、刷新和跨日恢复前台重新加载测试。
3. 写首次失败整页错误、有缓存失败保留数据并标记“数据可能不是最新”测试。
4. 写页面销毁、账号切换、日期切换后丢弃迟到响应测试。
5. 写创建/编辑表单失败保留草稿、相同操作重试复用幂等键、成功后清除键测试。
6. 写完成、跳过、撤销和延期乐观更新，失败准确回滚并提供重试测试。
7. 写同一实例操作期间防重复点击和并发刷新不覆盖新状态测试。
8. 最近成功缓存复用 `shared_preferences`，只存展示所需 JSON；不做离线写入队列。
9. 复用 Riverpod 当前控制器模式，不新增 repository/use-case 接口层。

阶段验证：

```powershell
cd E:\Healthy-worktrees\tasks-flutter\mobile
flutter test test/features/tasks/task_controller_test.dart
```

## 任务 12：Flutter 本地任务通知调度

所有者：Flutter 任务。

新增：

- `mobile/lib/features/tasks/application/task_notification_scheduler.dart`
- `mobile/test/features/tasks/task_notification_scheduler_test.dart`

步骤：

1. 写提前 0/5/15/30/60 分钟换算和未来 7 天过滤的纯函数测试。
2. 写跨午夜勿扰判断，落入勿扰直接不安排、勿扰结束不补发测试。
3. 写无时间全天任务不安排、完成/跳过/删除后取消、延期/编辑后重排测试。
4. 写任务通知 ID 使用独立区间，取消任务通知不影响饮水或睡眠通知测试。
5. 写通知负载只含任务实例标识，点击后产生 `OPENED` 事件并导航到对应日期测试。
6. 写账号切换/退出只取消对应账号任务通知，应用启动、恢复和时区变化按需重排测试。
7. 写首次启用时才请求权限、拒绝权限不影响任务保存并显示系统设置引导测试。
8. 调度成功/取消后批量上报可验证事件；上报失败不影响本地任务使用。
9. 复用现有 `flutter_local_notifications`、`timezone` 和 `flutter_timezone`，使用非精确通知，不新增依赖或精确闹钟权限。

阶段验证：

```powershell
cd E:\Healthy-worktrees\tasks-flutter\mobile
flutter test test/features/tasks/task_notification_scheduler_test.dart
```

## 任务 13：每日任务页、任务表单和周概览

所有者：Flutter 任务。

新增：

- `mobile/lib/features/tasks/presentation/tasks_page.dart`
- `mobile/lib/features/tasks/presentation/task_editor_page.dart`
- `mobile/lib/features/tasks/presentation/task_week_overview_sheet.dart`
- `mobile/lib/features/tasks/presentation/task_settings_sheet.dart`
- 对应 `mobile/test/features/tasks/` Widget 测试。

步骤：

1. 写日期前后切换、返回今天、完成进度、下一任务、时间线和“今日待办”测试。
2. 写全部/健康/工作/生活/学习/其他筛选，以及已完成/已跳过默认折叠测试。
3. 写任务行完成、撤销、跳过、延期、更多菜单和来源/自动完成依据测试。
4. 写新增表单标题、备注、分类、优先级、全天/时间、重复和提醒校验测试。
5. 使用系统日期/时间选择器；星期使用中文多选；能选择的内容不要求键盘输入。
6. 写重复任务编辑弹出“仅修改今天”“之后都按此安排”测试。
7. 写删除弹出“仅删除今天”“删除今天及以后”中文确认测试。
8. 写延期三个入口：“稍后 30 分钟”“明天”“自选时间”。
9. 写最近 7 天真实数量、完成率空值、分类进度和无主观评价测试。
10. 写勿扰默认值、跨午夜选择、提醒权限拒绝和系统设置入口测试。
11. 网络失败保留表单与缓存；保存中禁用重复提交；错误提示使用中文。
12. 沿用深绿/米白主题，新增卡片、输入框、按钮、菜单和弹窗圆角统一 6 px。
13. 支持 720×1600、1.3 倍字体、读屏语义、底部安全区域、键盘和减少动画。
14. 使用 Flutter 原生控件和简单进度条，不新增日历、时间线或图表组件库。

## 任务 14：Today 入口与三种用户状态权限闭环

所有者：Flutter 任务。

修改：

- `mobile/lib/features/today/domain/today_data.dart`
- `mobile/lib/features/today/presentation/today_page.dart`
- `mobile/lib/features/today/application/today_controller.dart`
- `mobile/lib/app/app_shell.dart`
- `mobile/lib/app/router.dart`
- 对应 Today、AppShell、路由和权限测试。

步骤：

1. 写 Today 任务卡展示完成数、待完成数、逾期数和下一任务测试。
2. 写点击摘要进入每日任务页、点击下一任务定位到对应日期/实例测试。
3. 不新增底部导航项，保持现有导航结构；每日任务由 Today 摘要进入。
4. 写游客可看示例，点击创建/状态操作进入登录，并在登录后恢复原意图测试。
5. 写已登录未建档用户可以创建和操作个人任务，健康任务入口才引导建档测试。
6. 写已建档无活动计划用户可用个人任务，健康任务入口引导生成计划测试。
7. 写已建档有活动计划用户看到健康和个人任务测试。
8. 写 tasks `ERROR` 不影响 Today 其他卡片，任务页可独立重试测试。
9. 写通知点击冷启动/前台均能打开正确任务，资源不存在时回到对应日期并显示中文提示测试。

Flutter 候选完成前运行：

```powershell
cd E:\Healthy-worktrees\tasks-flutter\mobile
dart format lib test
flutter analyze
flutter test
flutter build apk --debug

cd E:\Healthy-worktrees\tasks-flutter
.\scripts\check.ps1
git diff --check
git status --short --branch
```

Flutter 候选不得修改后端业务实现或 QA 结论，只可加入契约测试所需的客户端代码和测试。

## 任务 15：QA 合并候选与自动化回归

所有者：QA/集成任务。

步骤：

1. 确认后端和 Flutter 候选均从共同基线开始、工作树干净、提交范围正确。
2. 先合并后端候选，再合并 Flutter 候选；保留两个独立合并提交以便追溯。
3. 运行 V8→V10、V9→V10、空库迁移和 MySQL 8.4 可用时的真实数据库迁移。
4. 独立补测遗漏的高风险边界：并发生成、版本冲突、跨用户、DST、历史不回填、延期跨日、计划更新覆盖。
5. 独立补测四类健康数据删除后的自动状态回滚和用户显式状态优先级。
6. 独立补测 Today 单模块降级、账号/日期缓存隔离、页面销毁迟到响应和幂等重试。
7. 运行后端全量、Flutter 全量、静态分析、格式检查、Debug APK 和仓库检查。
8. 只修复测试证实的根因；修复必须补回归测试，不做无关重构。

自动化命令：

```powershell
cd E:\Healthy-worktrees\tasks-qa\backend
.\mvnw.cmd test

cd E:\Healthy-worktrees\tasks-qa\mobile
dart format lib test
flutter analyze
flutter test
flutter build apk --debug

cd E:\Healthy-worktrees\tasks-qa
.\scripts\check.ps1
git diff --check
git status --short --branch
```

## 任务 16：Android API 36 模拟器端到端验收

所有者：QA/集成任务。

前置：使用 QA 工作树启动 H2 测试后端，确保模拟器通过 `10.0.2.2:8080` 访问，不依赖 Docker。

步骤：

1. 安装 QA 最终 Debug APK，清理旧 App 数据，验证首次游客浏览和登录恢复原操作。
2. 验证已登录未建档可创建工作/生活任务，但健康任务提示补档。
3. 验证完成档案及活动计划后出现早餐、午餐、晚餐、饮水、运动和睡眠任务。
4. 触控验证一次性、每天、工作日、周末、每周指定星期。
5. 验证有时间时间线、无时间“今日待办”、五类筛选和三级优先级。
6. 验证完成/撤销、跳过/撤销、稍后、明天、自选时间和动态逾期。
7. 验证仅改今天/之后都按此安排、仅删今天/删除今天及以后。
8. 分别新增/删除饮食、饮水、运动、睡眠记录，核对健康任务自动完成和回滚。
9. 验证用户手动完成、跳过或延期后健康联动不覆盖。
10. 验证最近 7 天统计、延期只计一次、分母为空时不显示虚假百分比。
11. 验证提醒提前量、勿扰、权限允许/拒绝、编辑重排、完成取消、点击跳转和饮水/睡眠通知不受影响。
12. 断开后端验证最近成功缓存和失败回滚，再恢复后端验证重试。
13. 验证 720×1600、1.3 倍字体、键盘、读屏语义、底部安全区域和减少动画。
14. 恢复模拟器分辨率、字体、网络和动画设置，释放 8080 端口。
15. 在验收报告记录测试数量、触控步骤、截图/日志、环境遗留、APK 路径、大小和 SHA-256。
16. 确认 QA 工作树干净，给出明确“建议合并”或“阻止合并”结论，不推送 `main`。

## 任务 17：主线复核、合并与推送

所有者：主任务。

步骤：

1. 核对 QA 最终候选包含后端、Flutter、最小集成修复和验收报告。
2. 核对未混入复杂 RRULE、离线队列、工作流引擎、消息队列、服务器推送、第三方日历或新依赖。
3. 检查提交历史、`git diff --check`、构建产物、`.env`、密钥和凭据模式。
4. 将 QA 候选无冲突合并或快进到 `main`；若主线已前进，先在 QA 工作树重新集成验证。
5. 在 `main` 运行 `scripts/check.ps1` 和必要全量回归。
6. 确认 Git 提交邮箱为 `3040503900@qq.com`。
7. 推送私有远程并确认 `main` 与 `origin/main` 指向同一提交。
8. 向用户报告完成范围、测试数量、APK 路径/哈希和任何真实遗留项。

## 最终完成标准

- 用户可创建、浏览、编辑、完成、撤销、跳过、延期和删除个人任务。
- 每天、工作日、周末和每周指定星期按用户时区稳定生成，历史不会被补造。
- 健康计划稳定生成饮食、饮水、运动和睡眠任务，不重复、不丢失用户长期覆盖。
- 真实健康记录可自动完成任务；删除记录可回滚自动状态；用户显式状态优先。
- 最近 7 天数量、完成率、分类和延期统计准确，不生成主观评价或虚假百分比。
- 每项任务提醒和全局勿扰使用设备本地非精确通知，且与饮水、睡眠提醒隔离。
- Today 使用同一服务端任务摘要，任务故障不影响其他模块。
- 游客、已登录未建档、已登录已建档三种状态权限和恢复原操作闭环正确。
- 缓存按账号/日期隔离，乐观更新可回滚，迟到响应不污染当前页面。
- 所有用户文案中文，新增控件圆角 6 px，窄屏、大字体、键盘、安全区域和减少动画通过。
- V8→V10 升级、后端全量、Flutter 全量、静态分析、APK、仓库检查和 API 36 模拟器验收通过。
- 最终提交推送至私有 GitHub，`main` 与 `origin/main` 同步，主工作树干净。
