# 轻食记「健康报告」实施计划

日期：2026-09-10

依据：[健康报告设计规格](../specs/2026-09-10-health-reports-design.md)

## 实施原则

- 继续使用“健康饮食”项目内已有的后端、Flutter、QA 三个任务，不创建新对话。
- 规格与本计划确认并推送后，三个任务必须从同一个精确 `origin/main` 提交创建全新工作树，不复用每日任务阶段工作树。
- 后端沿用 Spring Boot、`JdbcTemplate`、Flyway、认证主体和统一中文错误；Flutter 沿用 Dio、Riverpod、`shared_preferences`、现有路由与三种用户状态权限闭环。
- 报告由服务端按需同步生成并保存不可变 JSON 快照；客户端不重新计算业务指标，数据库不保存 PDF 二进制。
- 每项非平凡逻辑先写会失败的最小测试，再补最小实现；后端、Flutter 和 QA 候选都必须独立全量回归。
- 不新增 ORM 仓储层、接口加单实现、消息队列、定时任务、AI、图表库、对象存储、公开链接或本地数据库。
- 仅 PDF 生成允许新增一个固定版本的 Java 依赖；优先选择可嵌入开源中文字体、可流式输出且许可证兼容的最小方案。
- 报告只读取现有体重/计划、饮食、饮水、运动、睡眠和每日任务权威数据，不修改这些模块的计算公式或原始记录。
- Web 官网不增加报告业务页面；本期只实现后端 API 与 Flutter App。
- 如实现需要改变已确认的周期、充分性、建议排序、隐私或版本规则，停止开发并回到规格确认，任一任务不得自行扩展。

## 三个既有任务与分支

### 后端任务

继续使用现有后端任务，改名为“健康报告后端开发”。创建：

- 工作树：`E:\Healthy-worktrees\reports-backend`
- 分支：`codex/reports-backend`

负责 V11、周期策略、只读数据收集、纯计算、版本与幂等、来源追踪、HTTP API、PDF 和后端测试。

### Flutter 任务

继续使用现有 Flutter 任务，改名为“健康报告 Flutter 开发”。创建：

- 工作树：`E:\Healthy-worktrees\reports-flutter`
- 分支：`codex/reports-flutter`

负责领域模型、API、状态控制与缓存、结论优先页面、历史版本、依据跳转、PDF 下载、权限闭环和 Flutter 测试。

### QA/集成任务

继续使用现有 QA 任务，改名为“健康报告 QA 集成”。创建：

- 工作树：`E:\Healthy-worktrees\reports-qa`
- 分支：`codex/reports-qa`

先独立建立验收矩阵与共同基线；等待两个候选后完成合并、契约修复、Android API 36 触控和 PDF 验收，产出唯一最终候选。

三个任务均不得直接推送 `main`。后端和 Flutter 只提交候选；QA 合并并只修复经验证的集成问题；主任务最终复核、合并并推送私有 GitHub。

## 执行顺序与交接

1. 主任务提交并推送已确认规格与计划，记录精确 `origin/main` 基线 SHA。
2. QA 从该 SHA 创建工作树，先写验收矩阵并完成未改代码的基线检查。
3. 后端与 Flutter 从同一 SHA 并行开发；Flutter 依据固定 API 契约和测试假数据开发，不等待后端运行。
4. 后端提交工作树干净的候选 SHA；Flutter 提交工作树干净的候选 SHA。
5. QA 依次合并两个候选，若冲突则保持已经确认的契约，不静默改变规格。
6. QA 跑全量自动化、以 H2 启动后端、安装 Debug APK，在 API 36 模拟器完成真实中文 PDF 下载和打开验收。
7. QA 只提交最小根因修复、最终验收报告与唯一候选 SHA。
8. 主任务复核候选，在 `main` 再跑门禁，合并并推送，核对本地与远端 SHA 一致。

## 任务 1：QA 建立验收矩阵与共同基线

所有者：QA/集成任务。

新增：

- `docs/qa/health-reports-acceptance.md`

步骤：

