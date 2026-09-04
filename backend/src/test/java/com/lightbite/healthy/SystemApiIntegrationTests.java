package com.lightbite.healthy;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class SystemApiIntegrationTests {

    @Autowired
    private WebApplicationContext applicationContext;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @org.springframework.beans.factory.annotation.Value("${local.server.port}")
    private int serverPort;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext)
                .apply(springSecurity())
                .build();
    }

    @Test
    void pingIsPublicAndReturnsServiceStatus() throws Exception {
        mockMvc.perform(get("/api/v1/system/ping"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ok"))
                .andExpect(jsonPath("$.service").value("healthy-backend"))
                .andExpect(jsonPath("$.timestamp").isNotEmpty());
    }

    @Test
    void pingWorksThroughRealHttpServer() throws Exception {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create("http://localhost:" + serverPort + "/api/v1/system/ping"))
                .GET()
                .build();

        HttpResponse<String> response = HttpClient.newHttpClient()
                .send(request, HttpResponse.BodyHandlers.ofString());

        org.assertj.core.api.Assertions.assertThat(response.statusCode()).isEqualTo(200);
        org.assertj.core.api.Assertions.assertThat(response.body())
                .contains("\"status\":\"ok\"")
                .contains("\"service\":\"healthy-backend\"");
    }

    @Test
    void protectedPathsReturnUnifiedUnauthorizedResponse() throws Exception {
        mockMvc.perform(get("/api/v1/profile"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"))
                .andExpect(jsonPath("$.message").value("请先登录后再访问"))
                .andExpect(jsonPath("$.path").value("/api/v1/profile"));
    }

    @Test
    void localFrontendOriginIsAllowed() throws Exception {
        mockMvc.perform(get("/api/v1/system/ping")
                        .header(HttpHeaders.ORIGIN, "http://localhost:4173"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:4173"))
                .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_CREDENTIALS, "true"));
    }

    @Test
    void flywayCreatesApplicationMetadata() {
        Integer count = jdbcTemplate.queryForObject(
                "select count(*) from app_metadata where metadata_key = 'schema_version'",
                Integer.class
        );

        org.assertj.core.api.Assertions.assertThat(count).isEqualTo(1);
    }
}
