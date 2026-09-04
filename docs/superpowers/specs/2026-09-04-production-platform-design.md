# 轻食记正式上线版产品与技术设计

日期：2026-09-04

状态：待用户最终审核

目标市场：中国大陆

## 1. 目标与已确认决策

轻食记将建设为一套可在中国大陆正式上线的健康生活管理产品。Web 端保持轻量，Flutter App 承载完整业务，Spring Boot 与 MySQL 为所有客户端提供统一数据服务。

已确认的产品决策：

- 交付目标为正式上线版，而非仅供演示的原型。
- Web 端负责品牌展示、下载、账户和报告查看，不复制完整 App。
- App 使用 Flutter，一套代码面向 Android 与 iOS。
- 当前没有 Mac 和 Apple Developer 账号，因此先完成 Android 运行、打包和测试；iOS 保持代码兼容，待具备 Mac 与账号后完成签名、HealthKit 真机验证和上架。
- 登录支持手机号验证码、微信、Apple 和密码备用登录。开发环境先使用模拟验证码，生产环境切换真实服务。
- 健康计划由科学公式和可测试规则生成，AI 仅负责解释与文字建议，不决定核心健康数值。
- 首发市场为中国大陆，采用国内云、备案、短信、微信/支付宝支付及国内隐私合规方案。
- 首发健康数据来源为手动记录、Apple HealthKit 和 Android Health Connect，不接入华为、小米、Keep 等专有平台。
- 视觉延续克制、高级的健康品牌风格，主要圆角为 6px。

## 2. 交付边界

### 2.1 Web 用户端

Web 端包含：

- 品牌官网、产品功能、会员方案和 App 下载。
- 手机号登录。
- 个人健康概览。
- 周报和月报查看。
- 个人数据导出。
- 账户安全、隐私授权和账号注销。
- 隐私政策、用户协议、会员说明、联系与反馈。

Web 端不提供完整餐食编辑、AI 拍照识别、复杂计划编辑和健康设备同步。这些能力以 App 为主，避免维护两套完整客户端。

### 2.2 Flutter App

App 提供账户、健康档案、个性计划、今日执行中心、饮食、饮水、运动、睡眠、工作与生活任务、健康报告、AI 食物识别、会员、家庭和隐私设置。

手机底部导航固定为：

```text
今日 ｜ 饮食 ｜ 计划 ｜ 报告 ｜ 我的
```

平板和大屏使用可悬停展开、可固定的侧边导航。手机底部导航需要贴合左右安全区域、降低无效高度，并兼容系统手势条。

### 2.3 管理后台

管理后台用于用户支持、食物库、食谱、轮播内容、会员产品、订单、AI 成本、反馈、通知模板、系统配置、管理员权限和审计日志。普通用户 Token 不能访问管理接口，高风险操作必须记录操作人和修改前后值。

## 3. 总体架构

```text
品牌官网 / Web 用户端 ─┐
                       ├─ HTTPS ─ Spring Boot API ─ MySQL
Flutter Android / iOS ─┤                  ├─ Redis
管理后台 ───────────────┘                  ├─ 私有对象存储
                                          ├─ 短信/微信/支付
                                          └─ AI/推送/监控
```

后端采用模块化单体。第一版不拆微服务；模块以稳定接口和清晰数据边界协作，未来只有在真实流量或团队边界要求下才拆分。

后端模块：

- `auth`：验证码、登录、Token 和第三方身份。
- `user`：账户、设备和基础设置。
- `profile`：健康档案、测量数据、偏好和风险问卷。
- `plan`：计划计算、版本和调整。
- `nutrition`：食物库、餐食和营养汇总。
- `hydration`：饮水记录与提醒。
- `activity`：运动与系统健康数据同步。
- `sleep`：睡眠记录、趋势和冲突处理。
- `workplan`：每日任务、重复规则和完成状态。
- `report`：日报、周报、月报与导出。
- `ai`：图片识别任务、结果确认和使用额度。
- `membership`：会员、家庭、订单、支付和权益。
- `notification`：本地提醒配置、推送任务和送达状态。
- `admin`：运营管理。
- `audit`：安全与管理操作审计。

