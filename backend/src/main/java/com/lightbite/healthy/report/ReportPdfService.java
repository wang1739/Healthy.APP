package com.lightbite.healthy.report;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDType0Font;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;
import tools.jackson.databind.JsonNode;

@Service
public class ReportPdfService {
    private final ReportService reports;

    public ReportPdfService(ReportService reports) {
        this.reports = reports;
    }

    public void write(String userId, String reportId, OutputStream output) throws IOException {
        ReportService.Row row = reports.owned(userId, reportId);
        try (PDDocument document = new PDDocument();
             InputStream input = new ClassPathResource("fonts/LXGWWenKai-Regular.ttf").getInputStream()) {
            PDType0Font font = PDType0Font.load(document, input, true);
            PdfWriter writer = new PdfWriter(document, font);
            JsonNode snapshot = row.snapshot();
            writer.title("健康报告");
            writer.line("用户：" + snapshot.path("displayName").asText("用户"));
            writer.line("周期：" + row.start() + " 至 " + row.end() + "（" + status(row.status()) + "）");
            writer.line("版本：第 " + row.version() + " 版");
            writer.line("生成时间：" + row.createdAt());
            writer.heading("本期结论");
            writer.line(snapshot.path("conclusion").asText("暂无结论"));
            writer.heading("关键数字");
            for (JsonNode metric : snapshot.path("keyMetrics"))
                writer.line(metric.path("label").asText() + "：" + metric.path("value").asText() + metric.path("unit").asText());
            writer.heading("六个核心栏目");
            for (JsonNode section : snapshot.path("sections")) {
                writer.subheading(section.path("title").asText() + " · " + sufficiency(section.path("sufficiency").asText()));
                writer.line(section.path("reason").asText());
                writer.line("记录：" + section.path("recordDays").asText("0") + " / " + section.path("expectedDays").asText("0"));
            }
            writer.heading("规则建议");
            for (JsonNode advice : snapshot.path("advice")) {
                writer.subheading(advice.path("title").asText());
                writer.line(advice.path("description").asText());
            }
            writer.heading("说明");
            writer.line(snapshot.path("disclaimer").asText("本报告仅用于健康记录回顾，不构成医疗诊断或治疗建议。"));
            writer.close();
            document.save(output);
        }
    }

    private static String status(String value) { return "COMPLETE".equals(value) ? "已完成" : "进行中"; }
    private static String sufficiency(String value) { return switch (value) { case "SUFFICIENT" -> "数据充分"; case "LIMITED" -> "数据有限"; case "NOT_APPLICABLE" -> "不适用"; default -> "暂无记录"; }; }

    private static final class PdfWriter {
        private final PDDocument document; private final PDType0Font font;
        private PDPageContentStream stream; private float y;
        PdfWriter(PDDocument document, PDType0Font font) throws IOException { this.document = document; this.font = font; page(); }
        void title(String text) throws IOException { text(text, 20, 26); }
        void heading(String text) throws IOException { ensure(36); text(text, 15, 22); }
        void subheading(String text) throws IOException { ensure(26); text(text, 12, 18); }
        void line(String text) throws IOException { for (String line : wrap(text == null ? "" : text, 10, 480)) { ensure(18); text(line, 10, 16); } }
        void close() throws IOException { if (stream != null) stream.close(); }
        private void page() throws IOException { if (stream != null) stream.close(); PDPage page = new PDPage(PDRectangle.A4); document.addPage(page); stream = new PDPageContentStream(document, page); y = 800; }
        private void ensure(float height) throws IOException { if (y - height < 45) page(); }
        private void text(String value, float size, float leading) throws IOException { stream.beginText(); stream.setFont(font, size); stream.newLineAtOffset(55, y); stream.showText(value); stream.endText(); y -= leading; }
        private List<String> wrap(String text, float size, float width) throws IOException {
            List<String> lines = new ArrayList<>(); StringBuilder line = new StringBuilder();
            for (int i = 0; i < text.length();) { int cp = text.codePointAt(i); String next = new String(Character.toChars(cp));
                if (!line.isEmpty() && font.getStringWidth(line + next) / 1000f * size > width) { lines.add(line.toString()); line.setLength(0); }
                line.append(next); i += Character.charCount(cp); }
            lines.add(line.toString()); return lines;
        }
    }
}
