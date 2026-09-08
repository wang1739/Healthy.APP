# 轻食记「饮食记录与营养实时计算」实施计划

日期：2026-09-08

依据：[饮食记录与营养实时计算设计](../specs/2026-09-08-nutrition-cloud-tracking-design.md)

## 实施原则

- 三个任务并行：后端与数据库、Flutter 页面与交互、独立 QA 与最终集成。
- 所有功能先写失败测试，再实现使测试通过的最小代码。
- 后端继续使用现有 `JdbcTemplate`、Bearer Token、统一错误结构和 Flyway，不新增 ORM、状态框架或网络依赖。
- Flutter 继续使用现有 Dio、Riverpod、`SessionController` 和底部导航，不建立第二套路由或鉴权。
- 服务端是营养数据和汇总的唯一权威；Flutter 只做同公式即时预览。
- 不把饮水、AI、条形码、第三方食物库或趋势报告顺带加入本轮。
- 任何实现若需要改变已确认规格，先停止并重新确认。

## 并行任务与依赖

### 任务 A：后端与数据库

分支 `codex/nutrition-backend`。负责 V5 迁移、食物库、餐食记录、营养汇总、接口和今日模块联动。该任务可以独立完成并以自动化测试证明 API 契约。

### 任务 B：Flutter 页面与交互

分支 `codex/nutrition-flutter`。负责数据模型、API 客户端、控制器、饮食页面和录入弹层。开发时使用固定 JSON 与 Fake ApiClient，不等待真实后端。

### 任务 C：独立 QA 与最终集成

分支 `codex/nutrition-qa`。先建立验收矩阵并复核基线；等待 A、B 提交后合并，修复真实契约差异，执行全量检查和 Android 模拟器验收。该任务不直接推送 `main`。

最终由主任务复核候选提交，快进或合并到 `main`，再推送私有 GitHub。

## 任务 1：V5 数据库迁移与种子食物

新增：

- `backend/src/main/resources/db/migration/V5__create_nutrition_tracking.sql`
- `backend/src/test/java/com/lightbite/healthy/NutritionMigrationTests.java`

步骤：

1. 写 V4→V5 升级测试，确认已有用户、档案和计划数据不变。
2. 写空库迁移测试，确认 `foods`、`food_portions`、`meal_entries` 表与索引存在。
3. 建立系统食物和用户自定义食物共用的 `foods` 表；`owner_user_id` 为空代表系统食物。
4. 建立常用份量表，并通过外键级联约束防止孤立份量。
5. 建立餐食记录表，保存食物名称与四项营养快照、软删除时间和幂等键。
6. 对 `(user_id, idempotency_key)` 建唯一约束；为用户日期查询、食物名称搜索和份量排序建立必要索引。
7. 在迁移中加入约 40 种中文常见食物及对应常用份量。
8. 为克数和营养值加入数据库非负与上限约束；SQL 同时兼容 MySQL 8.4 和测试使用的 H2 MySQL 模式。

实现约束：

- 主键沿用字符串 UUID。
- 营养字段使用 `DECIMAL`，不使用 `FLOAT` 或 `DOUBLE`。
- 系统食物名称保持唯一；用户自定义名称只在当前用户可见，不要求全局唯一。
- 种子食物只包含可追溯、常见的基础食物，不加入品牌商品或无法验证的营销食品。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=NutritionMigrationTests
```

## 任务 2：后端食物查询与自定义食物

新增：

- `backend/src/main/java/com/lightbite/healthy/nutrition/NutritionDtos.java`
- `backend/src/main/java/com/lightbite/healthy/nutrition/FoodService.java`
- `backend/src/main/java/com/lightbite/healthy/nutrition/FoodController.java`
- `backend/src/test/java/com/lightbite/healthy/nutrition/FoodServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/FoodIntegrationTests.java`

步骤：

1. 写系统食物搜索、空查询、中文模糊搜索、范围筛选和数量上限测试。
2. 写用户自定义食物仅创建者可见的隔离测试。
3. 写 `/foods/suggestions` 的最近去重与按记录次数计算常用食物测试。
4. 写常用份量稳定排序和营养字段精度测试。
5. 写自定义食物名称、基准营养、重复名称和异常大值的中文校验测试。
6. 使用 `JdbcTemplate` 实现最小查询与写入服务。
7. 控制器从 `Authentication.getName()` 获取用户身份，不接受请求体中的用户 ID。

API：

- `GET /api/v1/foods?query=&scope=ALL&limit=20`
- `GET /api/v1/foods/suggestions?limit=8`
- `POST /api/v1/foods/custom`

实现约束：

- `limit` 在服务端限制为 1–50。
- 搜索结果统一返回每 100 克营养和份量数组。
- `scope=MINE` 只返回当前用户自定义食物，`SYSTEM` 只返回系统食物。
- 未登录返回 401；搜索可以由已登录未建档用户使用，但餐食写入仍要求档案完成。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=FoodServiceTests,FoodIntegrationTests
```

