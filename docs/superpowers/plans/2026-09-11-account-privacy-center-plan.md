# 轻食记「账户与隐私中心」实施计划

日期：2026-09-11

依据：[账户与隐私中心设计规格](../specs/2026-09-11-account-privacy-center-design.md)

## 实施原则

- 只扩展现有 Spring Boot、`JdbcTemplate`、Flyway、PDFBox、Flutter Material、Dio、GoRouter 和会话控制器，不重建账户体系。
- 每项非平凡业务逻辑先写最小失败测试，再补最小实现；安全、删除、注销和授权边界不能只依赖客户端测试。
- 所有用户可见页面、按钮、状态和错误使用中文；内部枚举与机器错误码可以使用英文。
- 主要控件圆角统一为 6 px；危险操作使用克制的红色文字或描边，并配合明确文本。
- 不新增 ORM、消息队列、工作流引擎、事件总线、通用策略 DSL、Flutter 状态管理、PDF 库或 UI 组件库。
- 异步导出与大批量删除使用应用进程内执行器和数据库任务状态；重启恢复仅把无法安全继续的任务标记失败。
- 数据权利删除必须以服务端用户隔离、来源追踪和数据库事务为准，不接受客户端提交记录 ID 列表作为删除权威。
- 账户注销、授权撤回、换绑和设备撤销必须在服务端立即影响会话或权限，不能等待 Flutter 刷新后才生效。
- AI 食物图片识别不进入任何任务；如实现需要改变已确认规则，停止开发并回到规格确认。

## 执行阶段

1. 建立 QA 验收矩阵和未改代码基线。
2. 完成 V12 数据结构与迁移测试。
3. 完成验证码用途、账户状态和受限会话基础。
4. 完成设备、安全事件和账户摘要后端。
5. 完成健康档案分区编辑与计划重算闭环。
6. 完成隐私版本、同意、撤回和重新同意。
7. 完成手机号换绑与人工申诉。
8. 完成加密 PDF 数据导出。
9. 完成健康数据删除与来源关联。
10. 完成注销、恢复和永久清理。
11. 完成 Flutter 领域模型、API 和会话路由。
12. 完成 Flutter 账户、档案、安全和隐私页面。
13. 完成 Flutter 数据权利与注销页面。
14. 完成全量集成、真机/模拟器和隐私验收。

后端基础完成后可以按页面所需接口逐段接入 Flutter，但每个阶段必须保持仓库可编译、测试可运行。

## 任务 1：QA 验收矩阵与共同基线

新增：

- `docs/qa/account-privacy-center-acceptance.md`

步骤：

1. 将设计规格拆成数据库迁移、账户状态、设备会话、档案编辑、隐私版本、授权撤回、换绑申诉、导出、删除、注销、中文化和无障碍矩阵。
2. 每项标注验证层级：迁移、纯单元、服务、HTTP、Dart、Widget、Android/iOS 手工验收和 MySQL 发布门禁。
3. 在改代码前运行后端、Flutter、仓库检查和 Debug APK 构建，记录真实测试数量、工具版本、APK 路径与哈希。
4. 准备两个用户、两个设备、跨周期健康记录、多个计划版本和报告来源关系的验收夹具说明。
5. 明确日志扫描词：验证码、PDF 密码、Bearer Token、Refresh Token、完整手机号和完整健康档案。

基线命令：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test

cd E:\Healthy\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug

