package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.lightbite.healthy.datarights.DataExportService;
import java.nio.file.Files;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.encryption.InvalidPasswordException;
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
class DataExportIntegrationTests {
    private static final String PHONE = "13600003001";
    private static final String PASSWORD = "Healthy-导出-2026";
    @Autowired WebApplicationContext context;
    @Autowired DataExportService exports;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() { mockMvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build(); }

    @Test
    void createsChineseEncryptedPdfWithMaskedPhoneAndOwnedDownload() throws Exception {
        String token = register();
        String code = sendCode("DATA_EXPORT");
        String response = mockMvc.perform(post("/api/v1/data-exports").header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"code\":\"%s\",\"password\":\"%s\"}".formatted(code, PASSWORD)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("READY"))
                .andExpect(jsonPath("$.expiresAt").isNotEmpty())
                .andReturn().getResponse().getContentAsString();
        String id = JsonPath.read(response, "$.id");
        byte[] bytes = Files.readAllBytes(exports.download(userIdForToken(token), id));
        assertThat(new String(bytes, java.nio.charset.StandardCharsets.ISO_8859_1)).doesNotContain(PHONE);
        assertThatThrownBy(() -> Loader.loadPDF(bytes)).isInstanceOf(InvalidPasswordException.class);
        try (PDDocument document = Loader.loadPDF(bytes, PASSWORD)) {
            assertThat(document.isEncrypted()).isTrue();
            assertThat(document.getNumberOfPages()).isPositive();
        }
        mockMvc.perform(get("/api/v1/data-exports/" + id + "/download")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    private String register() throws Exception {
        String code = sendCode("LOGIN");
        String body = mockMvc.perform(post("/api/v1/auth/sms/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"code\":\"%s\",\"deviceName\":\"导出测试手机\",\"password\":\"Healthy123\",\"acceptedTerms\":true}"
                                .formatted(PHONE, code)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.accessToken");
    }

    private String sendCode(String purpose) throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"purpose\":\"%s\"}".formatted(PHONE, purpose)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.debugCode");
    }

    private String userIdForToken(String token) {
        return ((com.lightbite.healthy.auth.AuthService) context.getBean(com.lightbite.healthy.auth.AuthService.class))
                .validateAccessToken(token).userId();
    }
}
