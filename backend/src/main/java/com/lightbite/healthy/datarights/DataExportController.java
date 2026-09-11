package com.lightbite.healthy.datarights;

import jakarta.validation.Valid;
import java.io.IOException;
import java.nio.file.Files;
import java.util.List;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/data-exports")
public class DataExportController {
    private final DataExportService exports;
    public DataExportController(DataExportService exports) { this.exports = exports; }

    @PostMapping
    DataExportDtos.Job create(@Valid @RequestBody DataExportDtos.Request request, Authentication authentication) {
        return exports.create(authentication.getName(), request);
    }

    @GetMapping
    List<DataExportDtos.Job> list(Authentication authentication) { return exports.list(authentication.getName()); }

    @GetMapping(value = "/{id}/download", produces = MediaType.APPLICATION_PDF_VALUE)
    ResponseEntity<InputStreamResource> download(@PathVariable String id, Authentication authentication) throws IOException {
        var path = exports.download(authentication.getName(), id);
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_PDF)
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=healthy-data-export.pdf")
                .body(new InputStreamResource(Files.newInputStream(path)));
    }
}
