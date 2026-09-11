package com.lightbite.healthy.auth;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class BearerTokenFilter extends OncePerRequestFilter {

    private final AuthService authService;

    public BearerTokenFilter(AuthService authService) {
        this.authService = authService;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            String token = header.substring(7);
            AuthService.SessionIdentity identity = authService.validateAccessToken(token);
            if (identity != null) {
                if ("DELETION_PENDING".equals(identity.accountStatus()) && !deletionPath(request.getRequestURI())) {
                    response.setStatus(423);
                    response.setContentType("application/json;charset=UTF-8");
                    response.getOutputStream().write(
                            "{\"code\":\"ACCOUNT_DELETION_PENDING\",\"message\":\"账户正在注销处理中\"}"
                                    .getBytes(StandardCharsets.UTF_8));
                    return;
                }
                SecurityContextHolder.getContext().setAuthentication(
                        new UsernamePasswordAuthenticationToken(identity.userId(), token, List.of())
                );
            }
        }
        filterChain.doFilter(request, response);
    }

    private boolean deletionPath(String path) {
        return path.startsWith("/api/v1/account/deletion") || path.equals("/api/v1/auth/logout");
    }
}