cd E:\Healthy
.\scripts\check.ps1
git diff --check
git status --short --branch
```

阶段提交：

```text
test: 建立账户与隐私中心验收基线
```

## 任务 2：V12 账户与隐私数据迁移

新增：

- `backend/src/main/resources/db/migration/V12__create_account_privacy_center.sql`
- `backend/src/test/java/com/lightbite/healthy/AccountPrivacyMigrationTests.java`

步骤：

1. 先写 V11→V12 升级测试，确认现有用户、设备、档案、计划、记录和报告不丢失。
2. 写空库迁移测试，确认新增表、索引、唯一约束、外键和状态默认值存在。
3. 扩展 `user_devices`，增加系统字段；不保存客户端可伪造的“当前设备”布尔值。
4. 建立隐私文件版本表，保存文件类型、版本、生效时间、变更摘要、中文正文和实质变化标记，并约束文件类型与版本唯一。
5. 建立追加式同意事件表，保存用户、文件类型、版本、动作和时间；把现有 `consent_records` 和 `health_permissions` 数据迁移为可读取的新结构，不丢失既有同意事实。
6. 建立数据导出任务、健康数据删除任务、安全事件和手机号换绑申诉表。
7. 扩展账户注销申请，保存计划完成时间、恢复时间和最终状态。
8. 为计划版本增加可空的来源测量标识；历史版本无法可靠反推来源时保持空值，不伪造关联。
9. 为每个真实查询增加最少索引：用户＋状态、用户＋时间、文件类型＋版本、任务过期时间。
10. H2 MySQL 模式通过；MySQL 8.4 实迁移列为发布门禁。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=AccountPrivacyMigrationTests
```

阶段提交：

```text
feat: 增加账户与隐私中心数据结构
```

## 任务 3：验证码用途、账户状态与受限会话

修改：

- `backend/src/main/java/com/lightbite/healthy/auth/AuthDtos.java`
- `backend/src/main/java/com/lightbite/healthy/auth/AuthService.java`
- `backend/src/main/java/com/lightbite/healthy/auth/BearerTokenFilter.java`
- `backend/src/main/java/com/lightbite/healthy/auth/AuthController.java`
- `backend/src/test/java/com/lightbite/healthy/AuthProfileIntegrationTests.java`

新增：

- `backend/src/test/java/com/lightbite/healthy/auth/AuthServiceTests.java`

步骤：

1. 先写测试覆盖验证码按用途隔离、5 分钟有效、一次使用、失败次数限制和跨用途拒绝。
2. 将允许的验证码用途固定为登录、数据导出、健康数据删除、旧手机号、新手机号、退出其他设备、账户注销和账户恢复；拒绝客户端传入任意用途。
3. 提取最小的“校验并核销验证码”服务方法，供敏感操作在事务内复用，不创建单实现接口。
4. 扩展会话身份，携带当前 `deviceId` 和会话类型；普通会话与注销恢复受限会话必须由服务端签发并区分。
5. `ACTIVE` 用户继续获得普通会话；`DELETION_PENDING` 用户验证成功后只获得受限会话；其他状态拒绝登录。
6. Bearer 过滤器只允许受限会话访问注销状态、恢复和退出接口，其他资源统一返回“账户正在注销处理中”。
7. 保持访问令牌 15 分钟、刷新令牌 30 天等现有规则不变，除非注销或安全操作主动撤销。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=AuthServiceTests,AuthProfileIntegrationTests
```

阶段提交：

```text
feat: 增加敏感操作验证与受限会话
```

## 任务 4：账户摘要、设备管理和安全事件

修改：

- `backend/src/main/java/com/lightbite/healthy/account/AccountController.java`
- `backend/src/main/java/com/lightbite/healthy/auth/AuthService.java`

新增：

- `backend/src/main/java/com/lightbite/healthy/account/AccountDtos.java`
- `backend/src/main/java/com/lightbite/healthy/account/AccountService.java`
- `backend/src/main/java/com/lightbite/healthy/account/SecurityEventService.java`
- `backend/src/test/java/com/lightbite/healthy/account/AccountServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/AccountSecurityIntegrationTests.java`

步骤：

1. 先写测试覆盖账户摘要脱敏、当前设备判定、单设备撤销、退出其他设备和跨用户设备拒绝。
2. 账户摘要只返回展示所需的昵称、脱敏手机号、账户状态、建档和授权状态，不返回用户内部 ID。
3. 设备列表从认证上下文的 `deviceId` 推导当前设备，返回设备名、系统、最近活跃时间和创建时间。
4. 单设备移除明确拒绝当前设备；成功后复用现有令牌撤销逻辑并写安全事件。
5. 退出其他设备验证短信后，一次性撤销除当前设备外的设备、访问令牌和刷新令牌。
6. 新设备创建时写登录安全事件并调用现有短信发送边界；测试环境使用可验证的假发送器，不接真实短信网络。
7. 安全事件列表按当前用户和时间倒序返回中文展示类型、设备、结果和时间，不返回敏感负载。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=AccountServiceTests,AccountSecurityIntegrationTests
```