1. 从计划推送后的精确 `origin/main` 创建 QA 工作树，记录基线 SHA、Java、Flutter、Android SDK、模拟器和数据库环境。
2. 将规格第 19 节拆成矩阵：迁移、周期、充分性、对比、建议、版本、并发、幂等、来源、删除、权限、隐私、PDF、缓存、可访问性与设备触控。
3. 每项标注验证层级：迁移、纯单元、服务、HTTP、Dart、Widget、Android API 36、MySQL 8.4 发布门禁。
4. 在未合并候选前运行后端与 Flutter 全量测试、静态分析、Debug APK 构建和仓库检查，记录真实数量与 APK 哈希。
5. 确认 `emulator-5554` 或其他 API 36 设备是否在线；没有设备只记录环境阻断，不延误并行开发。
6. 提交仅含验收文档的 QA 基线提交，将 SHA 发给后端、Flutter 与主任务。

基线命令：

```powershell
cd E:\Healthy-worktrees\reports-qa\backend
.\mvnw.cmd test

cd E:\Healthy-worktrees\reports-qa\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug

cd E:\Healthy-worktrees\reports-qa
.\scripts\check.ps1
git diff --check
git status --short --branch
```

## 任务 2：V11 健康报告数据库迁移

所有者：后端任务。

新增：

- `backend/src/main/resources/db/migration/V11__create_health_reports.sql`
- `backend/src/test/java/com/lightbite/healthy/ReportMigrationTests.java`

步骤：

1. 先写 V10→V11 升级测试，确认已有账号、档案、计划与六类健康数据不变。
2. 写空库迁移测试，确认 `health_reports` 与 `health_report_sources`、外键、唯一约束和查询索引存在。
3. `health_reports` 按规格保存用户、类型、周期本地日期、时区、周期状态、版本、规则版本、截止时间、输入哈希、不可变快照、幂等键、软删除与创建时间。
4. 约束 `(user_id, report_type, period_start, version)` 唯一，并约束用户范围内幂等键唯一。
5. `health_report_sources` 保存报告、栏目、指标、来源类型、来源 ID 与本地日期；以报告、指标和来源组合去重。报告删除时只软删报告，不级联删除任何原始健康数据。
6. 索引只服务真实查询：用户＋类型＋周期＋删除状态、用户＋创建时间、报告来源明细。
7. JSON 快照使用现有数据库可兼容的文本字段，避免引入 MySQL 专属 JSON 查询逻辑。
8. SQL 同时通过 H2 MySQL 模式；真实 MySQL 8.4 迁移若当前环境不可用，明确列为发布门禁。

阶段验证：

```powershell
cd E:\Healthy-worktrees\reports-backend\backend
.\mvnw.cmd test -Dtest=ReportMigrationTests
```

## 任务 3：周期与时间策略

所有者：后端任务。

新增：

- `backend/src/main/java/com/lightbite/healthy/report/ReportDtos.java`
- `backend/src/main/java/com/lightbite/healthy/report/ReportPeriodPolicy.java`
- `backend/src/test/java/com/lightbite/healthy/report/ReportPeriodPolicyTests.java`

步骤：

