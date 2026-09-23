package com.lightbite.healthy.privacy;

import com.lightbite.healthy.common.api.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
public class HealthAuthorizationInterceptor implements HandlerInterceptor {
    private static final List<String> HEALTH_PATHS = List.of(
            "/api/v1/profile", "/api/v1/plans", "/api/v1/nutrition", "/api/v1/hydration",
            "/api/v1/activity", "/api/v1/sleep", "/api/v1/tasks", "/api/v1/today", "/api/v1/reports"
    );
    private final JdbcTemplate jdbc;

    public HealthAuthorizationInterceptor(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        Authentication authentication = (Authentication) request.getUserPrincipal();
        if (authentication == null || !isHealthPath(request.getRequestURI())) return true;
        List<Boolean> permissions = jdbc.query("SELECT health_data_authorized FROM health_permissions WHERE user_id=?",
                (rs, row) -> rs.getBoolean(1), authentication.getName());
        if (permissions.isEmpty()) {
            throw new ApiException(HttpStatus.LOCKED, "HEALTH_AUTHORIZATION_REQUIRED",
                    "请先同意健康数据授权后使用此功能");
        }
        if (!permissions.get(0)) {
            throw new ApiException(HttpStatus.LOCKED, "HEALTH_AUTHORIZATION_WITHDRAWN",
                    "健康数据授权已撤回，请重新同意后使用此功能");
        }
        return true;
    }

    private boolean isHealthPath(String path) {
        return HEALTH_PATHS.stream().anyMatch(path::startsWith);
    }
}
