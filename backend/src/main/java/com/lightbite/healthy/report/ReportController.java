package com.lightbite.healthy.report;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

@RestController
@RequestMapping("/api/v1/reports")
public class ReportController {
    private final ReportService service; private final ReportPdfService pdf;
    public ReportController(ReportService service, ReportPdfService pdf) { this.service = service; this.pdf = pdf; }

    @PostMapping
    ReportDtos.ReportResponse generate(Authentication auth,
            @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @RequestBody(required = false) ReportDtos.GenerateRequest request) {
        return service.generate(auth.getName(), key, request);
    }

    @GetMapping
    List<ReportDtos.ReportSummary> list(Authentication auth,
            @RequestParam(required = false) String type, @RequestParam(required = false) LocalDate date,
            @RequestParam(required = false) String timezone) {
        return service.list(auth.getName(), type, date, timezone);
    }

    @GetMapping("/{id}")
    ReportDtos.ReportResponse detail(Authentication auth, @PathVariable String id) { return service.detail(auth.getName(), id); }

    @GetMapping("/{id}/sources")
    List<ReportDtos.SourceResponse> sources(Authentication auth, @PathVariable String id,
            @RequestParam(required = false) String section, @RequestParam(required = false) String metric) {
        return service.sources(auth.getName(), id, section, metric);
    }

    @GetMapping(value = "/{id}/pdf", produces = MediaType.APPLICATION_PDF_VALUE)
    ResponseEntity<StreamingResponseBody> pdf(Authentication auth, @PathVariable String id) {
        ReportDtos.ReportResponse report = service.detail(auth.getName(), id);
        String name = "健康报告-" + report.periodStart() + "-第" + report.version() + "版.pdf";
        String encoded = URLEncoder.encode(name, StandardCharsets.UTF_8).replace("+", "%20");
        StreamingResponseBody body = output -> pdf.write(auth.getName(), id, output);
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_PDF)
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=health-report.pdf; filename*=UTF-8''" + encoded)
                .header("X-Content-Type-Options", "nosniff").body(body);
    }

    @DeleteMapping("/{id}")
    ReportDtos.DeleteResponse delete(Authentication auth, @PathVariable String id) { return service.delete(auth.getName(), id); }
}
