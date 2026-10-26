# 轻食记 Web 管理端实施计划

日期：2026-10-26

依据：[轻食记 Web 管理端设计规格](../specs/2026-10-26-admin-web-design.md)

## 实施原则

- 从已确认规格提交建立 `codex/admin-web`，不修改或直接推送 `main`。
- 单分支顺序实施，不拆并行任务；数据库、认证、API、页面按依赖逐层完成。
- 每项非平凡逻辑先写失败测试，再实现使其通过的最小代码。
- 复用现有 `JdbcTemplate`、BCrypt、SHA-256 令牌哈希、Spring Security、Flyway 和统一错误结构。
- 管理页面只使用原生 HTML、CSS、JavaScript，不增加 Node、Vue、React、图表库或浏览器测试框架。
- 所有数据库变化只使用 V14；如果实现需要 V15、通用 RBAC、刷新令牌或改变现有注销语义，停止并重新确认。
- 不修改 Flutter 功能；Flutter 只参加最终回归门禁。
- 所有用户可见文案使用中文，主要控件圆角为 6 px。

## 分支与提交安排

实施分支：`codex/admin-web`。

建议提交边界：

1. `feat: 建立管理端认证与审计基础`
2. `feat: 增加管理端业务接口`
3. `feat: 实现轻食记 Web 管理端`
4. `docs: 补充管理端运行说明`

如阶段内只有紧密关联的小改动，可以合并提交；不得为了提交数量拆出无意义提交。完成后报告完整 SHA，不推送 `main`，远程推送等待用户明确授权。

## 任务 1：V14 数据库迁移

新增：

- `backend/src/main/resources/db/migration/V14__create_admin_web.sql`
- `backend/src/test/java/com/lightbite/healthy/AdminWebMigrationTests.java`

步骤：

1. 先写 V1→V14 空库迁移测试，断言管理员、令牌和审计表及必要索引存在。
2. 写 V13→V14 升级测试，预置普通用户、系统食物、自定义食物和历史餐食，升级后断言原数据不变。
3. 写审核状态回填测试：系统食物审核字段为空，现有自定义食物为 `PENDING`。
4. 建立 `admin_users`，保存唯一用户名、显示名、BCrypt 哈希、状态和时间字段。
5. 建立 `admin_access_tokens`，保存管理员外键、唯一令牌哈希、到期和撤销时间。
6. 建立 `admin_audit_logs`，保存管理员、操作、目标、原因、摘要和时间；通用目标 ID 不建立业务外键。
7. 给 `foods` 增加入库审核状态、审核管理员、审核时间、审核意见和已发布系统食物 ID。
8. 为管理员用户名、令牌哈希、审计筛选和自定义食物审核队列建立必要索引。
9. 确认 SQL 同时兼容 MySQL 8.4 与 H2 MySQL 模式。

实现约束：

- 主键继续使用字符串 UUID。
- 系统食物的审核字段保持空值，不伪装成用户审核记录。
- `published_food_id` 只关联系统食物；不得级联删除来源私有食物。
- 不给 `users` 新增角色列或版本列；`DISABLED` 继续复用现有字符串状态。

阶段验证：

```powershell
cd E:\Healthy-worktrees\account-profile-final\backend
.\mvnw.cmd -Dtest=AdminWebMigrationTests test
```

## 任务 2：管理员初始化、登录与安全过滤

新增：

- `backend/src/main/java/com/lightbite/healthy/admin/AdminDtos.java`
- `backend/src/main/java/com/lightbite/healthy/admin/AdminAuthService.java`
- `backend/src/main/java/com/lightbite/healthy/admin/AdminAuditService.java`
- `backend/src/main/java/com/lightbite/healthy/admin/AdminBootstrap.java`
- `backend/src/main/java/com/lightbite/healthy/admin/AdminBearerTokenFilter.java`
- `backend/src/main/java/com/lightbite/healthy/admin/AdminController.java`
- `backend/src/test/java/com/lightbite/healthy/AdminAuthIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/config/SecurityConfig.java`

