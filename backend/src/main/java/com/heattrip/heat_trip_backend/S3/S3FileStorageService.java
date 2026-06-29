package com.heattrip.heat_trip_backend.S3;

import com.amazonaws.HttpMethod;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.model.*;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.time.Duration;
import java.util.Collection;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/**
 * FileStorage의 S3 구현체.
 *
 * 설계 포인트:
 *  - (A) 캐시 전략: immutable + 1년(31536000초)  [1]
 *  - (B) 키 전략: UUID/버전 분리로 캐시 무효화 비용 ↓   [2]
 *  - (C) 공개 URL: CloudFront 도메인 + 키 매핑        [3]
 *  - (D) 접근 제어: ACL 비권장(= Bucket Owner Enforced) [4]
 *  - (E) 스트리밍과 리소스 해제 책임 명확화            [5]
 */
@Service
public class S3FileStorageService implements FileStorage {

    private final AmazonS3 s3;              // AWS SDK v1 S3 클라이언트(스레드 세이프)
    private final KeyStrategy keyStrategy;  // 업로드 키 생성 규칙(경로, 파일명 등)
    private final UploadValidator validator;// 파일 크기/MIME/확장자 검증

    @Value("${cloud.aws.s3.bucket}")
    private String bucket;

    @Value("${cloud.aws.cloudfront.domain}")
    private String cloudFrontDomain;

    public S3FileStorageService(
            AmazonS3 s3,
            KeyStrategy keyStrategy,
            UploadValidator validator
    ) {
        this.s3 = s3;
        this.keyStrategy = keyStrategy;
        this.validator = validator;
    }

    /**
     * 신규 업로드.
     * 1) 입력 검증 → 2) 키 생성 → 3) 메타데이터 세팅(길이/타입/캐시) → 4) putObject
     * 성공 시 StoredObject(키/공개URL/MIME/크기) 반환.
     */
    @Override
    public StoredObject upload(MultipartFile file, UploadRequest req) {
        // (1) 업로드 전 파일/도메인 규칙 검증
        validator.validate(file, req); // 예: 최대 용량, 허용 MIME/확장자, 경로 제약 등 [6]

        // (2) 키 생성: 경로 규칙 + UUID 파일명 등 (캐시 무효화를 파일명 교체로 해결) [2]
        String key = keyStrategy.buildKey(file, req);

        // (3) S3 오브젝트 메타데이터 준비
        ObjectMetadata meta = new ObjectMetadata();
        meta.setContentLength(file.getSize());           // SDK v1은 길이를 아는 편이 안전 [7]
        meta.setContentType(file.getContentType());      // 브라우저/다운로드 동작에 영향
        meta.setCacheControl("public, max-age=31536000, immutable"); // (A) 캐시 정책 [1]

        // (4) 스트리밍 업로드 (try-with-resources로 InputStream 자동 close)
        try (var in = file.getInputStream()) {
            // ACL은 설정하지 않음: Bucket owner enforced 권장 [4]
            s3.putObject(new PutObjectRequest(bucket, key, in, meta));
        } catch (IOException e) {
            // checked → unchecked 변환: 서비스 레이어에선 런타임 예외로 전파
            throw new RuntimeException("S3 업로드 실패", e);
        }

        // (5) 응답 객체 구성: 키, CDN 공개 URL, MIME, 크기
        return new StoredObject(
                key,
                UrlMapper.cfUrl(cloudFrontDomain, key), // (C) CloudFront 매핑 [3]
                file.getContentType(),
                file.getSize()
        );
    }

    /** 키로 공개 URL(CloudFront) 생성. 객체 권한과 무관한 '표시용 경로' */
    @Override
    public String publicUrl(String key) {
        return UrlMapper.cfUrl(cloudFrontDomain, key); // 도메인/슬래시/인코딩 처리 주의 [3]
    }

    /** S3 상의 객체 존재 여부 확인 */
    @Override
    public boolean exists(String key) {
        return s3.doesObjectExist(bucket, key);
    }

    /**
     * 소용량 다운로드: 전부 메모리로 읽어 byte[] 반환.
     * 대용량의 경우 openStream 사용 권장.
     */
    @Override
    public byte[] downloadBytes(String key) {
        try (
            S3Object obj = s3.getObject(bucket, key);             // close 필요
            S3ObjectInputStream in = obj.getObjectContent();      // close 필요
            ByteArrayOutputStream out = new ByteArrayOutputStream()
        ) {
            in.transferTo(out);                                   // Java 9+ 편의
            return out.toByteArray();
        } catch (IOException e) {
            throw new RuntimeException("S3 다운로드 실패", e);
        }
    }

    /**
     * 스트리밍 다운로드: 호출자가 반드시 close 해야 함.
     * 컨트롤러/서비스 바깥으로 스트림을 넘길 때는 try-with-resources 범위를
     * 호출자 쪽에 두도록 가이드가 필요. [5]
     */
    @Override
    public InputStream openStream(String key) {
        // 반환된 S3ObjectInputStream은 호출자가 꼭 close 해야 네트워크 커넥션이 회수됨.
        return s3.getObject(bucket, key).getObjectContent();
    }

