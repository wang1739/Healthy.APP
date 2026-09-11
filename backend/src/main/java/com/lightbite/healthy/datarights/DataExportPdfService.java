package com.lightbite.healthy.datarights;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.encryption.AccessPermission;
import org.apache.pdfbox.pdmodel.encryption.StandardProtectionPolicy;
import org.apache.pdfbox.pdmodel.font.PDType0Font;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

@Service
public class DataExportPdfService {
    public void write(List<Section> sections, char[] password, OutputStream output) throws IOException {
        try (PDDocument document = new PDDocument();
             InputStream fontInput = new ClassPathResource("fonts/LXGWWenKai-Regular.ttf").getInputStream()) {
            PDType0Font font = PDType0Font.load(document, fontInput, true);
            Writer writer = new Writer(document, font);
            writer.title("轻食记个人数据导出");
            for (Section section : sections) {
                writer.heading(section.title());
                for (String line : section.lines()) writer.line(line);
            }
            writer.line("本文件仅供账户本人查阅，请妥善保管。");
            writer.close();
            AccessPermission permission = new AccessPermission();
            permission.setCanModify(false);
            permission.setCanExtractContent(false);
            StandardProtectionPolicy policy = new StandardProtectionPolicy(randomOwnerPassword(), new String(password), permission);
            policy.setEncryptionKeyLength(256);
            document.protect(policy);
            document.save(output);
        }
    }

    private String randomOwnerPassword() {
        return java.util.UUID.randomUUID().toString();
    }

    public record Section(String title, List<String> lines) {}

    private static final class Writer {
        private final PDDocument document; private final PDType0Font font;
        private PDPageContentStream stream; private float y;
        Writer(PDDocument document, PDType0Font font) throws IOException { this.document = document; this.font = font; page(); }
        void title(String text) throws IOException { text(text, 20, 28); }
        void heading(String text) throws IOException { ensure(32); text(text, 14, 22); }
        void line(String text) throws IOException { for (String line : wrap(text == null ? "" : text, 10, 480)) { ensure(18); text(line, 10, 16); } }
        void close() throws IOException { if (stream != null) stream.close(); }
        private void page() throws IOException { if (stream != null) stream.close(); PDPage page = new PDPage(PDRectangle.A4); document.addPage(page); stream = new PDPageContentStream(document, page); y = 800; }
        private void ensure(float height) throws IOException { if (y - height < 45) page(); }
        private void text(String value, float size, float leading) throws IOException { stream.beginText(); stream.setFont(font, size); stream.newLineAtOffset(55, y); stream.showText(value); stream.endText(); y -= leading; }
        private List<String> wrap(String text, float size, float width) throws IOException { List<String> lines = new ArrayList<>(); StringBuilder line = new StringBuilder(); for (int i = 0; i < text.length();) { int cp = text.codePointAt(i); String next = new String(Character.toChars(cp)); if (!line.isEmpty() && font.getStringWidth(line + next) / 1000f * size > width) { lines.add(line.toString()); line.setLength(0); } line.append(next); i += Character.charCount(cp); } lines.add(line.toString()); return lines; }
    }
}
