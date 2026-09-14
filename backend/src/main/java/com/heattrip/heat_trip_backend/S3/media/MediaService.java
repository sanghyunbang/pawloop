package com.heattrip.heat_trip_backend.S3.media;

import com.heattrip.heat_trip_backend.S3.*;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import java.net.URL;
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
 *
 * <h2>영상은 세 단계다 (#429)</h2>
 * <p>서버를 안 지난다 — {@code api.heattrip.link} 앞의 Cloudflare 가 본문을 100MB 에서 끊는다.
 * ① {@link #reserveVideo} 가 형식·크기·길이를 받아 {@code pending} 행과 서명 PUT 을 만들고
 * ② 앱이 그 URL 로 S3 에 직접 올리고 ③ {@link #completeVideo} 가 S3 에 HEAD 로 <b>실제로
 * 올라왔는지와 크기</b>를 묻고 포스터를 받아 {@code ready} 로 바꾼다. 서명 PUT 은 크기 조건을
 * 못 걸어서(SDK v1) "올렸다" 는 앱의 말이 아니라 HEAD 의 답으로 정한다.
 *
 * <p>{@code pending} 인 채 하루가 지나면 {@link #sweepOrphans} 가 사진과 같이 거둔다 — 상태를
 * 안 보고 {@code ref_type IS NULL} 만 본다. S3 에 객체가 있든 없든 {@code deleteObjects} 는
 * 성공을 준다.
 */
@Service
public class MediaService implements MediaAttachment {

    /** 글에 붙는 카테고리. 고아 청소와 글 삭제가 이 둘만 본다. */
    private static final Set<UploadCategory> POST_CATEGORIES =
            // 산책 사진(#450)도 같은 두 단계(올리고 → 붙이고)를 지난다 — 산책을 저장 안 하면 고아다.
            EnumSet.of(UploadCategory.POST_IMAGE, UploadCategory.POST_VIDEO, UploadCategory.WALK_IMAGE);

    /**
     * 서명 PUT 이 사는 시간 (#429). 앱이 URL 을 받고 720p 파일을 올리는 데 15분이면 넉넉하고,
     * URL 이 새도 그 뒤로는 못 쓴다. 계약({@code /media/videos})이 같은 숫자를 적는다.
     */
    public static final Duration VIDEO_UPLOAD_TTL = Duration.ofMinutes(15);

    /**
     * 영상 길이 상한 (#429). 피드에서 스치며 보는 영상이지 강의가 아니다 — 60초.
     * 크기 상한은 {@link UploadCategory#POST_VIDEO} 가 든다(150MB). 계약이 둘 다 적는다.
     */
    public static final Duration MAX_VIDEO_DURATION = Duration.ofSeconds(60);

    /** 한 글에 붙는 영상 수 — 이슈 #429 의 한도, 하나. 사진과 합쳐 열 개까지는 {@code PostRequest} 가 잰다. */
    public static final int MAX_VIDEOS_PER_POST = 1;

    /** 포스터(썸네일)는 사진 규칙(형식 · 10MB)을 따르고, 사진 접두사 밑 이 하위 경로에 산다. */
    static final String POSTER_SUB_PATH = "posters";

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
    @Override
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

    // ─────────────────────────── 영상 — 세 단계 (#429) ───────────────────────────

    /** {@link #reserveVideo} 의 답 — 만든 행과, 앱이 PUT 할 서명 URL. */
    public record VideoTicket(MediaObject media, URL uploadUrl) {
    }

    /**
     * ① 자리 잡기. 형식·크기·길이를 재고 {@code pending} 행을 만든 뒤 서명 PUT 을 돌려준다.
     *
     * <p>파일은 아직 없다. 크기는 앱이 <b>올리겠다고 알린</b> 값이고, {@link #completeVideo} 가
     * 실제 크기와 같은지 잰다 — 다르면 앱이 알린 것과 다른 파일을 올린 것이다.
     *
     * @param width  픽셀 폭. {@code height} 와 함께거나 둘 다 없거나
     */
    @Transactional
    public VideoTicket reserveVideo(String ownerId, String contentType, long size,
                                    Integer width, Integer height, int durationMs) {
        UploadCategory category = UploadCategory.POST_VIDEO;
        if (contentType == null || !category.allowed.contains(contentType)) {
            throw new IllegalArgumentException("영상은 mp4 · mov 만 올릴 수 있어요.");
        }
        if (size <= 0 || size > category.max) {
            throw new IllegalArgumentException("영상은 " + (category.max / (1024 * 1024)) + "MB 까지예요.");
        }
        if (durationMs <= 0 || durationMs > MAX_VIDEO_DURATION.toMillis()) {
            throw new IllegalArgumentException("영상은 " + MAX_VIDEO_DURATION.toSeconds() + "초까지예요.");
        }
        if ((width == null) != (height == null)) {
            throw new IllegalArgumentException("width·height 는 함께 줘야 합니다.");
        }

        String fileName = "clip" + extensionOf(contentType);
        PresignedUpload put = storage.presignedPut(
                UploadRequest.of(category, ownerId), fileName, contentType, VIDEO_UPLOAD_TTL);

        MediaObject m = MediaObject.of(category, ownerId, null, null, put.key(), fileName, contentType, size);
        m.setStatus(MediaStatus.PENDING);
        m.setDimensions(width, height);
        m.setDurationMs(durationMs);
        return new VideoTicket(repo.save(m), put.url());
    }

    /**
     * ③ 끝내기. S3 에 HEAD 로 실제로 올라왔는지와 크기를 묻고, 포스터를 받아 {@code ready} 로 바꾼다.
     *
     * <ul>
     *   <li>내 것이 아니면 <b>404</b> — 클래스 javadoc 의 규약 그대로.</li>
     *   <li>사진이면 <b>400</b> — 사진은 받는 순간 끝나서 이 단계가 없다.</li>
     *   <li>이미 {@code ready} 면 <b>그대로 돌려준다</b> — 앱이 타임아웃 뒤 다시 부를 수 있다. 두 번째
     *       포스터는 안 받는다. 첫 번째가 이미 글에 그려지고 있을 수 있다.</li>
     *   <li>S3 에 없으면 <b>409</b> — 아직 그 상태가 아닌 것이지 잘못된 요청이 아니다. 앱이 다시
     *       올리고 다시 부른다. 행은 {@code pending} 으로 남고 하루 뒤 청소가 거둔다.</li>
     *   <li>크기가 알린 것과 다르면 <b>400</b> — 알린 것과 다른 파일이다. S3 의 객체는 안 지운다.
     *       행이 {@code pending} 이라 청소가 함께 거둔다.</li>
     * </ul>
     *
     * <p>포스터는 HEAD 뒤에 올린다. 앞에 올리면 "아직 안 올라왔습니다" 마다 포스터가 버킷에 남는다.
     * 그래도 포스터를 올린 뒤 DB 가 실패하면 그 한 장은 남는다 — 행이 가리키지 않는 키라 청소도
     * 모른다. 사진의 {@link #uploadMany} 와 같은 틈이고, 같은 이유로 여기서 안 막는다.
     */
    @Transactional
    public MediaObject completeVideo(Long mediaId, MultipartFile poster, String ownerId) {
        MediaObject m = mine(mediaId, ownerId);
        if (!m.isVideo()) {
            throw new IllegalArgumentException("사진은 올리는 순간 끝납니다 — 이 경로는 영상만 씁니다.");
        }
        if (m.getStatus().isReady()) {
            return m;
        }
        requirePoster(poster);

        StoredObject actual = storage.stat(m.getObjectKey())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.CONFLICT,
                        "영상이 아직 올라오지 않았습니다. 올린 뒤 다시 불러 주세요."));
        if (actual.size() != m.getSize()) {
            throw new IllegalArgumentException("올라온 영상의 크기가 알린 크기와 다릅니다.");
        }
        if (actual.contentType() == null || !m.getCategory().allowed.contains(actual.contentType())) {
            throw new IllegalArgumentException("올라온 파일이 영상이 아닙니다.");
        }

        StoredObject posterObject = storage.upload(
                poster, UploadRequest.of(UploadCategory.POST_IMAGE, ownerId).withSubPath(POSTER_SUB_PATH));
        m.setPosterKey(posterObject.key());
        m.setContentType(actual.contentType());
        m.setStatus(MediaStatus.READY);
        return repo.save(m);
    }

    // ─────────────────────────── MediaAttachment (#429) ───────────────────────────

    @Override
    @Transactional
    public List<AttachedMedia> attach(String refType, String refId, List<Long> mediaIds, long ownerId) {
        requireAtMostOneVideo(List.of(), mediaIds == null ? List.of() : mediaIds);
        attachOrThrow(refType, refId, mediaIds, ownerId);
        return attachedList(refType, refId);
    }

    @Override
    @Transactional
    public List<AttachedMedia> replace(String refType, String refId, List<Long> mediaIds, long ownerId) {
        Set<Long> wanted = new LinkedHashSet<>(mediaIds);
        List<MediaObject> current = repo.findByRefTypeAndRefIdOrderByIdAsc(refType, refId);

        List<MediaObject> gone = current.stream()
                .filter(m -> !wanted.contains(m.getId()))
                .toList();
        List<MediaObject> kept = current.stream()
                .filter(m -> wanted.contains(m.getId()))
                .toList();

        // 새로 든 것만 붙인다. 이미 붙어 있는 것은 조건(ref_type is null)에 안 걸리므로 빼고 센다.
        Set<Long> already = current.stream().map(MediaObject::getId).collect(Collectors.toSet());
        List<Long> fresh = wanted.stream().filter(id -> !already.contains(id)).toList();

        // **붙이기가 먼저고 지우기는 나중이다.** 지우기는 S3 를 부르고 S3 는 트랜잭션 밖이다 —
        // 먼저 지우고 붙이기가 실패하면 DB 는 되돌아가는데 파일은 이미 없어서, 뗀 적 없는
        // 사진이 화면에서 깨진다. 붙이기는 조건부 UPDATE 라 실패해도 밖에 남는 것이 없다.
        requireAtMostOneVideo(kept, fresh);
        attachOrThrow(refType, refId, fresh, ownerId);

        // 빠진 것은 지운다 — 사용자가 고치기 화면에서 뗀 사진이다. 되돌릴 길을 남기지 않는다.
        remove(gone);

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
                m.getDurationMs(),
                m.getObjectKey());
    }

    /**
     * 한 글에 영상은 {@value #MAX_VIDEOS_PER_POST}개다 (#429). 붙이기 전에 센다 — 요청 하나가 목록
     * 전부를 들고 오므로 경합이 없다. 남의 id 나 없는 id 는 여기서 안 거른다 — 그건
     * {@link #attachOrThrow} 의 영향 행 수가 잰다.
     *
     * @param kept  이미 붙어 있고 이번에도 남는 것
     * @param fresh 이번에 새로 붙일 id
     */
    private void requireAtMostOneVideo(List<MediaObject> kept, List<Long> fresh) {
        long videos = kept.stream().filter(MediaObject::isVideo).count();
        if (!fresh.isEmpty()) {
            videos += repo.findAllById(new LinkedHashSet<>(fresh)).stream()
                    .filter(MediaObject::isVideo)
                    .count();
        }
        if (videos > MAX_VIDEOS_PER_POST) {
            throw new IllegalArgumentException("영상은 한 글에 하나까지 붙일 수 있어요.");
        }
    }

    /**
     * 포스터는 사진 규칙이다 — 비어 있지 않고, 사진 형식이고, 10MB 아래. 저장소의 검증기도 같은
     * 것을 보지만 그쪽은 S3 를 부르기 직전이라, HEAD 를 부르기 <b>전에</b> 여기서 먼저 거른다.
     */
    private static void requirePoster(MultipartFile poster) {
        if (poster == null || poster.isEmpty()) {
            throw new IllegalArgumentException("포스터(썸네일) 한 장이 있어야 합니다.");
        }
        UploadCategory rule = UploadCategory.POST_IMAGE;
        if (poster.getContentType() == null || !rule.allowed.contains(poster.getContentType())) {
            throw new IllegalArgumentException("포스터는 jpeg · png · webp 여야 합니다.");
        }
        if (poster.getSize() > rule.max) {
            throw new IllegalArgumentException("포스터가 너무 큽니다.");
        }
    }

    /** 허용 형식이 둘뿐이라 표가 아니다 — {@code UploadCategory.POST_VIDEO.allowed} 가 늘면 여기도 는다. */
    private static String extensionOf(String contentType) {
        return "video/quicktime".equals(contentType) ? ".mov" : ".mp4";
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