1. 先用参数化测试覆盖日报、周一至周日、自然月、闰日、跨月、跨年、当前周期和上一完整周期。
2. 类型只允许 `DAILY`、`WEEKLY`、`MONTHLY`，服务端根据客户端传入的合法 IANA 时区与日期计算边界。
3. 当前自然周期标记 `IN_PROGRESS`，历史周期标记 `COMPLETE`；未来日期返回统一中文校验错误。
4. 无效或不支持的时区返回 400，不回退服务器时区，不允许客户端传任意起止日期。
5. 将查询截止点固定为生成开始时刻，所有模块共用同一个 cutoff，避免生成中数据变化造成混合快照。
6. DTO 只承载实际 API 和内部计算需要的数据，不创建一套接口加单实现的抽象层。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=ReportPeriodPolicyTests
```

## 任务 4：六类权威数据只读收集

所有者：后端任务。

新增：

- `backend/src/main/java/com/lightbite/healthy/report/ReportDataCollector.java`
- `backend/src/test/java/com/lightbite/healthy/report/ReportDataCollectorTests.java`

修改现有模块仅限增加必要的包内或公开只读查询：

- `backend/src/main/java/com/lightbite/healthy/plan/`
- `backend/src/main/java/com/lightbite/healthy/nutrition/`
- `backend/src/main/java/com/lightbite/healthy/hydration/`
- `backend/src/main/java/com/lightbite/healthy/activity/`
- `backend/src/main/java/com/lightbite/healthy/sleep/`
- `backend/src/main/java/com/lightbite/healthy/tasks/`

步骤：

1. 先写数据收集测试，覆盖无计划、计划中、风险暂停、部分记录、跨时区边界和 cutoff 之后新增记录排除。
2. 优先复用各模块现有服务/查询；只有缺少批量只读能力时，才增加最小查询方法，不复制业务公式。
3. 一次收集体重与适用计划、饮食、饮水、运动、夜间睡眠、每日任务及对应目标和来源元数据。
4. 所有查询按用户隔离、按本地周期与统一 cutoff 限定；不能用报告请求读取其他用户数据。
5. 任一权威来源查询失败时整次生成失败，不保存部分报告；无数据是正常空结果，不是系统失败。
6. 收集结果使用一个内部事实对象供计算器消费，同时携带可追溯的来源类型、ID、时间戳和本地日期。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=ReportDataCollectorTests
```

## 任务 5：充分性、指标、对比与规则建议

所有者：后端任务。

新增：

- `backend/src/main/java/com/lightbite/healthy/report/ReportCalculator.java`
- `backend/src/test/java/com/lightbite/healthy/report/ReportCalculatorTests.java`

步骤：

1. 把计算器写成无数据库、无当前时间、无用户会话的纯函数，输入是任务 4 的事实和任务 3 的周期。
2. 先覆盖 `SUFFICIENT`、`LIMITED`、`EMPTY`、`NOT_APPLICABLE` 四种栏目状态，以及周/月 `ceil(eligibleDays × 0.5)` 临界点。
3. 体重趋势必须至少两次测量；有计划的运动按计划次数一半判断，无计划运动至少两条记录；任务仅在存在应执行实例时适用。
4. 饮食热量达标日固定为目标的 90%–110%；宏量营养素单独展示，不合并成笼统“饮食达标”。
5. 目标对比只在该目标适用时生成；上一周期对比只使用上一完整周期且其栏目数据充分时生成，否则返回原因而非结论。
6. 不计算综合健康分、不作医学诊断；关键数字与注意项都能回溯到快照事实。
7. 建议使用 `REPORT_RULES_V1`，固定优先级为数据缺口、计划差距、行为连续性、积极事实，去重后最多三条。
8. 对无数据和数据不足输出中性中文，不使用“异常”“不健康”等诊断性措辞。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=ReportCalculatorTests
```

## 任务 6：版本、幂等、来源与删除服务

所有者：后端任务。

新增：

- `backend/src/main/java/com/lightbite/healthy/report/ReportService.java`
- `backend/src/test/java/com/lightbite/healthy/report/ReportServiceTests.java`

步骤：

1. 先写服务测试覆盖首次生成、输入未变复用、输入改变新版本、同幂等键重试、并发竞争、历史列表、详情、来源与软删除。
2. 对排序后的规范事实、计划版本、周期、时区、cutoff 规则和 `REPORT_RULES_V1` 生成 SHA-256；昵称不进入输入哈希。
3. 快照内固化生成时展示昵称、周期结论、关键数字、六个核心栏目、完整度、对比、建议和隐私允许字段。
4. 同周期输入哈希未变时返回现有最新版本；输入变化才创建递增版本，旧版本永不原地修改。
5. 使用数据库唯一约束解决竞争，不实现分布式锁；唯一冲突的竞争者读取赢家并返回同一版本。
6. 同一个用户最多 100 字符的幂等键与相同请求返回相同结果；幂等键复用于不同请求时返回 409 中文冲突错误。
7. 列表默认最新版本优先，可按类型与周期筛选；列表与详情按当前权威输入计算 `sourceDataChanged`，详情与来源必须校验所属用户及未删除状态。
8. 删除只软删指定报告版本且重复删除结果稳定；不删除源数据，不影响同周期其他版本，也不提供恢复或批量删除。
9. 保存报告与来源引用在同一事务；任何失败都不得留下无来源或半成品报告。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=ReportServiceTests
```