阶段提交：

```text
feat: 完成账户设备与安全记录后端
```

## 任务 5：六分区健康档案与计划重算

修改：

- `backend/src/main/java/com/lightbite/healthy/profile/ProfileDtos.java`
- `backend/src/main/java/com/lightbite/healthy/profile/ProfileService.java`
- `backend/src/main/java/com/lightbite/healthy/profile/ProfileController.java`
- `backend/src/main/java/com/lightbite/healthy/plan/PlanService.java`
- `backend/src/test/java/com/lightbite/healthy/plan/PlanPolicyTests.java`
- `backend/src/test/java/com/lightbite/healthy/PlanIntegrationTests.java`

新增：

- `backend/src/test/java/com/lightbite/healthy/profile/ProfileSectionServiceTests.java`

步骤：

1. 先写六分区读取与保存测试，覆盖缺失、非法枚举、边界数值、跨用户和未完成档案。
2. 保留现有七步建档接口，增加完成建档后的分区 DTO 与保存入口，避免破坏首次建档流程。
3. 关键字段仅限出生日期、性别、代谢计算依据、身高、当前体重、活动水平、主要目标、目标体重和目标日期；变化后设置 `plan_needs_recalculation`。
4. 腰围、工作状态、睡眠时长、每周运动天数、饮食方式和普通口味偏好直接保存，不设置重算标记。
5. 过敏与禁忌保存后让食物建议查询立即排除冲突项；不改变计划数值。
6. 风险答案保存后立即复用现有风险检查并暂停不安全计划。
7. 新计划继续先产生预览；只有确认接口成功后切换当前版本并清除重算标记，取消预览不改变旧计划。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=ProfileSectionServiceTests,PlanPolicyTests,PlanIntegrationTests
```

阶段提交：

```text
feat: 完成健康档案分区编辑闭环
```

## 任务 6：隐私文件、独立版本与健康授权

新增：

- `backend/src/main/java/com/lightbite/healthy/privacy/PrivacyDtos.java`
- `backend/src/main/java/com/lightbite/healthy/privacy/PrivacyService.java`
- `backend/src/main/java/com/lightbite/healthy/privacy/PrivacyController.java`
- `backend/src/test/java/com/lightbite/healthy/privacy/PrivacyServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/PrivacyIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/auth/AuthService.java`
- `backend/src/main/java/com/lightbite/healthy/today/TodayService.java`
- `backend/src/main/java/com/lightbite/healthy/plan/PlanService.java`
- 各健康记录与报告控制器的统一授权入口。

步骤：

1. 先写测试覆盖隐私政策与健康授权独立版本、普通更新、实质更新、旧版继续使用和新版专属能力限制。
2. 通过 V12 初始化当前中文隐私政策和健康授权版本；服务只读返回当前版本、最新版本、摘要、正文和历史同意事件。
3. 注册只记录当时最新的隐私政策版本；健康授权单独记录，不再把两个版本强制绑定在一行。
4. 撤回健康授权只需登录和二次确认，追加撤回事件并更新当前状态。
5. 在服务端统一健康能力入口拒绝撤回后的计划、记录和报告读写，同时保留账户、安全、隐私、导出、删除和注销能力。
6. 重新同意追加新事件并恢复仍存在的数据；源数据或关键档案已变化时继续要求重算。
7. 新功能需要更高授权版本时在该功能入口声明固定最低版本，不实现通用策略引擎。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=PrivacyServiceTests,PrivacyIntegrationTests
```

阶段提交：

```text
feat: 完成隐私版本与健康授权管理
```

## 任务 7：手机号换绑与人工申诉

新增：

- `backend/src/main/java/com/lightbite/healthy/account/PhoneChangeDtos.java`
- `backend/src/main/java/com/lightbite/healthy/account/PhoneChangeService.java`
- `backend/src/main/java/com/lightbite/healthy/account/PhoneChangeController.java`
- `backend/src/test/java/com/lightbite/healthy/account/PhoneChangeServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/PhoneChangeIntegrationTests.java`

