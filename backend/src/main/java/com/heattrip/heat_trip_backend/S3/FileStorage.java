package com.heattrip.heat_trip_backend.S3;

import java.io.InputStream;
import java.net.URL;
import java.time.Duration;
import java.util.Collection;
import java.util.Optional;
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

    /**
     * HEAD — 객체가 있으면 크기·형식, 없으면 비어 있다. 본문을 안 받는다 (#429).
     *
     * <p>앱이 S3 에 직접 올린 영상을 서버가 확인하는 유일한 길이다. 서명 PUT 은 크기 조건을
     * 못 걸어서, "올렸다" 는 앱의 말이 아니라 이 답으로 {@code ready} 를 정한다.
     */
    Optional<StoredObject> stat(String key);

    // C: 앱이 직접 올리는 길 (#429)
    /**
     * 서명 PUT 발급 — 앱이 S3 에 직접 올릴 때. 키는 저장소가 정한다.
     *
     * <p>서명은 네트워크를 안 탄다. 이 호출이 성공했다고 파일이 있는 것이 아니다 — 있는지는
     * {@link #stat} 이 답한다.
     *
     * @param fileName    키 끝에 붙는 이름. 확장자가 여기서 온다
     * @param contentType 서명에 묶인다 — 앱은 <b>같은</b> {@code Content-Type} 으로 PUT 해야 한다
     * @param ttl         이 시간이 지나면 S3 가 403 을 준다
     */
    PresignedUpload presignedPut(UploadRequest req, String fileName, String contentType, Duration ttl);

    // U: Update (새 업로드 후 구 키 삭제)
    StoredObject replace(String oldKey, MultipartFile file, UploadRequest req);

    // D: Delete
    void delete(String key);
    void deleteAll(Collection<String> keys);
}
