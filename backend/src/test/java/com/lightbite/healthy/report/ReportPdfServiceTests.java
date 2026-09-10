package com.lightbite.healthy.report;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.ByteArrayOutputStream;
import java.time.LocalDate;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class ReportPdfServiceTests {
    @Autowired JdbcTemplate jdbc;
    @Autowired ReportService reports;
    @Autowired ReportPdfService pdf;

    @BeforeEach
    void setUp() {
        jdbc.update("DELETE FROM health_report_sources"); jdbc.update("DELETE FROM health_reports");
        jdbc.update("MERGE INTO users (id,phone,display_name,status) KEY(id) VALUES ('pdf-user','13000000971','中文用户','ACTIVE')");
        jdbc.update("MERGE INTO health_profiles (user_id,current_step,completed) KEY(user_id) VALUES ('pdf-user',7,TRUE)");
    }

    @Test
    void streamsExtractableChineseWithEmbeddedFontAndNoSensitiveFields() throws Exception {
        var report = reports.generate("pdf-user", "pdf-report",
                new ReportDtos.GenerateRequest("DAILY", LocalDate.of(2026, 9, 10), "Asia/Shanghai"));
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        pdf.write("pdf-user", report.id(), output);
        byte[] bytes = output.toByteArray();
        assertThat(bytes).startsWith("%PDF".getBytes()).hasSizeGreaterThan(1000);
        try (PDDocument document = Loader.loadPDF(bytes)) {
            assertThat(document.getNumberOfPages()).isPositive();
            String text = new PDFTextStripper().getText(document);
            assertThat(text).contains("健康报告", "中文用户", "六个核心栏目", "不构成医疗诊断")
                    .doesNotContain("13000000971", "Idempotency-Key", "inputHash", "riskBlocked");
            boolean embedded = false;
            for (var name : document.getPage(0).getResources().getFontNames())
                embedded |= document.getPage(0).getResources().getFont(name).isEmbedded();
            assertThat(embedded).isTrue();
        }
    }
}