步骤：

1. 先写测试覆盖旧号码验证码、新号码验证码、号码冲突、验证码跨用途、并发换绑和会话撤销。
2. 正常换绑在一个事务中验证两个号码、更新用户与手机号身份、撤销其他设备并写安全事件。
3. 向新旧手机号发送结果通知；通知失败记录可重试状态，但不得回滚已经安全完成的换绑。
4. 人工申诉只实现提交必要材料引用、查看状态和受控处理入口；不实现自动审核或管理后台。
5. 存在活动申诉时禁止重复提交；申诉期间由服务端拦截已确认的敏感操作。
6. 申诉通过后的换绑撤销全部设备与令牌；原设备不能保留会话。
7. 申诉结束 90 天后清理材料；依法保留内容转入隔离流程。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=PhoneChangeServiceTests,PhoneChangeIntegrationTests
```

阶段提交：

```text
feat: 完成手机号换绑与申诉流程
```

## 任务 8：中文加密 PDF 数据导出

新增：

- `backend/src/main/java/com/lightbite/healthy/datarights/DataExportDtos.java`
- `backend/src/main/java/com/lightbite/healthy/datarights/DataExportService.java`
- `backend/src/main/java/com/lightbite/healthy/datarights/DataExportPdfService.java`
- `backend/src/main/java/com/lightbite/healthy/datarights/DataExportController.java`
- `backend/src/test/java/com/lightbite/healthy/datarights/DataExportServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/datarights/DataExportPdfServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/DataExportIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/report/ReportPdfService.java`，仅提取可复用的中文字体或分页辅助；不改变现有报告内容。

步骤：

1. 先写测试覆盖验证码、24 小时限频、活动任务唯一、失败不计次数、跨用户下载和下载过期。
2. 用一个数据截止时间读取账户、档案、计划、健康记录和报告内容；不得把内部 ID 放入导出 DTO。
3. 复用现有 PDFBox 与中文字体，生成目录、章节、月份分段和页码；不增加 PDF 依赖。
4. 使用 PDFBox 标准保护策略设置用户密码，并验证无密码不能打开、正确密码可提取中文文本。
5. PDF 密码只作为可清除内存值进入任务，`finally` 中清除；数据库、日志和错误对象均不得保存。
6. 应用重启时把遗留的待处理或生成中导出标记失败并清理半成品。
7. 文件完成后提供 24 小时鉴权下载；过期清理文件，申请元数据保留 90 天。
8. 写内容扫描测试，确认手机号脱敏且不存在密码、验证码、令牌、内部 ID 或英文数据库字段名。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=DataExportServiceTests,DataExportPdfServiceTests,DataExportIntegrationTests
```

阶段提交：

```text
feat: 完成加密健康数据导出
```

## 任务 9：健康数据删除预览、来源与事务执行

新增：

- `backend/src/main/java/com/lightbite/healthy/datarights/HealthDataDeletionDtos.java`
- `backend/src/main/java/com/lightbite/healthy/datarights/HealthDataDeletionService.java`
- `backend/src/main/java/com/lightbite/healthy/datarights/HealthDataDeletionController.java`
- `backend/src/test/java/com/lightbite/healthy/datarights/HealthDataDeletionServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/HealthDataDeletionIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/plan/PlanService.java`
- `backend/src/main/java/com/lightbite/healthy/report/ReportService.java`
- `backend/src/main/java/com/lightbite/healthy/report/ReportDataCollector.java`
- 各健康记录模块，仅增加数据权利服务需要的用户范围计数与删除方法。

步骤：