## 任务 3：后端每日饮食与营养计算

新增：

- `backend/src/main/java/com/lightbite/healthy/nutrition/NutritionCalculator.java`
- `backend/src/main/java/com/lightbite/healthy/nutrition/NutritionService.java`
- `backend/src/main/java/com/lightbite/healthy/nutrition/NutritionController.java`
- `backend/src/test/java/com/lightbite/healthy/nutrition/NutritionCalculatorTests.java`
- `backend/src/test/java/com/lightbite/healthy/nutrition/NutritionServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/NutritionIntegrationTests.java`

步骤：

1. 写每 100 克换算、零值营养、边界克数和汇总后统一舍入测试。
2. 写四餐稳定分组与餐次小计测试。
3. 写有活动减脂计划、无计划、暂停、需重算和风险拦截时的目标映射测试。
4. 写新增内置食物时忽略客户端营养值、由服务端重算的测试。
5. 写临时自定义食物和已保存“我的食物”的新增测试。
6. 写编辑时替换快照、删除时软删除、历史快照不随食物库变化的测试。
7. 写未建档、跨用户条目、未来日期、非法餐次、非法克数和不存在食物测试。
8. 写相同幂等键串行和并发请求只创建一条记录的测试。
9. 实现计算器、服务和控制器；新增、编辑、删除成功后返回完整当日响应。

API：

- `GET /api/v1/nutrition/days/{date}`
- `POST /api/v1/nutrition/entries`
- `PUT /api/v1/nutrition/entries/{id}`
- `DELETE /api/v1/nutrition/entries/{id}`

实现约束：

- 使用 `BigDecimal` 计算，响应层再舍入。
- 餐食快照在同一事务内计算并写入。
- 未来日期以服务端本地日期判断。
- 写接口使用 `Idempotency-Key`；新增必填，编辑和删除依靠条目 ID 与事务幂等。
- 每日响应包含日期、四餐、全天汇总、可空计划目标和页面状态。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=NutritionCalculatorTests,NutritionServiceTests,NutritionIntegrationTests
```

## 任务 4：今日执行中心接入真实饮食状态

修改：

- `backend/src/main/java/com/lightbite/healthy/today/TodayDtos.java`
- `backend/src/main/java/com/lightbite/healthy/today/TodayService.java`
- `backend/src/test/java/com/lightbite/healthy/today/TodayServiceTests.java`
- `backend/src/test/java/com/lightbite/healthy/TodayIntegrationTests.java`

步骤：

1. 写无餐食返回 `EMPTY`、有餐食返回 `READY` 的测试。
2. 写摄入热量和三大营养素准确映射测试。
3. 写无有效计划时 `targetKcal` 为空的测试。
4. 写饮食查询失败时仅 `nutrition` 返回 `ERROR`，计划和体重继续返回的测试。
5. 让 `TodayService` 调用 `NutritionService` 的只读汇总方法，不复制 SQL 或计算公式。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=TodayServiceTests,TodayIntegrationTests
```

## 任务 5：Flutter 营养模型与 API 客户端

新增：

- `mobile/lib/features/nutrition/domain/nutrition_data.dart`
- `mobile/test/features/nutrition/nutrition_data_test.dart`
- `mobile/test/core/api/api_client_nutrition_test.dart`

修改：

- `mobile/lib/core/api/api_client.dart`

步骤：

1. 写食物、份量、餐食、餐次小计、全天汇总和可空目标的 JSON 解析测试。
2. 写未知扩展字段和未知页面状态安全降级测试。
3. 写搜索、建议、自定义食物、读取日期、新增、编辑和删除请求契约测试。
4. 写 `Idempotency-Key` 请求头存在且每次用户新增操作稳定复用的测试。
5. 实现不可变模型和最小 ApiClient 方法，复用现有鉴权刷新及 `errorMessage`。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/nutrition/nutrition_data_test.dart test/core/api/api_client_nutrition_test.dart
```

## 任务 6：Flutter 饮食状态控制器

新增：

- `mobile/lib/features/nutrition/application/nutrition_controller.dart`
- `mobile/test/features/nutrition/nutrition_controller_test.dart`

步骤：

1. 写首次加载、日期切换、刷新和未来日期只读测试。
2. 写用户＋日期缓存隔离和页面销毁释放测试。
3. 写跨日恢复刷新以及较旧在途响应被丢弃的测试。
4. 写添加、编辑、删除成功后直接采用服务端完整响应的测试。
5. 写保存失败时保持编辑草稿和现有页面数据的测试。
6. 写重复点击只发一次写请求，并在重试时复用同一幂等键的测试。
7. 使用现有 Riverpod 模式实现自动释放控制器，不增加持久缓存。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/nutrition/nutrition_controller_test.dart
```