## 任务 7：HTTP API、权限和中文错误

所有者：后端任务。

新增：

- `backend/src/main/java/com/lightbite/healthy/report/ReportController.java`
- `backend/src/test/java/com/lightbite/healthy/ReportIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/common/GlobalExceptionHandler.java`

步骤：

1. 按规格实现生成、列表、详情、依据、PDF 和删除六类接口，不新增未确认端点。
2. `POST /api/v1/reports` 校验登录、档案完整、type/date/timezone 与 `Idempotency-Key`；无活动计划仍允许生成。
3. 列表、详情、来源、PDF、删除统一按当前认证用户隔离；不存在与不属于当前用户均不泄露资源信息。
4. HTTP 测试覆盖游客 401、已登录未建档的中文引导错误、跨账号 404、非法日期/时区 400、幂等冲突 409、生成失败不留快照。
5. 完整用户即使数据不足也返回报告，不把 `EMPTY` 或 `LIMITED` 映射为服务错误。
6. 保持现有错误信封结构；只在现有全局处理器缺失映射时补最小异常映射。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=ReportIntegrationTests
```

## 任务 8：中文 PDF 流式导出

所有者：后端任务。

新增：

- `backend/src/main/java/com/lightbite/healthy/report/ReportPdfService.java`
- `backend/src/test/java/com/lightbite/healthy/report/ReportPdfServiceTests.java`
- `backend/src/main/resources/fonts/<选定中文字体文件>`
- `backend/src/main/resources/fonts/LICENSE.txt`

修改：

- `backend/pom.xml`
- `backend/src/main/java/com/lightbite/healthy/report/ReportController.java`
- 如仓库已有统一第三方声明，则追加到该声明文件，不再创建重复文档。

步骤：

1. 后端任务先从字体官方发布源核验一个支持简体中文、允许随应用再分发的开源字体，只纳入一个实际使用的字体文件和完整许可证。
2. 选择一个支持该字体嵌入与流式生成的最小 Java PDF 库，固定明确版本；不加入模板引擎、图表库或 HTML 渲染器。
3. PDF 仅从不可变快照渲染，内容包含昵称、周期、状态、版本、生成时间、结论、关键数字、注意项、六个核心栏目、完整度、建议和免责声明。
4. 不输出手机号、完整出生日期、登录信息、风险问卷答案、内部来源 ID、幂等键或输入哈希。
5. 文件名使用安全中文或 ASCII 周期名，不接受用户输入路径；响应为认证流式下载，不生成公开 URL，不把文件留在服务器。
6. 测试校验 `%PDF` 头、非空页、中文字体已嵌入、关键中文可提取或可验证、删除/跨用户不能下载。
7. PDF 生成失败返回中文错误且不改变已保存报告；报告生成成功不依赖 PDF 当场生成。

阶段验证：

```powershell
.\mvnw.cmd test -Dtest=ReportPdfServiceTests,ReportIntegrationTests
```

## 任务 9：后端候选全量复核

所有者：后端任务。

步骤：

1. 全量测试必须包含 V1→V11、V10→V11 和空库迁移路径。
2. 复核所有报告 SQL 都含用户隔离、软删除条件和确定性排序。
3. 用并发测试确认同输入只产生一个版本，用失败注入确认没有半成品。
4. 扫描快照与 PDF 测试夹具，确认不含手机号、完整出生日期和问卷隐私字段。
5. 运行仓库检查、空白检查和敏感信息扫描，提交单一后端候选并报告 SHA、测试数和新增依赖许可证。

候选命令：

```powershell
cd E:\Healthy-worktrees\reports-backend\backend
.\mvnw.cmd test

