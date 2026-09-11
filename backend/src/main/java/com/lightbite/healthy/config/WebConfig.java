package com.lightbite.healthy.config;

import com.lightbite.healthy.privacy.HealthAuthorizationInterceptor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {
    private final HealthAuthorizationInterceptor healthAuthorization;

    public WebConfig(HealthAuthorizationInterceptor healthAuthorization) {
        this.healthAuthorization = healthAuthorization;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(healthAuthorization);
    }
}