1. 先写影响预览测试，覆盖每种数据类型、时间边界、全部删除和跨用户隔离。
2. 预览由服务端按选择范围计数并解析 `health_report_sources` 与计划来源，不接受客户端提供的影响数量。
3. 新生成计划写入来源测量标识；历史空来源计划只有在能通过既有不可变快照精确确认时才删除，不能按日期猜测。
4. 删除源记录时永久删除所有引用它的报告版本与来源关系；无关时间段报告保留。
5. 删除档案或来源测量时永久删除依赖的计划版本；若删除当前版本，按剩余版本重建当前指针或将计划置空。
6. 删除全部健康数据覆盖档案、目标、偏好、风险、测量、计划、记录、报告和健康授权当前状态，保留账户和最小安全事件。
7. 少量同步删除与大型异步删除调用同一事务方法，保证失败整体回滚。
8. 使用数据库状态或唯一约束保证同一用户只有一个活动删除任务。
9. 写故障注入测试，确认中途异常后所有源记录、计划和报告均未变化。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=HealthDataDeletionServiceTests,HealthDataDeletionIntegrationTests
```

阶段提交：

```text
feat: 完成健康数据关联删除
```

## 任务 10：账户注销、恢复和永久清理

新增：

- `backend/src/main/java/com/lightbite/healthy/account/AccountDeletionDtos.java`
- `backend/src/main/java/com/lightbite/healthy/account/AccountDeletionService.java`
- `backend/src/main/java/com/lightbite/healthy/account/AccountDeletionController.java`
- `backend/src/main/java/com/lightbite/healthy/account/AccountDeletionCleanup.java`
- `backend/src/test/java/com/lightbite/healthy/account/AccountDeletionServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/AccountDeletionIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/auth/AuthService.java`
- `backend/src/main/java/com/lightbite/healthy/auth/BearerTokenFilter.java`
- `backend/src/main/java/com/lightbite/healthy/datarights/DataExportService.java`

步骤：

1. 使用可注入 `Clock` 写 7 天边界测试：边界前可恢复，边界时及之后不可恢复。
2. 注销申请在一个事务中验证短信、创建活动申请、设置 `DELETION_PENDING`、撤销全部令牌并取消导出。
3. 重复申请返回当前注销状态，不产生第二条活动申请。
4. 注销处理中登录只签发受限会话；状态接口返回申请时间、计划完成时间和服务端剩余秒数。
5. 恢复操作验证绑定手机号，恢复 `ACTIVE`，结束注销申请，只为当前设备签发普通会话。
6. 到期清理按外键安全顺序删除业务数据、身份、密码、设备和令牌，并删除或匿名化用户主记录以释放手机号。
7. 法定保留记录转为不可用于恢复账户的隔离引用；普通业务查询无法访问。
8. 清理任务可重复执行：已清理账户再次执行不报错，也不恢复任何数据。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=AccountDeletionServiceTests,AccountDeletionIntegrationTests
```

阶段提交：

```text
feat: 完成账户注销与恢复闭环
```

## 任务 11：Flutter 领域模型、API 与会话路由

新增：

- `mobile/lib/features/account/domain/account_data.dart`
- `mobile/lib/features/account/application/account_controller.dart`
- `mobile/lib/features/privacy/domain/privacy_data.dart`
- `mobile/lib/features/privacy/application/privacy_controller.dart`
- `mobile/lib/features/data_rights/domain/data_rights_data.dart`
- `mobile/lib/features/data_rights/application/data_rights_controller.dart`
- `mobile/test/features/account/domain/account_data_test.dart`
- `mobile/test/features/account/application/account_controller_test.dart`
- `mobile/test/features/privacy/application/privacy_controller_test.dart`
- `mobile/test/features/data_rights/application/data_rights_controller_test.dart`

修改：

- `mobile/lib/core/api/api_client.dart`
- `mobile/lib/app/session_controller.dart`
- `mobile/lib/app/router.dart`
- `mobile/test/app/session_controller_test.dart`
- `mobile/test/core/api/` 下相应 API 契约测试。

步骤：