统一 API 前缀为 `/api/v1`。所有用户资源都通过认证主体确定 `user_id`，客户端不能通过修改参数访问其他用户数据。

## 4. 环境与基础设施

建立以下隔离环境：

- `local`：本机开发，Docker MySQL，模拟验证码和测试第三方服务。
- `test`：内部联调、Android 安装包和产品验收，使用独立数据库、存储桶与密钥。
- `prod`：正式用户环境，使用生产短信、微信、支付、存储和监控。

基础设施职责：

- MySQL 保存账户、档案、计划、记录、报告和交易数据。
- Redis 保存短期验证码、限流计数、缓存和需要快速撤销的会话状态。
- 私有对象存储保存头像、食物照片和报告文件。
- 后台任务处理报告生成、通知和可重试的第三方调用。
- 监控覆盖服务健康、错误率、慢请求、数据库连接、任务积压和第三方失败。
- 生产数据库执行自动备份，并定期验证恢复流程。

## 5. 统一数据规则

- 核心记录使用不可预测的唯一 ID。
- 所有核心表包含创建时间和更新时间，关键用户数据支持软删除。
- 用户业务数据必须包含 `user_id`，查询默认限定当前认证用户。
- 时间以标准时间存储，按用户时区展示。
- 体重、营养和金额采用精确数值类型。
- 密码仅保存安全哈希；验证码、Token、支付密钥不写入普通日志。
- 图片正文不存入 MySQL，只保存私有对象键、用途、所有者和生命周期。
- 关键算法、计划和协议保存版本，保证历史结果可解释。
- 写操作支持客户端唯一操作号，网络重试不会重复创建数据。

## 6. 账户与认证

### 6.1 数据

- `users`
- `user_identities`
- `user_passwords`
- `verification_codes`
- `refresh_tokens`
- `user_devices`
- `consent_records`
- `account_deletion_requests`

### 6.2 接口

```text
POST   /api/v1/auth/sms/send
POST   /api/v1/auth/sms/login
POST   /api/v1/auth/password/login
POST   /api/v1/auth/wechat/login
POST   /api/v1/auth/apple/login
POST   /api/v1/auth/token/refresh
POST   /api/v1/auth/logout
GET    /api/v1/account
PUT    /api/v1/account
GET    /api/v1/account/devices
DELETE /api/v1/account/devices/{id}
POST   /api/v1/account/deletion
```

验证码短期有效、单次使用，并限制手机号、设备和 IP 的发送频率。Access Token 短期有效，Refresh Token 支持续期、单设备退出和全部设备退出。修改密码或识别到风险后可以撤销已有会话。注销前必须再次验证身份。

## 7. 健康档案与安全拦截

### 7.1 建档步骤

1. 基础资料。
2. 身高、体重、腰围和体脂等身体数据。
3. 活动水平、工作类型和作息。
4. 运动与睡眠习惯。
5. 饮食偏好、过敏和禁忌。
6. 减脂、增肌、维持体重或改善饮食目标。
7. 健康风险问卷。
8. 档案分析结果与确认。

建档支持分步保存。用户修改体重、目标或关键生活方式后，系统提示是否重新计算计划。

### 7.2 风险规则

未成年人、孕期、哺乳期、进食障碍风险、严重慢性病或明显不安全目标不进入普通自动减脂流程。产品提示咨询医生或营养师，并明确说明轻食记不提供医疗诊断或治疗。

### 7.3 数据与接口

数据表：`health_profiles`、`body_measurements`、`health_goals`、`dietary_preferences`、`health_risk_answers`、`health_permissions`。

```text
GET  /api/v1/profile
PUT  /api/v1/profile
POST /api/v1/profile/measurements
GET  /api/v1/profile/measurements
PUT  /api/v1/profile/preferences
POST /api/v1/profile/risk-assessment
GET  /api/v1/profile/completeness
```

## 8. 个性计划引擎

计划引擎读取健康档案，检查风险条件，计算 BMI、BMR 与 TDEE，在安全范围内生成热量、蛋白质、碳水、脂肪、饮水、运动和睡眠目标，并向用户提供计划预览。只有用户确认后计划才生效。