步骤：

1. 写数据库为空且环境变量完整时创建首个管理员的失败测试。
2. 写已有管理员不覆盖、变量缺失不创建、用户名或密码不合规不创建的测试。
3. 写正确登录、错误凭据统一错误、禁用管理员拒绝和密码只保存 BCrypt 哈希的测试。
4. 写令牌只保存 SHA-256 哈希、默认 8 小时到期、退出撤销和过期拒绝测试。
5. 写普通用户令牌访问管理接口返回 `403`、管理员令牌访问普通私有接口返回 `401` 的隔离测试。
6. 实现启动初始化：用户名 3–64 个字符，密码至少 12 个字符；日志不得包含原始变量值。
7. 复用现有随机令牌和哈希方式签发管理员令牌，不复制密码编码配置。
8. 实现只处理 `/api/v1/admin/**` 的管理员过滤器并授予 `ROLE_ADMIN`。
9. 调整 Spring Security：公开 `/admin/**` 和管理员登录，其余管理接口要求管理员权限。
10. 实现 `POST /api/v1/admin/auth/login` 和 `POST /api/v1/admin/auth/logout`。

实现约束：

- 不实现刷新令牌、Cookie 会话、验证码、找回密码或管理员注册。
- 登录失败文案不区分用户名不存在和密码错误。
- 管理员过滤器不得改变现有普通用户 Token、注销受限会话和健康授权拦截语义。
- 登录和退出成功后追加管理员审计日志；失败操作不建立独立事务审计。

阶段验证：

```powershell
cd E:\Healthy-worktrees\account-profile-final\backend
.\mvnw.cmd -Dtest=AdminAuthIntegrationTests test
```

## 任务 3：只读运营与审计查询

新增：

- `backend/src/main/java/com/lightbite/healthy/admin/AdminDashboardService.java`
- `backend/src/main/java/com/lightbite/healthy/admin/AdminOversightService.java`
- `backend/src/test/java/com/lightbite/healthy/AdminDashboardIntegrationTests.java`
- `backend/src/test/java/com/lightbite/healthy/AdminOversightIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/admin/AdminController.java`
- `backend/src/main/java/com/lightbite/healthy/admin/AdminDtos.java`

步骤：

1. 写看板真实统计失败测试：用户总数、今日活跃、今日有效饮食、待审核食物和注销处理中数量。
2. 写最近 7 天每日新增用户和有效饮食记录趋势测试，使用可控日期验证边界和空日期补零。
3. 写注销申请状态、日期、关键词筛选及分页测试。
4. 写注销查询只读测试，确认没有批准、驳回、取消或提前执行路由。
5. 写审计日志按管理员、操作、目标和日期筛选及分页测试。
6. 实现 `GET /dashboard`，只执行规格中的五个卡片指标和两条 7 天趋势。
7. 实现 `GET /deletion-requests`，只读取现有注销表和用户摘要。
8. 实现审计追加与 `GET /audit-logs`；列表不得返回密码、令牌或健康正文。
9. 统一分页响应，服务端限制 `size` 为 1–50，并稳定按时间与 ID 倒序。

实现约束：

- 今日活跃只按当天 `user_devices.last_seen_at` 的去重用户计算。
- 不新增每日统计表，不伪造历史活跃趋势。
- 趋势固定为连续 7 个自然日，缺失日期返回零。
- 注销申请的任何已有写服务均不得被管理端调用。

阶段验证：

```powershell
cd E:\Healthy-worktrees\account-profile-final\backend
.\mvnw.cmd -Dtest=AdminDashboardIntegrationTests,AdminOversightIntegrationTests test
```

## 任务 4：用户管理与敏感查看

新增：