## 任务 7：Flutter 饮食页面与录入弹层

新增：

- `mobile/lib/features/nutrition/presentation/nutrition_summary.dart`
- `mobile/lib/features/nutrition/presentation/meal_section.dart`
- `mobile/lib/features/nutrition/presentation/food_entry_sheet.dart`
- `mobile/lib/features/nutrition/presentation/food_search_view.dart`
- `mobile/test/features/nutrition/nutrition_page_test.dart`
- `mobile/test/features/nutrition/food_entry_sheet_test.dart`

修改：

- `mobile/lib/features/nutrition/presentation/nutrition_page.dart`
- `mobile/lib/app/app_shell.dart`
- `mobile/test/app/app_shell_test.dart`

步骤：

1. 写游客示例页和受限操作进入既有登录/建档闭环的测试。
2. 写已建档用户的日期栏、单卡营养总览和四餐折叠测试。
3. 写有计划显示目标进度、无计划只显示摄入量和计划入口的测试。
4. 写最近吃过、常用食物、中文搜索和空搜索结果测试。
5. 写按时间推荐餐次但允许切换的测试。
6. 写常用份量、精确克数和即时营养预览测试。
7. 写自定义食物校验及“保存到我的食物”测试。
8. 写编辑复用弹层、删除中文确认和保存失败保留输入测试。
9. 写窄屏、1.3 倍字体、键盘遮挡、安全区、中文语义和减少动态效果测试。
10. 替换现有 `FeaturePlaceholder`，并让今日页“记录饮食”直接切换到底部导航的饮食页。

界面约束：

- 顶部仅一张总览卡，不堆叠四张大卡。
- 目标进度最多绘制到 100%，文字保留真实超出值。
- 底部“添加食物”位于导航上方且不遮挡餐食内容。
- 主要圆角统一 6px；超标只使用局部温和提示。
- 优先选择份量，只有精确克数和自定义营养需要键盘。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/nutrition/nutrition_page_test.dart test/features/nutrition/food_entry_sheet_test.dart test/app/app_shell_test.dart
```

## 任务 8：QA 基线与集成验收

新增：

- `docs/qa/nutrition-cloud-tracking-acceptance.md`

步骤：

1. 从相同 `origin/main` 基线建立独立 QA 分支并记录候选提交哈希。
2. 在候选合并前建立数据库、接口、Flutter、权限、错误状态和设备验收矩阵。
3. 合入后端候选与 Flutter 候选，解决契约冲突，不触碰无关模块。
4. 运行 V4→V5 迁移、后端全量、Flutter 全量、静态分析和格式检查。
5. 构建 Debug APK，记录路径、文件大小与 SHA-256。
6. 启动本地后端并在 Android Emulator API 36 安装 APK。
7. 验收：登录、完成档案账号、无计划记录、有计划进度、搜索、份量、新增、编辑、删除、日期切换和网络失败。
8. 临时设置 720×1600 和 1.3 倍字体检查溢出，结束后恢复设备设置。
9. 运行 `scripts/check.ps1`、`git diff --check`、敏感凭据和构建产物扫描。
10. 把真实结果、缺陷修复和遗留项写入验收报告并提交，不推送 `main`。

## 任务 9：主线合并与推送

步骤：

1. 主任务检查 QA 最终分支与工作树干净状态。
2. 复核规格中的本轮边界，没有混入饮水、AI、条形码或趋势报告。
3. 将最终候选快进或无冲突合并到 `main`。
4. 在 `main` 重新运行仓库总检查和关键测试。
5. 确认 Git 作者邮箱为 `3040503900@qq.com`。
6. 推送 `origin/main` 并用远端引用核对最终提交。

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

- 用户可在 Android App 完成按餐次的新增、编辑和删除。
- 内置、最近、常用和自定义食物路径均可用。
- 常用份量与克数实时换算正确，保存结果以后端为准。
- 四项营养汇总、餐次小计和减脂计划目标准确一致。
- 无计划时不展示默认目标或虚假百分比。
- 今日执行中心显示真实饮食状态，单模块故障不拖垮首页。
- 权限、用户隔离、未来日期、幂等和营养快照规则通过测试。
- 全部用户可见文案为中文，6px 圆角、窄屏、大字体和减少动态效果通过。
- 后端、Flutter、静态检查、APK、仓库检查和模拟器冒烟全部通过。
- 最终提交已推送至私有 GitHub，工作树干净。