1. 先写 JSON 解析、中文状态映射、API 请求和控制器竞态测试。
2. 为账户、安全、档案分区、隐私、导出、删除和注销增加最小领域模型，不把原始 `Map` 扩散到页面。
3. `ApiClient` 增加现有接口所需方法，统一复用授权、刷新令牌、错误解析和文件下载能力。
4. 会话阶段增加“注销处理中”；恢复会话根据服务端会话类型或账户状态路由，不能由本地缓存猜测。
5. 撤回授权后清除或隔离本地健康成功缓存；账户和数据权利页面仍可访问。
6. 控制器忽略已取消或过期请求结果，防止快速返回页面后旧请求覆盖新状态。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/account test/features/privacy test/features/data_rights test/app/session_controller_test.dart test/core/api
```

阶段提交：

```text
feat(flutter): 接入账户与隐私领域状态
```

## 任务 12：Flutter 账户首页与健康档案分区

新增：

- `mobile/lib/features/account/presentation/account_section.dart`
- `mobile/lib/features/profile/presentation/profile_overview_page.dart`
- `mobile/lib/features/profile/presentation/profile_section_page.dart`
- `mobile/test/features/account/presentation/account_page_test.dart`
- `mobile/test/features/profile/presentation/profile_overview_page_test.dart`
- `mobile/test/features/profile/presentation/profile_section_page_test.dart`

修改：

- `mobile/lib/features/account/presentation/account_page.dart`
- `mobile/lib/features/profile/presentation/profile_wizard_page.dart`，仅复用或提取现有字段组件，不改变首次建档行为。
- `mobile/lib/core/theme/app_theme.dart`
- `mobile/lib/core/theme/app_spacing.dart`
- `mobile/lib/app/app_shell.dart`

步骤：

1. 先写 Widget 测试锁定六组顺序、脱敏手机号、游客/未建档/已建档状态和危险操作区。
2. 用现有 Material 列表与卡片构建分组设置首页，不引入第三方设置组件。
3. 统一主要控件 6 px 圆角；危险操作不能只用颜色表达。
4. 完成建档后进入六分区概览；未建档继续进入现有七步向导。
5. 分区表单复用现有日期、数字、选择和风险控件，保存失败保留输入。
6. 关键字段保存后在档案和计划入口持续展示“计划需要重新计算”；普通字段不显示。
7. 过敏与禁忌保存成功后显示即时生效说明；风险命中显示既有非医疗安全提示。

阶段验证：

```powershell
flutter test test/features/account/presentation test/features/profile/presentation test/app/profile_wizard_interaction_test.dart
```

阶段提交：

```text
feat(flutter): 完成账户首页与档案编辑
```

## 任务 13：Flutter 设备、换绑、隐私和安全记录页面

新增：

- `mobile/lib/features/account/presentation/device_management_page.dart`
- `mobile/lib/features/account/presentation/security_events_page.dart`
- `mobile/lib/features/account/presentation/phone_change_page.dart`
- `mobile/lib/features/account/presentation/phone_appeal_page.dart`
- `mobile/lib/features/privacy/presentation/privacy_center_page.dart`
- `mobile/lib/features/privacy/presentation/privacy_document_page.dart`
- `mobile/lib/features/privacy/presentation/health_authorization_page.dart`
- 对应 `mobile/test/features/account/presentation/` 与 `mobile/test/features/privacy/presentation/` Widget 测试。

步骤：

1. 设备页展示设备名、系统、最近活跃和当前设备；当前设备不渲染移除按钮。
2. 单设备移除使用二次确认；退出其他设备使用短信验证页，处理中禁用重复提交。
3. 换绑严格按旧号码验证码、新号码验证码、结果三步展示；旧号码不可用进入申诉。
4. 申诉期间在敏感入口展示服务端返回的冻结原因，不只在客户端隐藏按钮。
5. 隐私中心展示当前同意版本、最新版本、非阻断更新提示和历史记录。
6. 文档页展示变更摘要、生效日期和中文全文；隐私政策与健康授权分开呈现。
7. 撤回授权弹窗明确列出影响，不要求短信；成功后会话控制器刷新权限并清理健康缓存。
8. 新版专属功能受限时展示原因和“查看新版”，旧能力继续使用。

阶段验证：

```powershell
flutter test test/features/account/presentation test/features/privacy/presentation
```

阶段提交：

```text
feat(flutter): 完成账户安全与隐私页面
```

## 任务 14：Flutter 数据导出、数据删除与注销页面

新增：

- `mobile/lib/features/data_rights/presentation/data_export_page.dart`
- `mobile/lib/features/data_rights/presentation/health_data_deletion_page.dart`
- `mobile/lib/features/data_rights/presentation/deletion_impact_page.dart`
- `mobile/lib/features/account/presentation/account_deletion_page.dart`
- `mobile/lib/features/account/presentation/deletion_pending_page.dart`
- 对应 `mobile/test/features/data_rights/presentation/` 与 `mobile/test/features/account/presentation/` Widget 测试。

修改：

- `mobile/lib/app/router.dart`
- `mobile/lib/app/session_controller.dart`
- `mobile/lib/core/api/api_client.dart`

步骤：

1. 导出页完成短信验证、PDF 密码设置、任务列表、生成中、可下载、过期和失败状态。
2. 密码输入不进入日志、缓存或持久化；离开申请流程时清空控制器文本。
3. 下载前展示文件名、生成时间和过期时间；过期状态只提供重新申请。
4. 删除页支持数据类型与时间段选择；全部删除使用单独高风险选项。
5. 必须先加载服务端影响预览，再进入验证码和最终确认；最终确认文案显示数量与受影响计划、报告。
6. 删除任务处理中禁止重复提交；失败明确显示“数据未发生变化”。
7. 注销申请页展示 7 天冷静期和影响；申请成功后清除普通令牌并进入受限登录逻辑。
8. 注销处理中页面只显示申请时间、永久注销时间、剩余天数、恢复账户和退出登录。
9. 恢复成功后仅当前设备建立普通会话并进入账户中心。

阶段验证：

```powershell
flutter test test/features/data_rights/presentation test/features/account/presentation test/app/session_controller_test.dart
```

阶段提交：

```text
feat(flutter): 完成数据权利与账户注销页面
```

## 任务 15：全量集成、隐私扫描与交付文档

修改：

- `docs/qa/account-privacy-center-acceptance.md`
- `docs/project/04-execution/06-development-log.md`
- `docs/project/04-execution/07-changelog.md`
- `docs/project/05-quality/11-security-review-report.md`
- `docs/project/06-testing-acceptance/14-acceptance-report.md`
- `README.md`，仅在实际交付能力与现有描述不一致时更新。

步骤：

1. 运行后端和 Flutter 全量测试、格式、静态分析、Debug APK 构建和仓库检查。
2. 以 H2 完成端到端账户流程；以 MySQL 8.4 验证 V11→V12 迁移和删除事务。
3. 使用两个设备验证新设备提醒、单设备移除、退出其他设备、正常换绑和申诉换绑会话结果。
4. 使用真实中文夹具生成加密 PDF，验证正确密码、错误密码、脱敏、分页、24 小时过期和跨用户拒绝。
5. 使用跨周期夹具删除源记录，验证相关报告与计划版本永久删除、无关版本保留。
6. 使用可控时钟验证导出 24 小时、申诉材料 90 天、注销 7 天边界和导出记录 90 天。
7. 在 Android API 36 模拟器完成窄屏、字体放大、键盘、滚动、触控、返回键和中文 PDF 打开验收；iOS 无可用环境时明确列为发布前真机门禁。
8. 扫描 App 可见字符串和日志，确认无未翻译英文、验证码、PDF 密码、令牌、完整手机号或完整健康档案。
9. 确认 AI 食物图片识别未被实现或提前接入。
10. 只修复本阶段验收发现的根因问题，不夹带无关重构。

最终命令：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test

cd E:\Healthy\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug

cd E:\Healthy
.\scripts\check.ps1
git diff --check
git status --short --branch
```

最终提交建议：

```text
test: 完成账户与隐私中心集成验收
docs: 更新账户与隐私中心交付记录
```

## 计划完成门禁

开始开发前必须满足：

- 本计划 MD 已完成自检并提交。
- 用户明确确认本计划。
- 实施从包含已确认规格与计划的同一 Git 基线开始。
- Git 提交邮箱为 `3040503900@qq.com`。

完成开发前必须满足：

- 后端、Flutter、仓库检查和 Debug APK 构建全部通过。
- MySQL 8.4 迁移、Android API 36 和可用 iOS 真机门禁有真实记录。
- 导出、删除、注销和授权撤回通过用户隔离、并发、故障回滚和敏感信息扫描。
- 所有页面、按钮、状态和错误提示使用中文。
- 工作区无意外生成物或无关改动。
- AI 食物图片识别仍未实现。