cd E:\Healthy-worktrees\reports-backend
.\scripts\check.ps1
git diff --check
git status --short --branch
```

## 任务 10：Flutter 报告领域模型与 API

所有者：Flutter 任务。

新增：

- `mobile/lib/features/report/domain/report_data.dart`
- `mobile/test/features/report/domain/report_data_test.dart`
- `mobile/test/core/api/api_client_report_test.dart`

修改：

- `mobile/lib/core/api/api_client.dart`

步骤：

1. 先用固定 JSON 契约写解析和 API 请求测试，覆盖三种周期、四种充分性、六个核心栏目、历史版本、来源和可空对比。
2. 模型只表达 UI 实际需要的报告、摘要、栏目、建议、来源和分页结果，不复制服务端计算公式。
3. API 客户端实现生成、列表、详情、来源、PDF 字节下载和删除；生成请求发送 UUID 幂等键。
4. 将 400/401/403/404/409/5xx 与网络错误映射到现有中文错误体验，不展示服务端堆栈或英文异常名。
5. PDF 下载不新增网络依赖；继续使用 Dio，保存路径使用平台提供的应用文档/缓存能力或现有项目方法。

阶段验证：

```powershell
cd E:\Healthy-worktrees\reports-flutter\mobile
flutter test test/features/report/domain/report_data_test.dart test/core/api/api_client_report_test.dart
```

## 任务 11：Flutter 控制器、缓存与并发保护

所有者：Flutter 任务。

新增：

- `mobile/lib/features/report/application/report_controller.dart`
- `mobile/test/features/report/application/report_controller_test.dart`

步骤：

1. 先写状态测试覆盖游客示例、未建档引导、首次加载、生成、刷新、切换周期/版本、删除、离线缓存和错误保留旧内容。
2. 状态按账户＋报告类型＋周期＋版本隔离；退出、换账号时绝不显示前一账号报告。
3. 使用现有 `shared_preferences` 保存最近成功的只读报告 JSON；缓存只用于离线展示，不能伪装成最新生成成功。
4. 同一请求只允许一个在途操作；用请求序号或现有模式丢弃过期响应和控制器销毁后的响应。
5. 生成失败时保留屏幕上的旧版本并显示中文重试入口；删除成功后选择同周期下一版本或返回空状态。
6. PDF 下载使用报告 ID 与认证接口，展示下载中、成功、失败状态；失败不删除已缓存报告。
7. 不引入通用仓储接口、本地数据库、离线写入队列或后台下载服务。

阶段验证：

```powershell
flutter test test/features/report/application/report_controller_test.dart
```

## 任务 12：结论优先的报告页面

所有者：Flutter 任务。

修改：

- `mobile/lib/features/report/presentation/report_page.dart`

按实际复用需要才新增：

- `mobile/lib/features/report/presentation/report_section_card.dart`
- `mobile/lib/features/report/presentation/report_history_sheet.dart`
- `mobile/lib/features/report/presentation/report_sources_page.dart`
- `mobile/test/features/report/presentation/report_page_test.dart`
- `mobile/test/features/report/presentation/report_sources_page_test.dart`

步骤：

1. 替换现有占位页，顶部提供日报/周报/月报、日期周期选择、当前周期“进行中”标记和生成/更新操作。
2. 按方案 A 排列：周期结论、关键数字、最多三条注意项，然后是体重与计划、饮食、饮水、运动、睡眠、每日任务六个核心栏目。
3. 每个栏目显示充分性、核心指标、目标对比、上一周期对比和“查看依据”；数据不足时明确缺什么，不展示虚假趋势。
4. 历史版本使用底部 Sheet 或简单列表；默认最新，可查看旧版本、删除指定版本，不加入复杂时间轴。
5. 依据页按栏目/指标展示来源摘要并跳回现有记录页；不把内部数据库 ID 作为主要界面内容。
6. PDF 操作显示“下载报告”，成功后调用平台可用打开/分享能力；若没有现成打开能力，只保存并明确文件位置，不为此引入重量级依赖。
7. 保持中文、6px 圆角、现有高级克制视觉、窄屏不横向溢出；1.3x 和 2.0x 字体可滚动、按钮语义完整、减少动画设置下无必要动画。
8. 图形只用原生布局、进度条与文本，不引入第三方图表库。

阶段验证：

```powershell
flutter test test/features/report/presentation
```

## 任务 13：三种用户状态、路由和来源回跳

所有者：Flutter 任务。

修改：

- `mobile/lib/app/router.dart`
- `mobile/lib/features/report/presentation/report_page.dart`
- 必要时修改现有底部导航、认证或档案完成回跳文件。
- `mobile/test/app/auth_flow_test.dart`
- `mobile/test/features/report/report_access_test.dart`

步骤：

1. 游客进入报告标签看到中文示例，可切换示例周期；点击生成、下载、历史或依据时进入现有登录闭环。
2. 已登录未建档用户看到建档说明；点击受限操作进入健康档案，完成后自动回到原本报告意图。
3. 已登录已建档用户可生成报告；没有活动减脂计划仍允许生成，计划栏目显示“不适用”或无计划说明。
4. 来源跳转复用现有饮食、饮水、运动、睡眠、任务和计划路由；返回后仍保留报告周期与版本。
5. 退出登录、切换账号、会话过期时清理当前账户报告状态，遵守已有统一会话规则。
6. Android 返回键、底部导航与深层来源页返回行为一致，不出现循环跳转或空白页。

阶段验证：

```powershell
flutter test test/app/auth_flow_test.dart test/features/report/report_access_test.dart
```

## 任务 14：Flutter 候选全量复核与 APK

所有者：Flutter 任务。

步骤：

1. 全量运行格式化、静态分析和测试；检查所有新页面、按钮、空态、加载态和错误态均为中文。
2. 用 Widget 测试覆盖 360px 窄屏、1.3x/2.0x 字体、减少动画、游客、未建档、无计划、数据不足和离线缓存。
3. 构建 Debug APK，记录绝对路径、字节数与 SHA-256。
4. 确认没有提交 APK、下载 PDF、缓存、日志、密钥或构建产物。
5. 提交单一 Flutter 候选，保持工作树干净，把候选 SHA 和契约差异（应为零）告知 QA。

候选命令：

```powershell
cd E:\Healthy-worktrees\reports-flutter\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
Get-FileHash .\build\app\outputs\flutter-apk\app-debug.apk -Algorithm SHA256

