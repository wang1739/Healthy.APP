# 轻食记游客浏览与渐进式健康建档实施计划

日期：2026-09-07

依据：[游客浏览与渐进式健康建档设计](../specs/2026-09-07-guest-browsing-and-progressive-profile-design.md)

## 实施原则

- 使用现有 `go_router`、`SharedPreferences` 和页面结构，不增加依赖。
- 先写失败测试，再实现最小代码。
- 后端认证和健康档案接口保持不变。
- 第一轮只建立真实可复用的权限闭环，不伪造尚未开发的业务功能。

## 任务 1：会话状态和游客偏好

修改：

- `mobile/lib/app/session_controller.dart`
- 新增 `mobile/test/app/session_controller_test.dart`

步骤：

1. 测试首次无会话且未选择浏览时进入登录页。
2. 测试点击“先浏览”后进入首页并保存本地偏好。
3. 测试下次启动无会话时根据偏好直接进入首页。
4. 测试登录未建档和已建档两种权限状态。
5. 测试退出登录后保持游客浏览状态。
6. 实现最小会话字段和状态转换，使测试通过。

## 任务 2：按需路由和连续引导

修改：

- `mobile/lib/app/router.dart`
- `mobile/lib/app/session_controller.dart`
- 新增或更新路由测试

步骤：

1. 允许游客、未建档账号和完整账号进入 `/app`。
2. 登录和建档页面只在首次启动或用户主动触发时打开。
3. 记录待继续功能的标签和导航位置。
4. 登录完成后，若存在待继续功能且档案未完成，则进入建档。
5. 建档完成后回到原导航位置并消费一次待继续功能。
6. 取消登录或建档时清除待继续功能并返回首页。

## 任务 3：登录页增加“先浏览”

修改：

- `mobile/lib/features/auth/presentation/login_page.dart`
- `mobile/test/app/auth_flow_test.dart`

步骤：

1. 测试登录页显示“先浏览”。
2. 测试点击后调用游客浏览回调。
3. 保留现有登录、协议和中文错误处理。

## 任务 4：统一权限入口和状态化“我的”页面

修改：

- `mobile/lib/app/app_shell.dart`
- `mobile/lib/features/account/presentation/account_page.dart`
- `mobile/lib/features/nutrition/presentation/nutrition_page.dart`
- `mobile/lib/features/plan/presentation/plan_page.dart`
- `mobile/lib/features/report/presentation/report_page.dart`
- `mobile/test/app/app_shell_test.dart`

步骤：

1. 在 App Shell 建立唯一的个性化功能权限检查。
2. 游客点击受限按钮时显示“登录并继续”的底部弹层。
3. 已登录未建档用户点击时显示“去完善”的底部弹层。
4. 已完成档案用户点击时直接执行页面提供的操作。
5. 为当前占位页面增加最小受限操作按钮，用于验证完整闭环。
6. “我的”页面分别显示游客、未建档和已建档状态及对应入口。

## 任务 5：验证和交付

执行：

```powershell
cd E:\Healthy\mobile
dart format lib test
flutter analyze
flutter test
flutter build apk --debug

cd E:\Healthy
.\scripts\check.ps1
git diff --check
```

模拟器验收：

1. 清理 App 偏好后首次打开，确认登录页有“先浏览”。
2. 点击后确认五个页面可浏览。
3. 点击受限操作，确认游客登录引导。
4. 登录后确认未建档用户进入健康建档；取消后可进入首页并从“我的”继续建档。
5. 完成建档后确认返回原导航位置。
6. 重启 App，确认游客偏好仍有效。

最后检查密钥、提交作者邮箱、工作区状态，将实现提交并推送到 `origin/main`。
