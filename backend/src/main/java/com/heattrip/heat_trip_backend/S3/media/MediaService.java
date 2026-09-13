package com.heattrip.heat_trip_backend.S3.media;

import com.heattrip.heat_trip_backend.S3.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 미디어 도메인 서비스.
 * - 저장소(FileStorage) + JPA 리포지토리 결합
 * - 권한/연결(refType/refId) 처리
 * - 엔티티 변경( key → objectKey / 컬럼: media_key ) 반영 ①
 *
 * <p><b>{@code ownerId} 의 값 규약이 이슈 #5 배포를 기점으로 바뀐다.</b> 이 클래스의 소유권 검사는
 * 전부 {@code String.equals} 다. 그래서 규약이 바뀌면 옛 행은 진짜 주인에게도 매칭되지 않는다.
 *
 * <table>
 *   <caption>owner_id 에 실제로 들어간 값</caption>
 *   <tr><th>경로</th><th>#5 이전</th><th>#5 이후</th></tr>
 *   <tr><td>{@code MediaController} 직접 업로드</td>
 *       <td>JWT subject — 이메일 또는 {@code kakao_1234567890}</td><td>{@code users.id}</td></tr>
 *   <tr><td>{@code JourneyController_v2} 경유</td>
 *       <td>{@code users.id}</td><td>{@code users.id}(변화 없음)</td></tr>
 * </table>
 *
 * <p>즉 배포 이전에 {@code POST /media} 로 올라간 행은 소유자 본인도 replace·delete 를 할 수 없다
 * ({@code deleteByRef} 는 조용히 건너뛰어 S3 객체가 고아로 남는다).
 * 보안 구멍은 아니다 — 옛 값은 이메일이거나 {@code provider_socialId} 라 순수 숫자인 새 값과
 * 겹칠 수 없으므로 남의 파일이 열리지는 않는다(fail-closed).
 *
 * <p>백필 여부의 결정과 SQL 은 {@code docs/03-database/migration.md} §3-1 에 있다.
 * 여기서 두 형식을 함께 받아 주는 과도기 코드는 <b>일부러 넣지 않는다</b> — 그런 코드는
 * "언제 지우는가"의 주인이 없어 영구히 남고, 그 자체가 소유권 판정을 느슨하게 만든다.
 *
 * <h2>남의 것과 없는 것을 구별해 주지 않는다 (#429)</h2>
 * <p>{@link #replace}·{@link #delete} 에서 소유자가 아니면 <b>404</b> 다. 예전에는 400
 * "권한 없음" 이었는데, 그러면 id 를 훑어 어느 번호에 남의 파일이 있는지 셀 수 있다.
 * 크루·채팅이 같은 이유로 404 를 고른 것과 같다(ADR-0017 규약 3).
 *
 * <h2>글에 붙이기는 {@link MediaAttachment} 가 정본이다 (#429)</h2>
 * <p>{@code community} 는 그 표면만 본다. 여기 있는 다른 메서드는 그 모듈에서 안 보인다 —
 * 하위 패키지라 Modulith 가 막는다.
 */
@Service
public class MediaService implements MediaAttachment {

    /** 글에 붙는 카테고리. 고아 청소와 글 삭제가 이 둘만 본다. */
    private static final Set<UploadCategory> POST_CATEGORIES =
            EnumSet.of(UploadCategory.POST_IMAGE, UploadCategory.POST_VIDEO);

    private final FileStorage storage;
    private final MediaObjectRepository repo;

    public MediaService(FileStorage storage, MediaObjectRepository repo) {
        this.storage = storage;
        this.repo = repo;
    }

    /** C: 여러 장 업로드 */
    @Transactional
    public List<MediaObject> uploadMany(List<MultipartFile> files, UploadCategory cat,
                                        String ownerId, String refType, String refId) {
        return uploadMany(files, cat, ownerId, refType, refId, null, null);
    }

    /**
     * C: 여러 장 업로드 — 크기와 함께 (#429).
     *
     * @param width  픽셀 폭. 앱이 다시 인코딩한 뒤 아는 값이다. 파일이 하나일 때만 뜻이 있다
     */
    @Transactional
    public List<MediaObject> uploadMany(List<MultipartFile> files, UploadCategory cat,
                                        String ownerId, String refType, String refId,
                                        Integer width, Integer height) {
        return files.stream()
            .filter(f -> f != null && !f.isEmpty())
            .map(f -> {
                // 업로드 수행 → S3 key/메타를 가진 StoredObject 반환 가정 ②
                StoredObject so = storage.upload(
                    f,
                    UploadRequest.of(cat, ownerId).withSubPath(refId)
                );
                // 엔티티 팩토리: objectKey 사용(과거 key 아님) ①
                MediaObject m = MediaObject.of(
                    cat, ownerId, refType, refId,
                    so.key(),                       // ← String S3 object key
                    f.getOriginalFilename(),
                    f.getContentType(),
                    f.getSize()
                );
                m.setDimensions(width, height);
                return repo.save(m);
            })
            .collect(Collectors.toList()); // JDK < 16 호환
    }

    /** R: 공개 URL */
    public String publicUrl(String objectKey) {              // ← Long → String 변경 ③
        return storage.publicUrl(objectKey);
    }

    /** R: 프리사인드 URL */
    public String presignedUrl(String objectKey, Duration ttl) {
        return storage.presignedUrl(objectKey, ttl).toString();
    }

    /** R: refType/refId로 이미지 목록 조회 (컨트롤러에서 사용) */
    @Transactional(readOnly = true)
    public List<MediaObject> findByRef(String refType, String refId) {
        return repo.findByRefTypeAndRefId(refType, refId);
    }

    /** U: 교체 (새 업로드 → 구 키 삭제 → 메타 갱신). 내 것이 아니면 404 다. */
    @Transactional
    public MediaObject replace(Long mediaId, MultipartFile file, String ownerId) {
        MediaObject m = mine(mediaId, ownerId);

        // 기존 objectKey로 교체 업로드 수행 ④
        StoredObject neo = storage.replace(
            m.getObjectKey(),                                  // ← 변경
            file,
            UploadRequest.of(m.getCategory(), ownerId).withSubPath(m.getRefId())
        );

        // 엔티티 메타 갱신 (objectKey/콘텐츠타입/사이즈)
        m.setObjectKey(neo.key());                            // ← 변경
        m.setContentType(neo.contentType());
        m.setSize(neo.size());
        return repo.save(m);
    }

    /** D: 단건 삭제 (owner 검증). 내 것이 아니면 404 다 — 남의 것과 없는 것을 구별해 주지 않는다. */
    @Transactional
    public void delete(Long mediaId, String ownerId) {
        MediaObject m = mine(mediaId, ownerId);
        remove(List.of(m));
    }

    /** D: 연결 리소스 전체 삭제 (예: 특정 여정의 모든 이미지) */
    @Transactional
    public void deleteByRef(String refType, String refId, String ownerId) {
        var list = repo.findByRefTypeAndRefId(refType, refId);
        var own = list.stream()
                      .filter(m -> ownerId.equals(m.getOwnerId()))
                      .collect(Collectors.toList());
        remove(own);
    }

    // ─────────────────────────── MediaAttachment (#429) ───────────────────────────

    @Override
    @Transactional
    public List<AttachedMedia> attach(String refType, String refId, List<Long> mediaIds, long ownerId) {
        attachOrThrow(refType, refId, mediaIds, ownerId);
        return attachedList(refType, refId);
    }

    @Override
    @Transactional
    public List<AttachedMedia> replace(String refType, String refId, List<Long> mediaIds, long ownerId) {
        Set<Long> wanted = new LinkedHashSet<>(mediaIds);
        List<MediaObject> current = repo.findByRefTypeAndRefIdOrderByIdAsc(refType, refId);

        // 빠진 것은 지운다 — 사용자가 고치기 화면에서 뗀 사진이다. 되돌릴 길을 남기지 않는다.
        List<MediaObject> gone = current.stream()
                .filter(m -> !wanted.contains(m.getId()))
                .toList();
        remove(gone);

        // 새로 든 것만 붙인다. 이미 붙어 있는 것은 조건(ref_type is null)에 안 걸리므로 빼고 센다.
        Set<Long> already = current.stream().map(MediaObject::getId).collect(Collectors.toSet());
        List<Long> fresh = wanted.stream().filter(id -> !already.contains(id)).toList();
        attachOrThrow(refType, refId, fresh, ownerId);

        return attachedList(refType, refId);
    }

    @Override
    @Transactional(readOnly = true)
    public Map<String, List<AttachedMedia>> attachedTo(String refType, Collection<String> refIds) {
        if (refIds.isEmpty()) {
            return Map.of();
        }
        Map<String, List<AttachedMedia>> out = new LinkedHashMap<>();
        for (MediaObject m : repo.findByRefTypeAndRefIdInOrderByIdAsc(refType, refIds)) {
            out.computeIfAbsent(m.getRefId(), k -> new ArrayList<>()).add(toAttached(m));
        }
        return out;
    }

    @Override
    @Transactional
    public void detachAll(String refType, String refId) {
        remove(repo.findByRefTypeAndRefIdOrderByIdAsc(refType, refId));
    }

    /**
     * 안 붙은 채 {@code cutoff} 보다 오래된 글 미디어를 거둔다 — {@link MediaOrphanSweeper} 가 부른다.
     *
     * <p><b>같은 DB 를 향해 동시에 두 번 실행돼도 결과가 같다</b>(#86 원칙 2) — 조회 뒤 삭제라
     * 두 번째가 같은 행을 잡을 수는 있지만 {@code deleteAllInBatch} 는 없는 행에 0 을 주고,
     * S3 의 {@code deleteObjects} 는 이미 없는 키에도 성공을 준다. 남는 것은 로그 두 줄이다.
     *
     * <p>{@code POST_*} 만 본다 — 감정 여행 시절의 행은 이 잡의 것이 아니다.
     *
     * @return 거둔 수
     */
    @Transactional
    public int sweepOrphans(Instant cutoff) {
        List<MediaObject> orphans =
                repo.findByRefTypeIsNullAndCategoryInAndCreatedAtBefore(POST_CATEGORIES, cutoff);
        remove(orphans);
        return orphans.size();
    }

    // ─────────────────────────── 안쪽 ───────────────────────────

    /**
     * 붙인다 — 하나라도 못 붙이면 예외다. 트랜잭션이 이 예외를 되돌리므로 반만 붙은 상태가
     * 남지 않는다. {@code mediaIds} 가 비면 아무 일도 안 한다.
     */
    private void attachOrThrow(String refType, String refId, List<Long> mediaIds, long ownerId) {
        if (mediaIds == null || mediaIds.isEmpty()) {
            return;
        }
        List<Long> distinct = new ArrayList<>(new LinkedHashSet<>(mediaIds));
        int changed = repo.attach(refType, refId, distinct, String.valueOf(ownerId), MediaStatus.READY);
        if (changed != distinct.size()) {
            throw new IllegalArgumentException(
                    "붙일 수 없는 사진이 있습니다. 내가 올렸고 아직 어디에도 안 붙은 것만 붙일 수 있어요.");
        }
    }

    private List<AttachedMedia> attachedList(String refType, String refId) {
        return repo.findByRefTypeAndRefIdOrderByIdAsc(refType, refId).stream()
                .map(this::toAttached)
                .toList();
    }

    private AttachedMedia toAttached(MediaObject m) {
        return new AttachedMedia(
                m.getId(),
                m.isVideo() ? Kind.VIDEO : Kind.IMAGE,
                storage.publicUrl(m.getObjectKey()),
                m.getPosterKey() == null ? null : storage.publicUrl(m.getPosterKey()),
                m.getWidth(),
                m.getHeight(),
                m.getDurationMs());
    }

    /** 내 것이어야 한다. 아니면 <b>없는 것</b>이다 — 클래스 javadoc 참조. */
    private MediaObject mine(Long mediaId, String ownerId) {
        return repo.findById(mediaId)
                .filter(m -> m.getOwnerId().equals(ownerId))
                .orElseThrow(() -> new NoSuchElementException("미디어를 찾을 수 없습니다."));
    }

    /**
     * 행과 S3 객체를 함께 지운다. <b>행이 먼저</b>다 — S3 가 실패하면 예외로 트랜잭션이 되돌아가
     * 행이 남고, 다음 청소가 다시 시도한다. 반대로 하면 파일은 없는데 행이 남아 화면에 깨진
     * 그림이 뜬다.
     */
    private void remove(List<MediaObject> rows) {
        if (rows.isEmpty()) {
            return;
        }
        List<String> keys = new ArrayList<>(rows.size() * 2);
        for (MediaObject m : rows) {
            keys.add(m.getObjectKey());
            if (m.getPosterKey() != null) {
                keys.add(m.getPosterKey());
            }
        }
        repo.deleteAllInBatch(rows);
        storage.deleteAll(keys);
    }
}