数据表：`health_plans`、`health_plan_versions`、`daily_targets`、`plan_rules`、`plan_adjustments`。

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

公式与规则具有版本号。相同输入和规则版本必须产生稳定结果。AI 只能解释计算结果，不能绕过安全上下限或直接修改目标。

## 9. 今日执行中心

首页展示高清健康生活轮播、当天营养与饮水进度、运动任务、昨晚睡眠、工作与生活任务、体重摘要、连续打卡、健康评分和下一步建议。

App 通过聚合接口加载首页：

```text
GET /api/v1/today?date=2026-09-04
```

某个模块没有数据或暂时失败时，其他模块仍正常返回。记录发生变化后重新获取聚合结果，跨天后自动切换日期。

## 10. 饮食与饮水

饮食数据表：`foods`、`food_portions`、`custom_foods`、`meal_records`、`meal_items`、`nutrition_daily_summaries`、`favorite_foods`、`meal_templates`。

饮食能力包括四类餐次、公共食物搜索、自定义食物、份量换算、增删改、收藏、最近使用、常用搭配、复制昨日餐食、每日汇总、趋势和离线同步。App 可即时计算预览，服务端计算最终权威汇总。

```text
GET    /api/v1/foods/search
GET    /api/v1/foods/{id}
POST   /api/v1/foods/custom
GET    /api/v1/meals
POST   /api/v1/meals
PUT    /api/v1/meals/{id}
DELETE /api/v1/meals/{id}
POST   /api/v1/meals/{id}/items
PUT    /api/v1/meals/{id}/items/{itemId}
DELETE /api/v1/meals/{id}/items/{itemId}
GET    /api/v1/nutrition/daily
GET    /api/v1/nutrition/trend
```

饮水按实际毫升保存，杯数仅用于界面展示。数据表为 `hydration_records` 和 `hydration_settings`。

```text
GET    /api/v1/hydration
POST   /api/v1/hydration
DELETE /api/v1/hydration/{id}
GET    /api/v1/hydration/settings
PUT    /api/v1/hydration/settings
```

## 11. 运动、睡眠与系统健康数据

运动支持手动记录类型、时长、强度和消耗，并接入 Android Health Connect 与 Apple HealthKit。系统导入记录保存来源 ID，重复同步不会重复创建。

运动数据表：`activity_types`、`activity_records`、`activity_sync_sources`、`health_sync_cursors`。

睡眠保存入睡、醒来、时长、质量和可选分段。手动记录与系统导入重叠时提示用户确认，不直接累加。

睡眠数据表：`sleep_records`、`sleep_segments`、`sleep_settings`。

用户拒绝系统健康权限后仍能手动记录；取消授权后停止读取新数据。Windows 阶段完成 Android 接入，iOS 最终验证推迟到具备 Mac 与开发者账号后。

## 12. 工作与生活计划

功能包含每日时间轴、自定义任务、重复规则、饮水与用餐提醒、运动安排、久坐提醒、睡前准备、完成、跳过、延期和勿扰时间。

数据表：`daily_tasks`、`task_recurrences`、`task_completions`、`reminder_settings`。

系统生成任务与用户自建任务明确标记来源。用户可以调整、关闭或跳过健康任务。该模块保持轻量，不发展为完整项目管理工具。

## 13. 健康报告

日报、周报和月报展示营养、饮水、运动、睡眠、体重、计划完成度和健康评分，并给出下一周期建议。核心统计由服务端计算，AI 仅负责文字表达；数据不足时明确说明，不生成武断结论。

数据表：`health_reports`、`report_metrics`、`report_insights`、`report_exports`。

报告支持图片或 PDF 导出。周期报告使用唯一周期标识，后台任务失败重试不会生成重复报告。

## 14. AI 食物识别

流程：

```text
拍照或选择图片
→ 本地压缩与确认
→ 上传私有对象存储
→ 创建异步识别任务
→ 返回候选食物、份量和置信度
→ 用户修改或确认
→ 生成正式餐食记录
```

任务状态为 `UPLOADING`、`QUEUED`、`PROCESSING`、`SUCCEEDED`、`FAILED` 或 `EXPIRED`。界面必须覆盖上传前、上传中、识别中、成功待确认、低置信度待修改、失败重试和转手动记录。