cd E:\Healthy-worktrees\reports-flutter
.\scripts\check.ps1
git diff --check
git status --short --branch
```

## 任务 15：QA 合并候选与自动化回归

所有者：QA/集成任务。

步骤：

1. 在 QA 基线提交上先合并后端候选，再合并 Flutter 候选；记录所有合并 SHA 和冲突处理。
2. 先跑契约定向测试，再跑后端、Flutter 全量；任何失败先定位根因，不在测试中放宽已确认规则。
3. 重点补集成测试：日期/时区一致、栏目字段可空、错误信封、幂等重试、账号切换缓存、过期响应、PDF 响应头和中文文件名。
4. 复核输入哈希确定性与并发生成：相同输入只保留一个版本，变更记录后生成新版本，旧快照与旧 PDF 内容稳定。
5. 验证删除版本不影响源数据；跨账户不能列表、详情、查看来源、下载或删除。
6. 检查数据库与快照没有公开 PDF 地址、原始 PDF 二进制、手机号、完整出生日期或风险问卷。
7. 若 MySQL 8.4 可用，执行 V1→V11、V10→V11 与回滚备份演练；不可用则在 QA 报告标为上线前阻断门禁，而不是声称已验证。

自动化命令：

```powershell
cd E:\Healthy-worktrees\reports-qa\backend
.\mvnw.cmd test

cd E:\Healthy-worktrees\reports-qa\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug

