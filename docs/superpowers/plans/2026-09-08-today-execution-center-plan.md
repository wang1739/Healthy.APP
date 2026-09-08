# 轻食记「今日执行中心」第一版实施计划

日期：2026-09-08

依据：[今日执行中心第一版设计规格](../specs/2026-09-08-today-execution-center-design.md)

## 实施原则

- 先写失败测试，再实现最小代码使测试通过。
- 复用现有 `PlanService`、`ProfileService`、`ApiClient`、Riverpod 和导航结构。
- 不新增数据库表、依赖、缓存框架或临时打卡模型。
- 只展示真实计划和体重数据；未完成模块明确标记为“待接入”。
- 每个任务完成后运行对应小范围测试，最后执行全量回归。
- 任何实现若需要改变已确认规格，先停止并重新确认。

## 任务 1：建立后端今日聚合领域模型

新增：

- `backend/src/main/java/com/lightbite/healthy/today/package-info.java`
- `backend/src/main/java/com/lightbite/healthy/today/TodayDtos.java`
- `backend/src/main/java/com/lightbite/healthy/today/TodayService.java`
- `backend/src/test/java/com/lightbite/healthy/today/TodayServiceTests.java`

步骤：

1. 写服务测试，固定 `READY`、`EMPTY`、`COMING_SOON` 和 `ERROR` 四种模块状态。
2. 测试当前计划为 `ACTIVE`、`NEEDS_RECALCULATION`、`PAUSED`、`RISK_BLOCKED` 和 `EMPTY` 时的映射。
3. 测试计划目标字段完整映射，不在今日模块重复计算 BMI、BMR、TDEE 或目标数值。
4. 测试身体测量按现有接口返回顺序选取最新一条体重。
5. 测试计划读取异常时体重仍返回，体重读取异常时计划仍返回。
6. 测试档案未完成、无计划、计划暂停、风险拦截和计划生效时的 `nextAction`。
7. 实现最小 DTO 和聚合服务，使测试通过。

实现约束：

- `TodayService` 只编排现有领域服务。
- 独立方法读取计划和体重，并在模块边界转换异常为 `ERROR`。
- 尚未实现的营养、饮水、运动、睡眠和任务固定返回 `COMING_SOON`。
- 响应不包含用户 ID、内部异常、数据库字段或计划历史。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=TodayServiceTests
```

## 任务 2：开放并验证今日聚合 API

新增：

- `backend/src/main/java/com/lightbite/healthy/today/TodayController.java`
- `backend/src/test/java/com/lightbite/healthy/TodayIntegrationTests.java`

步骤：

1. 写未登录访问 `/api/v1/today` 返回 401 的测试。
2. 写合法 `YYYY-MM-DD` 日期返回请求日期的测试。
3. 写非法日期返回统一错误结构和中文提示的测试。
4. 写用户隔离测试，确保最新体重和计划不能跨用户读取。
5. 写无档案、无计划、计划生效、计划暂停和风险拦截的接口测试。
6. 写计划或体重模块缺失时仍返回 200 和独立模块状态的测试。
7. 实现控制器；使用 Spring 对 `LocalDate` 的原生绑定，不自行解析日期字符串。

实现约束：

- 路径固定为 `GET /api/v1/today?date=YYYY-MM-DD`。
- 用户 ID 只取 `Authentication.getName()`。
- 不新增 Flyway 迁移。
- 不修改现有计划接口的响应契约。

阶段验证：

```powershell
cd E:\Healthy\backend
.\mvnw.cmd test -Dtest=TodayServiceTests,TodayIntegrationTests
```

## 任务 3：建立 Flutter 今日数据模型与 API

新增：

- `mobile/lib/features/today/domain/today_data.dart`
- `mobile/test/core/api/api_client_today_test.dart`
- `mobile/test/features/today/today_data_test.dart`

修改：

- `mobile/lib/core/api/api_client.dart`

步骤：

1. 写模型解析测试，覆盖完整响应、缺少可选字段、未知扩展字段和四种模块状态。
2. 写日期格式测试，确保 API 使用设备本地日期的 `YYYY-MM-DD`，不附带 UTC 时间。
3. 写 `ApiClient.getToday(date)` 的请求路径、查询参数、鉴权和响应转换测试。
4. 实现不可变的今日数据模型、模块状态枚举和下一步行动枚举。
5. 对服务端未知状态使用安全的降级状态，不让页面解析崩溃。
6. 复用 `ApiClient.errorMessage`，不建立第二套网络错误处理。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/core/api/api_client_today_test.dart test/features/today/today_data_test.dart
```

## 任务 4：实现 Flutter 今日状态控制器

新增：

- `mobile/lib/features/today/application/today_controller.dart`
- `mobile/test/features/today/today_controller_test.dart`

步骤：

1. 写首次加载成功测试。
2. 写下拉刷新测试。
3. 写刷新失败后保留上一次成功数据并标记“可能不是最新”的测试。
4. 写首次请求失败时显示完整错误状态的测试。
5. 写日期变化后重新请求新日期的测试。
6. 写并发加载保护测试，避免一次刷新产生重复请求。
7. 实现基于现有 Riverpod 模式的最小控制器。

