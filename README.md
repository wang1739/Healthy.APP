# 轻食记 Healthy

轻食记是一套面向健康生活管理的产品。目前仓库包含简版品牌官网、可交互的 Web 减脂饮食记录页、Flutter 移动端基础框架，以及 Spring Boot 后端基础框架。

## 当前结构

```text
Healthy/
├─ index.html / style.css / script.js   品牌官网
├─ nutrition.html / nutrition.css       饮食记录功能页
├─ foods.js / nutrition.js              食物库与本地记录逻辑
├─ api.js                               前端统一 API 客户端
├─ mobile/                             Flutter Android / iOS 应用
├─ backend/                             Spring Boot 4 后端
├─ docker-compose.yml                   MySQL 8.4 本地环境
├─ scripts/check.ps1                    项目基础检查脚本
└─ docs/superpowers/                    架构设计与实施计划
```

后端已经按账户、健康档案、个性计划、饮食、运动、饮水、睡眠、工作计划、健康报告划分业务边界。接口统一使用 `/api/v1` 前缀。

## Web 与后端本地启动

环境要求：Java 17+、Docker Desktop。前端可继续使用现有的静态服务器运行在 `http://localhost:4173`。

1. 复制 `.env.example` 为 `.env`，修改两个本地数据库密码。
2. 在项目根目录启动 MySQL：

   ```powershell
   docker compose up -d mysql
   ```

3. 在 `backend` 目录启动 Spring Boot：

   ```powershell
   .\mvnw.cmd spring-boot:run
   ```

4. 验证接口：打开 `http://localhost:8080/api/v1/system/ping`，应返回 `status: ok`。

`.env` 只用于本地环境，已被 Git 忽略。数据库使用宿主机端口 `3308`，避免与电脑上已有的 MySQL `3306/3307` 冲突。

## 测试

在 `backend` 目录运行：

```powershell
.\mvnw.cmd test
```

测试环境使用内存数据库，不依赖 Docker，覆盖应用启动、Flyway 迁移、公开接口、登录保护和前端跨域。

## 当前接口

- `GET /api/v1/system/ping`：前后端联通检查，无需登录。
- `GET /actuator/health`：服务健康检查，无需登录。
- 其他 `/api/**` 地址默认要求登录，后续账户模块会接入正式认证。

前端通过 `window.LightBiteApi` 调用后端。本机访问时默认连接 `http://localhost:8080/api/v1`，部署后默认使用同域 `/api/v1`。

## Flutter 移动端

移动端当前完成第一轮基础框架：统一主题、6px 圆角、今日/饮食/计划/报告/我的五项中文导航、宽屏可固定侧边栏、页面状态保留，以及后端连通状态。业务页暂为真实开发入口，不填充虚假数据。

环境要求：Flutter 3.47+、Android Studio、Android SDK 36。Android 模拟器默认通过 `http://10.0.2.2:8080/api/v1` 连接电脑上的后端。

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

连接其他后端地址时使用：

```powershell
flutter run --dart-define=API_BASE_URL=https://example.com/api/v1
```

生成 Android 调试安装包：

```powershell
flutter build apk --debug
```

安装包输出到 `mobile/build/app/outputs/flutter-apk/app-debug.apk`。iOS 工程已经生成，正式编译和上架需要 macOS 与 Xcode。

## 一键基础检查

在项目根目录运行：

```powershell
.\scripts\check.ps1
```

脚本会检查 Git 空白错误、常见敏感文件、Web 必需文件，并运行后端测试。Flutter 的分析和测试仍在 `mobile` 目录独立执行。