cd E:\Healthy-worktrees\reports-qa
.\scripts\check.ps1
git diff --check
git status --short --branch
```

## 任务 16：Android API 36 与 PDF 端到端验收

所有者：QA/集成任务。

前提：API 36 模拟器在线，后端以 H2 测试配置监听 `0.0.0.0:8080`，App 通过 `10.0.2.2:8080` 访问。

步骤：

1. 安装 QA 构建的 Debug APK，完成游客示例、登录未建档拦截、建档回跳和完整用户四条主路径。
2. 准备跨日、跨周和跨月的六类测试数据，分别生成日报、周报、月报，核对自然周期、进行中状态和六个核心栏目。
3. 修改一条源记录后重新生成，确认出现新版本；切回旧版本，确认快照指标与 PDF 不变化。
4. 连点生成与模拟重试，确认幂等且无重复版本；断网生成失败时旧报告保留，联网后可恢复。
5. 下载并实际打开 PDF，确认中文无方框、分页不截字、关键指标一致、文件名安全且不含隐私字段。
6. 验证依据跳转到对应记录、返回保留周期；删除一个旧版本后源记录与最新版本仍存在。
7. 验证跨账号、退出、重登和会话过期不显示前一账户缓存。
8. 在 720×1600 或等效窄屏、1.3x 与 2.0x 字体下检查溢出、滚动、触控面积、语义和底部导航；恢复模拟器默认设置。
9. 记录屏幕、后端日志、APK 路径/大小/哈希和所有残留风险；停止后端并释放 8080 端口。

设备命令示例：

```powershell
adb devices
adb install -r E:\Healthy-worktrees\reports-qa\mobile\build\app\outputs\flutter-apk\app-debug.apk
adb shell am force-stop com.example.healthy
adb shell monkey -p com.example.healthy 1
adb logcat -d
```

## 任务 17：主线复核、合并与推送

所有者：主任务。

步骤：

1. QA 提交最终验收报告、最小修复和唯一候选 SHA，确认工作树干净且未跟踪构建产物。
2. 主任务审查候选提交范围、第三方 PDF 库与字体许可证、迁移、权限、隐私和 QA 证据。
3. 将 QA 候选合并到 `main`；不从后端或 Flutter 分支再次挑选提交，避免绕过 QA 最终状态。
4. 在 `main` 运行后端全量、Flutter 格式/分析/全量、Debug APK、仓库检查、空白和敏感信息扫描。
5. 确认 Git 提交邮箱为 `3040503900@qq.com`，推送私有远程 `origin/main`。
6. 获取远端 `main` SHA，确认与本地完全一致；报告测试数、APK 路径/哈希及仅剩发布门禁。
7. 若 MySQL 8.4 仍未实测，禁止把该项标记完成；部署前必须在真实 MySQL 8.4 备份环境执行 V11 迁移与基本报告生成冒烟。

主线命令：

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
git config user.email
git status --short --branch
git push origin main
git ls-remote origin refs/heads/main
```

## 最终完成标准

- V11 在空库、历史升级和 H2 MySQL 模式通过；真实 MySQL 8.4 已验证，或明确保留为部署前阻断门禁。
- 日报、自然周报、自然月报能按用户时区同步生成不可变快照，并正确标记进行中/完整周期。
- 六个核心栏目、完整度、目标对比、上一完整周期对比与最多三条确定性建议符合规格且可追溯。
- 同输入与并发重试不制造重复版本，输入变化生成新版本，历史版本内容稳定。
- 游客、未建档、已建档无计划、已建档有计划四条权限路径完整，跨账号无数据泄漏。
- PDF 从快照流式生成，中文可读、内容一致、无公开链接、无服务器永久文件、无禁止隐私字段。
- Flutter 结论优先页面、历史版本、依据、删除、缓存和失败恢复在自动化与 Android API 36 通过。
- 后端、Flutter 全量测试、静态分析、Debug APK、仓库检查、空白与敏感信息扫描全部通过。
- QA 报告记录精确提交、环境、测试数、APK 哈希、设备证据和残留门禁；`main` 与私有远程 SHA 一致。
