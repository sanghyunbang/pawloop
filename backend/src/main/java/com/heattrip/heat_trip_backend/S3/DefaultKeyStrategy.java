package com.heattrip.heat_trip_backend.S3;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

/**
 * 기본 키 규칙:
 *   {prefix}/{ownerId}/{yyyy}/{MM}/{optional subPath/}{UUID}_{sanitizedName}
 */
@Component
public class DefaultKeyStrategy implements KeyStrategy {

    private static final DateTimeFormatter YYYY = DateTimeFormatter.ofPattern("yyyy");
    private static final DateTimeFormatter MM   = DateTimeFormatter.ofPattern("MM");

    @Override
    public String buildKey(MultipartFile file, UploadRequest req) {
        var now = LocalDate.now();
        String yyyy = now.format(YYYY);
        String mm   = now.format(MM);
        String safe = sanitize(file.getOriginalFilename());
        String uuid = UUID.randomUUID().toString();
        String sub  = (req.subPath()==null || req.subPath().isBlank())
            ? ""
            : req.subPath().replaceAll("^/+", "").replaceAll("/+$", "") + "/";

        return req.category().prefix + "/" + req.ownerId() + "/" + yyyy + "/" + mm + "/"
             + sub + uuid + "_" + safe;
    }

    private String sanitize(String original) {
        if (original == null || original.isBlank()) return "unnamed";
        int dot = original.lastIndexOf('.');
        String base = (dot > 0 ? original.substring(0, dot) : original);
        String ext  = (dot > 0 ? original.substring(dot) : "");
        base = base.replaceAll("[^a-zA-Z0-9-_\\.]", "_");
        return base + ext.toLowerCase();
    }
}
