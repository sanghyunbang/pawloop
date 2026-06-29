package com.heattrip.heat_trip_backend.S3;

import java.io.InputStream;
import java.net.URL;
import java.time.Duration;
import java.util.Collection;
import org.springframework.web.multipart.MultipartFile;

/**
 * 저장소 추상화 인터페이스.
 * - S3 외 로컬/GCS 등으로 구현 교체 가능.
 */
public interface FileStorage {

    // C: Create
    StoredObject upload(MultipartFile file, UploadRequest req);

    // R: Read
    String publicUrl(String key);                // 공개 CDN 조합 URL
    boolean exists(String key);                  // 존재 확인
    byte[] downloadBytes(String key);            // 소용량 다운로드
    InputStream openStream(String key);          // 스트리밍 다운로드
    URL presignedUrl(String key, Duration ttl);  // 비공개 접근용 임시 URL

    // U: Update (새 업로드 후 구 키 삭제)
    StoredObject replace(String oldKey, MultipartFile file, UploadRequest req);

    // D: Delete
    void delete(String key);
    void deleteAll(Collection<String> keys);
}
