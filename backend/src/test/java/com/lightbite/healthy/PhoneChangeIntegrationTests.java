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
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

@SpringBootTest
@ActiveProfiles("test")
class PhoneChangeIntegrationTests {
    private static final String OLD_PHONE = "13600001001";
    private static final String NEW_PHONE = "13600001002";
    @Autowired WebApplicationContext context;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
    }

    @Test
    void changeRequiresBothPurposeBoundCodesAndKeepsOnlyCurrentDevice() throws Exception {
        String firstToken = register(OLD_PHONE, "主设备");
        passwordLogin(OLD_PHONE, "备用设备");

        String wrongPurposeCode = sendCode(OLD_PHONE, "ACCOUNT_DELETE");
        String newCode = sendCode(NEW_PHONE, "PHONE_NEW");
        mockMvc.perform(post("/api/v1/account/phone/change")
                        .header("Authorization", "Bearer " + firstToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"oldCode\":\"%s\",\"newPhone\":\"%s\",\"newCode\":\"%s\"}"
                                .formatted(wrongPurposeCode, NEW_PHONE, newCode)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("INVALID_VERIFICATION_CODE"));

        String oldCode = sendCode(OLD_PHONE, "PHONE_OLD");
        mockMvc.perform(post("/api/v1/account/phone/change")
                        .header("Authorization", "Bearer " + firstToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"oldCode\":\"%s\",\"newPhone\":\"%s\",\"newCode\":\"%s\"}"
                                .formatted(oldCode, NEW_PHONE, newCode)))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/v1/account").header("Authorization", "Bearer " + firstToken))
                .andExpect(status().isOk()).andExpect(jsonPath("$.maskedPhone").value("136****1002"));
        mockMvc.perform(get("/api/v1/account/devices").header("Authorization", "Bearer " + firstToken))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1));
        mockMvc.perform(post("/api/v1/auth/password/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"password\":\"Healthy123\",\"deviceName\":\"旧号码设备\"}"
                                .formatted(OLD_PHONE)))
                .andExpect(status().isUnauthorized());
        passwordLogin(NEW_PHONE, "新号码设备");
    }

    private String register(String phone, String device) throws Exception {
        String code = sendCode(phone, "LOGIN");
        String body = mockMvc.perform(post("/api/v1/auth/sms/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"code\":\"%s\",\"deviceName\":\"%s\","
                                .formatted(phone, code, device)
                                + "\"password\":\"Healthy123\",\"acceptedTerms\":true}"))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.accessToken");
    }

    private String passwordLogin(String phone, String device) throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/password/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"password\":\"Healthy123\",\"deviceName\":\"%s\"}"
                                .formatted(phone, device)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.accessToken");
    }

    private String sendCode(String phone, String purpose) throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"purpose\":\"%s\"}".formatted(phone, purpose)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.debugCode");
    }
}