    /**
     * 서명된(프리사인드) 임시 URL 생성: 비공개 객체 접근 허용.
     * TTL 경과 시 자동 만료. HTTP 메서드는 GET. [8]
     */
    @Override
    public URL presignedUrl(String key, Duration ttl) {
        var exp = new java.util.Date(System.currentTimeMillis() + ttl.toMillis());
        return s3.generatePresignedUrl(
                new GeneratePresignedUrlRequest(bucket, key)
                        .withMethod(HttpMethod.GET)
                        .withExpiration(exp)
        );
    }

    /**
     * 교체 업로드: 새 업로드 완료 후 이전 키 삭제(실패해도 진행).
     * - 트래픽/캐시 관점: 새 키를 발급하면 CDN 캐시 충돌 없이 안전. [2]
     */
    @Override
    public StoredObject replace(String oldKey, MultipartFile file, UploadRequest req) {
        StoredObject neo = upload(file, req);
        if (oldKey != null && !oldKey.isBlank()) {
            try {
                delete(oldKey);
            } catch (Exception ignored) {
                // 로깅 고려: 삭제 실패는 다운스트림 영향 적으므로 무시 가능하나 추적은 필요 [9]
            }
        }
        return neo;
    }

    /** 단일 삭제 */
    @Override
    public void delete(String key) {
        s3.deleteObject(bucket, key);
    }

    /** 일괄 삭제: 빈 컬렉션이면 무시 */
    @Override
    public void deleteAll(Collection<String> keys) {
        if (keys == null || keys.isEmpty()) return;
        var req = new DeleteObjectsRequest(bucket)
                .withKeys(keys.stream().map(DeleteObjectsRequest.KeyVersion::new).toList());
        s3.deleteObjects(req);
    }
}

/**
 * Design Notes
 *
 * Immutable 캐시(1년)
 * - "public, max-age=31536000, immutable"는 브라우저/CDN에 장기 캐시를 지시합니다.
 * - 파일명이 바뀌면(예: UUID) 새 리소스로 인식되어 캐시 무효화 비용 없이 업데이트 배포가 가능합니다.
 *
 * 키 전략과 캐시 무효화
 * - 같은 경로라도 키(파일명)가 달라지면 캐시 충돌 없이 즉시 새 콘텐츠가 노출됩니다.
 * - 릴리즈 파이프라인에서 “버전드 키” 전략이 유용합니다.
 *
 * CloudFront 공개 URL
 * - 실제 S3 퍼블릭 권한 없이도 “표시용 경로”로 CDN 도메인 + 키를 결합합니다.
 * - UrlMapper.cfUrl(domain, key) 구현 시 이스케이프, 슬래시 중복, 한글 키 인코딩에 주의하세요.
 *
 * ACL 비권장(BOE)
 * - "Bucket Owner Enforced(BOE)" 정책에서는 개별 객체 ACL을 사용하지 않고,
 *   버킷 정책/아이덴티티 기반 권한으로 제어하는 편이 보안/운영상 단순합니다.
 *
 * 스트림 수명
 * - openStream의 InputStream은 호출자에게 close 책임이 있습니다.
 * - 웹 컨트롤러에서 스트림을 HTTP 응답으로 직접 흘릴 경우, try-with-resources를
 *   컨트롤러 범위에 두어 전송 완료 시 자동 해제되도록 하세요.
 *
 * 업로드 검증
 * - MIME 스니핑(서명 위조 방지), 최대 크기(예: 10MB), 금지 확장자 차단,
 *   이미지 차원 검사(썸네일 서버 과부하 예방) 등을 UploadValidator에서 처리하세요.
 *
 * Content-Length
 * - SDK v1에서 InputStream 업로드 시 길이를 지정하는 편이 안전합니다
 *   (멀티파트/청크 업로드 유틸을 쓰지 않는 한). 길이를 모르면 TransferManager(멀티파트)를 고려하세요.
 *
 * 프리사인드 URL
 * - 만료 시간(ttl) 경과 시 자동 403이 발생합니다.
 * - 버킷 정책이 퍼블릭 읽기 금지여도 특정 키에 대해 임시 접근을 허용할 수 있습니다.
 * - 필요 시 ResponseHeaderOverrides로 콘텐츠 타입/파일명을 지정할 수 있습니다.
 *
 * 교체 시 삭제 실패 처리
 * - 네트워크/권한 이슈로 삭제 실패가 날 수 있습니다.
 * - 핵심 경로는 새 객체 노출이므로 예외 전파 없이 로깅만 하고 넘어가는 선택이 실무에서 흔합니다
 *   (주기적 정리 배치로 보완).
 *
 * 선택적 개선 팁
 * - 서버 측 암호화: 민감 파일은 ObjectMetadata#setSSEAlgorithm(AES256) 또는 KMS 키 사용.
 * - ETag/무결성: 멀티파트 업로드 시 ETag가 MD5와 불일치할 수 있으므로 별도 해시를
 *   메타데이터/DB에 저장해 무결성 검증을 수행하세요.
 * - 에러 매핑: AmazonS3Exception의 HTTP 상태 코드를 비즈니스 예외로 매핑하여
 *   API 응답 일관성을 높이세요(예: 404 → NotFoundException).
 * - Content-Disposition: 프리사인드 URL 생성 시 ResponseHeaderOverrides로
 *   contentDisposition을 설정하면 다운로드 파일명을 지정할 수 있습니다.
 */