数据表：`uploaded_assets`、`ai_recognition_jobs`、`ai_recognition_results`、`ai_usage_records`。

图片限制格式和大小，去除不必要的定位信息，使用私有地址，并按会员等级限制调用次数。AI 失败不妨碍手动记录，只有用户确认后才写入餐食。

## 15. 会员、家庭与支付

首发权益：

- 免费版：基础饮食、饮水和每日概览。
- Pro：AI 识别、深度报告、完整趋势和高级计划。
- 家庭版：最多五个成员档案和家庭计划。

Android 接入微信支付和支付宝。iOS 数字会员按照 Apple 规则使用应用内购买。服务端决定商品金额、会员期限和权益，客户端不能通过上传价格获得会员。

数据表：`membership_products`、`membership_entitlements`、`orders`、`payment_transactions`、`payment_callbacks`、`refunds`、`family_groups`、`family_members`。

支付回调必须验签且幂等。重复回调不能重复开通，会员降级不删除历史数据。

## 16. 通知、Web 与管理后台

通知数据包括 `notification_preferences`、`notification_jobs` 和 `notification_deliveries`。通知必须获得授权，支持勿扰时段、频率限制和关闭入口。

Web 用户端提供官网、登录、概览、报告、数据导出、账户安全和隐私管理。

管理后台提供运营概览、用户支持、食物库、食谱、轮播、AI 调用与成本、会员产品、订单、反馈、通知模板、管理员角色、配置与审计日志。管理接口统一使用 `/api/v1/admin/**`。

## 17. 页面与交互原则

完整 App 页面按复用能力组织，不为每个动作建立独立复杂页面。主要页面组包括：

- 启动、引导、手机号验证码、密码、微信、Apple、协议、设备和注销。
- 分步健康档案、风险问卷、档案分析和编辑。
- 计划生成、预览、各类目标、周安排、解释、调整、历史和暂停。
- 今日总览、轮播、健康得分、快速记录、建议、打卡和消息。
- 饮食记录、搜索、详情、份量、自定义、常用、收藏、趋势和日历。
- AI 拍照、裁剪、上传、识别、结果确认、修改、失败和额度。
- 饮水、运动、睡眠、系统健康授权和同步状态。
- 今日任务、重复规则、提醒、延期、周概览和勿扰。
- 日报、周报、月报、指标、体重趋势、导出与分享预览。
- 会员、支付、订阅、家庭邀请与成员档案。
- 个人资料、授权、隐私、数据导出、账户安全、反馈和法律文本。

每个依赖数据的页面都覆盖首次加载、成功、空数据、网络失败、服务失败、登录过期、权限拒绝、提交中、校验失败、重复点击、离线、同步冲突和会员不足状态。

## 18. 离线、同步与错误处理

App 本地缓存登录状态、当前计划、当日数据、搜索历史、未同步记录和界面偏好。饮食、饮水、运动、睡眠和任务允许离线新增，联网后使用唯一操作号同步。

同一记录被多个设备修改时不静默覆盖，向用户展示冲突。登录刷新失败后回到登录页，但不删除尚未同步的数据。

统一错误响应：

```json
{
  "code": "PROFILE_INCOMPLETE",
  "message": "请先完善健康档案",
  "requestId": "请求追踪编号",
  "fieldErrors": []
}
```

错误状态使用 `400`、`401`、`403`、`404`、`409`、`422`、`429` 和 `500`。客户端依据稳定错误码显示中文说明，服务端不向用户返回堆栈和内部实现信息。

## 19. 测试与质量门槛

Spring Boot 自动测试覆盖：

- 计划公式、边界与风险拦截。
- 登录、Token、退出和验证码限流。
- 跨用户越权与管理员权限。
- Flyway 数据库迁移。
- 营养计算和每日汇总。
- 重复请求幂等。
- 报告统计与后台重试。
- 支付验签和重复回调。
- 真实 HTTP 集成流程。

Flutter 自动测试覆盖：

