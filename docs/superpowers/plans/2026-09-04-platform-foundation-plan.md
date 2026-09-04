# 轻食记平台基础框架实施计划

## 1. 工程与构建

- 在 `backend/` 创建 Java 17、Spring Boot 4.1.1 Maven 工程。
- 加入 Web MVC、Security、Validation、JPA、Flyway、MySQL、Actuator 和测试依赖。
- 生成 Maven Wrapper，保证构建不依赖全局 Maven 版本。
- 建立按业务能力划分的包结构，并用 `package-info.java` 记录边界。

## 2. 本地基础设施

- 在仓库根目录创建 `docker-compose.yml`，运行 MySQL 8.4。
- 创建 `.env.example`，只提供开发变量名称和安全说明。
- 配置 local、test、prod 环境以及 UTF-8、时区和数据库连接。
- 创建 Flyway 初始迁移，验证版本化数据库初始化链路。

## 3. API 基础能力

- 创建 `GET /api/v1/system/ping`。
- 创建统一的 API 错误结构及全局异常处理。
- 配置只允许受信本地前端来源的 CORS。
- 配置 Spring Security：ping 和健康检查公开，其他接口默认要求认证。
- Actuator 仅公开必要健康信息。

## 4. 前端连接

- 新增统一 API 配置和连接状态脚本。
- 官网以非阻塞方式检查后端状态；后端未启动时不影响现有官网和营养记录功能。
- 不在本阶段迁移 localStorage 中的饮食数据。

## 5. 验证

- 使用 Maven Wrapper执行单元和集成测试。
- 验证 ping、CORS、安全默认规则、统一错误和 Flyway 迁移。
- 使用 Docker MySQL 启动后端，实际请求 ping 与 Actuator 健康接口。
- 验证原官网与营养记录页继续返回 200 且无脚本语法错误。

## 6. 提交

- 检查不包含密码、令牌和临时文件。
- 提交完整框架并推送到 `origin/main`。