- `backend/src/main/java/com/lightbite/healthy/admin/AdminUserService.java`
- `backend/src/test/java/com/lightbite/healthy/AdminUserIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/admin/AdminController.java`
- `backend/src/main/java/com/lightbite/healthy/admin/AdminDtos.java`

步骤：

1. 写用户关键词、状态、分页、手机号脱敏、档案完成状态、饮食数量和最近活跃时间测试。
2. 写 `ACTIVE → DISABLED` 成功并撤销设备、访问令牌和刷新令牌的测试。
3. 写 `DISABLED → ACTIVE` 成功但不恢复旧会话的测试。
4. 写重复禁用、重复恢复、非法状态和 `DELETION_PENDING` 修改返回中文 `409` 的测试。
5. 写敏感查看无原因、原因不足 5 字、超过 200 字、缺少日期、倒置日期和超过 31 天拒绝测试。
6. 写敏感查看返回目标用户完整手机号、档案、最新测量、目标、偏好、最新风险和日期范围饮食的测试。
7. 写跨用户数据不混入、软删除饮食不返回和记录稳定排序测试。
8. 写敏感查看成功追加访问原因与日期区间审计，审计写入失败时不返回数据的测试。
9. 实现 `GET /users`、`PATCH /users/{id}/status` 和 `POST /users/{id}/sensitive-view`。
10. 状态更新、会话撤销和审计写入使用单个事务；敏感读取与审计也使用单个事务。

实现约束：

- 普通列表永远返回脱敏手机号，不接受客户端请求取消脱敏。
- 敏感接口只读，不复用会修改计划或档案状态的业务方法。
- 访问原因只进入审计摘要，不写应用普通日志。
- 不新增通用 expectedVersion；条件更新原状态即可处理并发。

阶段验证：

```powershell
cd E:\Healthy-worktrees\account-profile-final\backend
.\mvnw.cmd -Dtest=AdminUserIntegrationTests test
```

## 任务 5：系统食物管理与自定义食物入库审核

新增：

- `backend/src/main/java/com/lightbite/healthy/admin/AdminFoodService.java`
- `backend/src/test/java/com/lightbite/healthy/AdminFoodIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/admin/AdminController.java`
- `backend/src/main/java/com/lightbite/healthy/admin/AdminDtos.java`
- `backend/src/main/java/com/lightbite/healthy/nutrition/FoodService.java`

步骤：

1. 写系统、自定义范围、关键词、分类、审核状态和分页查询测试。
2. 写系统食物新增、编辑营养值和整组替换份量的测试。
3. 写名称重复、非法分类、负值、超限营养、非法份量和空份量标签的中文校验测试。
4. 写系统食物停用后普通搜索不可见、历史饮食快照仍存在、恢复后重新可见的测试。
5. 写新建自定义食物自动为 `PENDING` 且仍只对创建者可见的回归测试。
6. 写审核通过复制系统食物、建立“100 克”份量、关联来源和不改变私有食物可用性的测试。
7. 写驳回意见必填、驳回不影响私有食物、重复审核和系统同名返回 `409` 的测试。
8. 实现系统食物与份量单事务增改、停用和恢复。
9. 实现自定义食物条件审核；发布副本、份量、来源状态和审计写入在同一事务完成。
10. 修改现有 `FoodService.createCustom`，明确写入 `PENDING`，保持现有用户端 API 响应兼容。

API：

```text
GET  /api/v1/admin/foods
POST /api/v1/admin/foods/system
PUT  /api/v1/admin/foods/system/{id}
POST /api/v1/admin/foods/system/{id}/disable
POST /api/v1/admin/foods/system/{id}/restore
POST /api/v1/admin/foods/custom/{id}/review
```

实现约束：

- 营养和克数使用 `BigDecimal`；校验上限与现有 `FoodService` 一致。
- 管理端不得编辑或停用用户私有食物。
- 审核是“是否发布到系统库”，不是用户内容封禁。
- 现有用户食物搜索、建议、餐食历史和用户隔离测试必须继续通过。

