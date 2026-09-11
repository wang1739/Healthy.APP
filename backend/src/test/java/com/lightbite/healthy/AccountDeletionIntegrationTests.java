package com.lightbite.healthy;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
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

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

@SpringBootTest
@ActiveProfiles("test")
class AccountDeletionIntegrationTests {
    private static final String PHONE = "13600002001";
    @Autowired WebApplicationContext context;
    @Autowired JdbcTemplate jdbc;
    @Autowired com.lightbite.healthy.account.AccountDeletionCleanup cleanup;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
    }

    @Test
    void pendingAccountGetsRestrictedSessionAndCanRecoverWithinCoolingOffPeriod() throws Exception {
        String normalToken = register(PHONE);
        String deleteCode = sendCode(PHONE, "ACCOUNT_DELETE");
        mockMvc.perform(post("/api/v1/account/deletion").header("Authorization", "Bearer " + normalToken)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"code\":\"%s\"}".formatted(deleteCode)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("注销处理中"))
                .andExpect(jsonPath("$.remainingSeconds").isNumber());

        mockMvc.perform(get("/api/v1/account/deletion").header("Authorization", "Bearer " + normalToken))
                .andExpect(status().isUnauthorized());

        String pendingLogin = passwordLogin(PHONE);
        String restrictedToken = JsonPath.read(pendingLogin, "$.accessToken");
        org.assertj.core.api.Assertions.assertThat((String) JsonPath.read(pendingLogin, "$.accountStatus"))
                .isEqualTo("DELETION_PENDING");
        mockMvc.perform(get("/api/v1/account").header("Authorization", "Bearer " + restrictedToken))
                .andExpect(status().isLocked())
                .andExpect(jsonPath("$.message").value("账户正在注销处理中"));
        mockMvc.perform(get("/api/v1/account/deletion").header("Authorization", "Bearer " + restrictedToken))
                .andExpect(status().isOk()).andExpect(jsonPath("$.remainingSeconds").isNumber());

        String recoverCode = sendCode(PHONE, "ACCOUNT_RECOVER");
        mockMvc.perform(post("/api/v1/account/deletion/recover")
                        .header("Authorization", "Bearer " + restrictedToken)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"code\":\"%s\"}".formatted(recoverCode)))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/account").header("Authorization", "Bearer " + restrictedToken))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ACTIVE"));
    }

    @Test
    void dueCleanupIsIdempotentAndReleasesPhone() throws Exception {
        String phone = "13600002002";
        String token = register(phone);
        String deleteCode = sendCode(phone, "ACCOUNT_DELETE");
        mockMvc.perform(post("/api/v1/account/deletion").header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"code\":\"%s\"}".formatted(deleteCode)))
                .andExpect(status().isOk());
        jdbc.update("UPDATE account_deletion_requests SET scheduled_for=DATEADD('DAY',-1,CURRENT_TIMESTAMP) "
                + "WHERE user_id=(SELECT id FROM users WHERE phone=?) AND status='PENDING'", phone);

        cleanup.cleanDueAccounts();
        cleanup.cleanDueAccounts();

        Integer oldPhone = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE phone=?", Integer.class, phone);
        Integer completed = jdbc.queryForObject("SELECT COUNT(*) FROM account_deletion_requests "
                + "WHERE status='COMPLETED'", Integer.class);
        org.assertj.core.api.Assertions.assertThat(oldPhone).isZero();
        org.assertj.core.api.Assertions.assertThat(completed).isPositive();
    }

    private String register(String phone) throws Exception {
        String code = sendCode(phone, "LOGIN");
        String body = mockMvc.perform(post("/api/v1/auth/sms/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"code\":\"%s\",\"deviceName\":\"注销测试手机\","
                                .formatted(phone, code)
                                + "\"password\":\"Healthy123\",\"acceptedTerms\":true}"))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.accessToken");
    }

    private String passwordLogin(String phone) throws Exception {
        return mockMvc.perform(post("/api/v1/auth/password/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"password\":\"Healthy123\",\"deviceName\":\"恢复设备\"}"
                                .formatted(phone)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
    }

    private String sendCode(String phone, String purpose) throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"purpose\":\"%s\"}".formatted(phone, purpose)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.debugCode");
    }
}
