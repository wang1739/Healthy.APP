package com.lightbite.healthy;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

@SpringBootTest
@ActiveProfiles("test")
class PrivacyIntegrationTests {
    private static final String USER = "privacy-user";
    @Autowired WebApplicationContext context;
    @Autowired JdbcTemplate jdbc;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
        jdbc.update("DELETE FROM consent_events WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_permissions WHERE user_id=?", USER);
        jdbc.update("DELETE FROM users WHERE id=?", USER);
        jdbc.update("INSERT INTO users (id,phone,status) VALUES (?,'13000009982','ACTIVE')", USER);
    }

    @Test
    void healthAuthorizationIsIndependentAndCanBeWithdrawnAndAcceptedAgain() throws Exception {
        mockMvc.perform(get("/api/v1/privacy").with(user(USER)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.healthAuthorized").value(false))
                .andExpect(jsonPath("$.latestDocuments.length()").value(2));

        mockMvc.perform(post("/api/v1/privacy/consents").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON).content("""
                                {"documentType":"HEALTH_DATA_AUTHORIZATION","version":"2026-09"}
                                """))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/privacy").with(user(USER)))
                .andExpect(jsonPath("$.healthAuthorized").value(true))
                .andExpect(jsonPath("$.acceptedHealthVersion").value("2026-09"));

        mockMvc.perform(post("/api/v1/privacy/health-authorization/withdraw").with(user(USER)))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/privacy").with(user(USER)))
                .andExpect(jsonPath("$.healthAuthorized").value(false))
                .andExpect(jsonPath("$.history[0].action").value("WITHDRAW"));
        mockMvc.perform(get("/api/v1/profile/completeness").with(user(USER)))
                .andExpect(status().isLocked())
                .andExpect(jsonPath("$.message").value("健康数据授权已撤回，请重新同意后使用此功能"));
        mockMvc.perform(get("/api/v1/account").with(user(USER)))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/v1/privacy/consents").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON).content("""
                                {"documentType":"HEALTH_DATA_AUTHORIZATION","version":"2026-09"}
                                """))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/profile/completeness").with(user(USER)))
                .andExpect(status().isOk());
    }
}