实现约束：

- 成功数据只保存在当前进程内存，不提前引入本地数据库或持久缓存。
- 控制器接收明确日期，测试不依赖系统时钟。
- 页面从后台恢复时比较本地日期，仅在跨日后刷新。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/today/today_controller_test.dart
```

## 任务 5：加入本地高清照片轮播

新增或复制：

- `mobile/assets/today/healthy-meal-1.png`
- `mobile/assets/today/healthy-meal-2.png`
- `mobile/assets/today/healthy-meal-3.png`

修改：

- `mobile/pubspec.yaml`
- `mobile/lib/features/today/presentation/today_carousel.dart`
- `mobile/test/features/today/today_carousel_test.dart`

资源来源：

- 优先复用仓库中已有的 `assets/figma-recipe-1.png`、`figma-recipe-2.png`、`figma-recipe-3.png`。
- 复制前检查画面确实为健康饮食真实照片且裁切适合手机横幅；若不符合，则停止并让用户确认替代资源，不临时使用网络图片。

步骤：

1. 写三张本地资源、中文覆盖文案、页码指示和语义标签的 Widget 测试。
2. 使用 Flutter 原生 `PageView` 和 `Timer` 实现轮播，不增加轮播依赖。
3. 支持手动左右滑动；用户操作后重新计算自动轮播时间。
4. 系统开启减少动画时停用自动播放，仍允许手动切换。
5. 统一使用 6px 圆角和高对比度遮罩。
6. 正确释放 `PageController` 和计时器。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/today/today_carousel_test.dart
```

## 任务 6：重构今日页面并接通导航

修改：

- `mobile/lib/features/today/presentation/today_page.dart`
- `mobile/lib/app/app_shell.dart`
- `mobile/test/app/app_shell_test.dart`
- 新增 `mobile/test/features/today/today_page_test.dart`

步骤：

1. 写游客首页测试：不请求私人接口、不显示虚构数值、受限操作进入既有登录闭环。
2. 写已登录未建档测试：显示“完善健康档案”主行动。
3. 写已建档无计划和客户端仍持有待确认预览的测试：显示正确下一步行动并进入计划页。
4. 写计划生效测试：显示目标热量、营养、饮水、运动、睡眠、最新体重和计划周数。
5. 写暂停、风险拦截和需要重算状态测试。
6. 写 `COMING_SOON`、`EMPTY` 和单模块 `ERROR` 卡片文案测试。
7. 写整体网络失败、保留旧数据、重新加载和下拉刷新测试。
8. 写窄屏、大字体和语义标签测试。
9. 将页面实现为：问候日期、轮播、核心目标、执行卡片、下一步建议和快捷入口。
10. 删除今日页通过 `PlanController` 展示已生效目标的旧逻辑；真实目标统一来自今日聚合控制器。
11. 仅观察 `PlanController` 是否仍持有内存中的预览，用于把下一步文案覆盖为“继续确认计划”，不从预览读取今日目标数值。
12. 复用 `AppShell` 现有权限入口和计划导航，不增加第二套鉴权或路由状态。

交互规则：

- 点击核心目标或 `VIEW_PLAN` 进入底部导航“计划”。
- `COMPLETE_PROFILE` 进入现有建档流程。
- 未上线的记录操作显示“该记录功能将在后续阶段接入”。
- 有旧数据的刷新失败使用非阻断提示；无旧数据才显示整页错误状态。

阶段验证：

```powershell
cd E:\Healthy\mobile
flutter test test/features/today/today_page_test.dart test/app/app_shell_test.dart
```

## 任务 7：全量回归、APK 和验收记录

新增：

- `docs/qa/today-execution-center-acceptance.md`

步骤：

1. 运行后端全量测试。
2. 格式化 Flutter 代码并运行全量测试与静态检查。
3. 构建 Android Debug APK。
4. 若模拟器在线，安装 APK 并验收游客、未建档、无计划、计划生效、刷新和模块待接入状态。
5. 若模拟器不在线，明确记录只缺少设备实测，不把构建成功描述为真机验收成功。
6. 运行仓库检查、空白差异检查和敏感信息扫描。
7. 在验收文档记录命令、测试数量、结果、未完成项和 APK 路径。
8. 检查 Git 作者邮箱为 `3040503900@qq.com`，提交并推送 `origin/main`。

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

最终验收标准：

- 今日接口鉴权、用户隔离、日期和降级行为符合规格。
- App 各账户状态不展示虚构数据。
- 计划和体重数据来自现有真实服务。
- 单个模块异常不会导致整个首页不可用。
- 所有用户可见功能、状态和错误提示为中文。
- 主要圆角为 6px，轮播离线可用且尊重减少动画设置。
- 后端、Flutter、静态检查、APK 构建和仓库检查全部通过。
- Git 工作区干净，提交已经推送到私有远程仓库。