阶段验证：

```powershell
cd E:\Healthy-worktrees\account-profile-final\backend
.\mvnw.cmd -Dtest=AdminFoodIntegrationTests,FoodIntegrationTests test
```

## 任务 6：管理端静态壳与安全 API 客户端

新增：

- `backend/src/main/resources/static/admin/index.html`
- `backend/src/main/resources/static/admin/admin.css`
- `backend/src/main/resources/static/admin/admin.js`
- `backend/src/test/java/com/lightbite/healthy/AdminWebIntegrationTests.java`

修改：

- `backend/src/main/java/com/lightbite/healthy/config/WebConfig.java`

步骤：

1. 先写 `/admin/`、CSS 和 JavaScript 可访问且无需认证的失败测试。
2. 写 HTML 包含登录、左侧五项导航、管理员摘要和退出入口的契约测试。
3. 为 `/admin/` 添加最小静态首页转发，不建立通用 SPA fallback。
4. 建立桌面优先的左侧导航壳，使用品牌绿、白色内容区和 6 px 主控件圆角。
5. 实现最小 `api()`：附加 Bearer Token、解析统一错误、处理 `204`，遇到 `401` 清除会话并返回登录。
6. 登录成功只把令牌、显示名和到期时间写入 `sessionStorage`；退出和页面关闭不持久化登录。
7. 所有动态 API 数据通过 `textContent`、`value` 或安全 DOM 属性渲染，不把数据拼入 `innerHTML`。
8. 建立统一加载、空状态、中文错误、分页和二次确认工具函数，不抽象成通用组件框架。

实现约束：

- HTML 只保存静态结构；JavaScript 只维护本页状态。
- 不使用 CDN、外部字体、远程脚本或第三方图标。
- 窄屏只需保证导航可收起和核心操作可用，不扩展移动端专用设计。

阶段验证：

```powershell
cd E:\Healthy-worktrees\account-profile-final\backend
.\mvnw.cmd -Dtest=AdminWebIntegrationTests test
```

## 任务 7：五个管理页面接入真实 API

修改：

- `backend/src/main/resources/static/admin/index.html`
- `backend/src/main/resources/static/admin/admin.css`
- `backend/src/main/resources/static/admin/admin.js`
- `backend/src/test/java/com/lightbite/healthy/AdminWebIntegrationTests.java`

步骤：

1. 接入看板五个核心数字和 7 天两组趋势；使用原生 SVG 或表格，不引入图表库。
2. 接入用户搜索、状态筛选、分页、禁用和恢复确认。
3. 接入敏感访问原因弹窗、31 天日期范围和完整只读详情；离开详情、退出或 `401` 时清空内存数据。
4. 接入系统食物查询、新增、编辑、份量行增减、停用和恢复。
5. 接入自定义食物审核队列、通过确认和驳回意见。
6. 接入注销申请只读筛选和分页；页面不得渲染写操作按钮。
7. 接入审计日志筛选和分页。
8. 为提交中按钮禁用、成功提示、失败保留输入和状态冲突刷新补齐交互。
9. 用 1280 px 桌面、窄屏和浏览器字体放大检查导航、表格、弹窗和表单无阻断溢出。
10. 用真实本地后端完成登录、导航、敏感查看、用户禁用恢复、食物增改审核、注销查看、日志查看和退出冒烟。

实现约束：

- 页面不缓存敏感详情或整份业务列表到持久存储。
- 不展示规格外的运动、睡眠、饮水、计划、报告或支付入口。
- 不在前端模拟成功；所有展示和状态变化以后端响应为准。

阶段验证：

```powershell
cd E:\Healthy-worktrees\account-profile-final\backend
.\mvnw.cmd -Dtest=AdminWebIntegrationTests,AdminDashboardIntegrationTests,AdminUserIntegrationTests,AdminFoodIntegrationTests,AdminOversightIntegrationTests test
```

并在浏览器访问：