- 状态管理和核心计算。
- 登录、建档、计划确认和添加餐食。
- Token 自动刷新。
- 离线同步与冲突。
- 公共组件和关键页面截图对比。
- Android 模拟器与真机集成流程。

Web 和管理后台测试覆盖登录、表单、响应式布局、主流浏览器、管理员角色和审计行为。

人工验收至少覆盖一台主流 Android、一台小屏设备、低性能模拟器、深色模式、大字体、手势导航、Chrome 和 Edge。iOS 在具备 Mac 后覆盖小屏 iPhone、灵动岛、Apple 登录、HealthKit 和应用内购买。

## 20. 安全、隐私与合规

上线前验证暴力登录、验证码轰炸、Token 伪造、跨用户越权、SQL 注入、恶意文件、接口限流、管理权限、支付伪造、日志泄漏、数据导出、注销后访问和对象存储泄漏。

用户可以查看信息收集范围、选择和撤回健康授权、拒绝非必要权限、关闭营销通知、导出数据、删除记录和注销账户。首次启动在同意隐私政策前不加载非必要 SDK；相机、相册、通知和健康权限在实际使用时申请。

中国大陆正式发布需要：

- 国内云服务器、域名、HTTPS 和 ICP 备案。
- 生产短信、微信开放平台、微信支付和支付宝资质。
- 隐私政策、用户协议、第三方信息共享清单和个人信息收集清单。
- Android 签名、应用市场材料和必要的软件著作权准备。
- 后续用于 iOS 的 Mac、Apple Developer 账号和应用内购买配置。

## 21. 实施阶段与验收顺序

每个阶段遵循“需求确认、Figma 对照、数据库、后端、Flutter、联调、测试、用户验收、Git 提交”的顺序。

1. **现有项目基线**：修复无效入口，稳定 Docker、MySQL、Spring Boot 和测试，建立可回退标签。
2. **Flutter 基础框架**：环境、路由、状态、网络、安全存储、设计系统和五项导航。
3. **账户闭环**：手机号、验证码、密码、Token、设备、微信、Apple 接口与注销。
4. **健康档案**：分步建档、测量历史、偏好、风险和档案完整度。
5. **个性计划**：公式、风险拦截、计划预览、确认、版本和调整。
6. **今日执行中心**：聚合接口、轮播、进度、快捷记录、建议和任务。
7. **饮食与饮水**：现有本地原型迁移为云端数据，补充离线同步和趋势。
8. **运动与睡眠**：手动记录、Health Connect、HealthKit 兼容与冲突处理。
9. **工作与生活计划**：时间轴、重复、提醒、完成、跳过和延期。
10. **健康报告**：日报、周报、月报、建议与导出。
11. **AI 食物识别**：私有上传、异步识别、确认、额度和失败降级。
12. **会员与支付**：产品、权益、订单、回调、订阅和家庭。
13. **轻量 Web 与管理后台**：账户、报告、隐私和运营管理。
14. **安全与正式发布**：压力测试、备份恢复、监控、合规、Android 发布与 iOS 后续准备。

每阶段交付完成内容、未完成内容、运行方式、测试账号、接口结果、数据库变化、自动测试、Git 提交编号和需要用户人工体验的操作。

## 22. 正式发布条件

- 核心用户流程全部通过。
- 没有阻断级或高危缺陷。
- 测试与生产环境完全隔离。
- 数据库备份与恢复演练通过。
- 域名、HTTPS、备案和生产第三方资质就绪。
- 隐私材料与应用真实行为一致。
- 用户注销和数据导出经过验证。
- Android 签名具有安全备份。
- 监控、告警和回滚流程可用。
- 官网下载地址、版本号、更新说明和客服信息真实有效。
- GitHub 不包含密钥、签名文件或用户数据。

## 23. 明确延期项

以下内容不进入首发开发范围：

- 华为运动健康、小米、荣耀、Keep 等专有健康平台接入。
- 微服务拆分。
- 完整 Web 版健康记录工具。
- 复杂企业项目管理或社交社区。
- 在没有 Mac 和 Apple Developer 账号时承诺完成 iOS 签名与 App Store 发布。

这些能力只能根据真实用户需求、平台开放条件和运营资源另行立项。