```text
http://localhost:8080/admin/
```

## 任务 8：配置、README 与兼容性回归

修改：

- `.env.example`
- `docker-compose.yml`
- `README.md`
- `backend/src/test/java/com/lightbite/healthy/AuthProfileIntegrationTests.java`（仅当需要补用户状态回归断言）
- `backend/src/test/java/com/lightbite/healthy/AccountDeletionIntegrationTests.java`（仅当需要补注销状态回归断言）

步骤：

1. 在 `.env.example` 只加入空的 `ADMIN_USERNAME`、`ADMIN_PASSWORD` 变量，不提交示例真实密码。
2. 让 Docker Compose 透传两个变量，不设置不安全默认值。
3. README 增加管理端实际目录、初始化变量、启动方式、访问地址和本期功能边界。
4. 写或强化回归测试：`DISABLED` 用户无法登录，恢复后可重新登录；`DELETION_PENDING` 流程不受管理端影响。
5. 运行管理员定向测试和现有认证、食物、注销定向测试。
6. 确认没有改动 Flutter 文件、没有新增依赖、没有跟踪 `.env` 或构建产物。

阶段验证：

```powershell
cd E:\Healthy-worktrees\account-profile-final\backend
.\mvnw.cmd -Dtest=AdminWebMigrationTests,AdminAuthIntegrationTests,AdminDashboardIntegrationTests,AdminOversightIntegrationTests,AdminUserIntegrationTests,AdminFoodIntegrationTests,AdminWebIntegrationTests,AuthProfileIntegrationTests,FoodIntegrationTests,AccountDeletionIntegrationTests test
```

## 任务 9：最终门禁与交付

步骤：

1. 运行后端全量测试并记录精确测试数、失败、错误和跳过数量。
2. 运行 Flutter 格式检查、静态分析和全量测试；不构建 APK，因为本轮没有移动端改动。
3. 运行 `scripts/check.ps1`，确认仓库级检查通过。
4. 运行 `git diff --check`。
5. 扫描跟踪文件和提交差异中的 `.env`、密钥库、密码、令牌、API Key 和私钥模式。
6. 以真实环境变量启动后端，验证 `/actuator/health`、`/admin/` 和管理员登录。
7. 完成真实浏览器冒烟，确认中文、6 px 圆角、窄屏、字体放大、敏感数据清理和无控制台异常。
8. 核对 Git 邮箱为 `3040503900@qq.com`、工作树干净、分支不是 `main`。
9. 报告完整提交 SHA、迁移兼容性、后端与 Flutter 测试精确数字、管理端访问地址和遗留环境警告。

全量命令：

```powershell
cd E:\Healthy-worktrees\account-profile-final\backend
.\mvnw.cmd test

cd E:\Healthy-worktrees\account-profile-final\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

cd E:\Healthy-worktrees\account-profile-final
.\scripts\check.ps1
git diff --check
git status --short --branch
```

## 完成标准

- V14 可从空库和 V13 数据安全迁移，MySQL 与 H2 测试均兼容。
- 管理员环境变量初始化、独立认证、8 小时令牌和用户身份隔离通过测试。
- 看板、用户管理、敏感查看、食物管理、注销监管和审计日志全部读取真实数据库。
- 敏感查看必须填写原因，成功访问和所有管理写操作可追溯。
- 用户禁用撤销全部会话，恢复不恢复旧会话，注销处理中状态不可被管理员覆盖。
- 自定义食物审核只控制是否发布系统副本，不改变用户私有使用权。
- `/admin/` 无需 Node 或额外静态服务器即可使用，全部文案中文、主要圆角 6 px。
- 不包含多角色、刷新令牌、批量、导出、会员、支付、AI 或管理员修改健康数据能力。
- 后端、Flutter、仓库检查、敏感扫描和浏览器冒烟全部通过。
- 最终代码保留在 `codex/admin-web`，不直接修改或推送 `main`。
