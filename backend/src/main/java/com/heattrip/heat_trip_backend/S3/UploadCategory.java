package com.heattrip.heat_trip_backend.S3;

import java.util.Set;
import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 업로드 범주 정책(경로 prefix, 허용타입, 최대크기).
 *
 * <h2>DB 의 enum 은 <b>알파벳순</b>이다 — 선언 순서가 아니다</h2>
 * <p>Hibernate 가 이 enum 을 MySQL {@code enum(...)} 컬럼으로 뽑는데(정본 {@code 01_schema.sql}),
 * 상수를 <b>알파벳순으로 정렬해</b> 뽑는다(2026-09-13 실측 — 옛 셋이 우연히 알파벳순이라
 * 몰랐다). {@code SchemaDdlDriftTest} 가 그 문자열을 그대로 비교하므로, 값을 더하는
 * 마이그레이션({@code 39_post_media.sql})의 {@code MODIFY} 도 알파벳순이어야 한다. 여기 선언
 * 순서는 사람이 읽는 순서일 뿐이다.
 *
 * <h2>앞의 셋은 감정 여행 시절 것이다</h2>
 * <p>{@code JOURNEY_IMAGE}·{@code REVIEW_IMAGE} 를 쓰던 코드는 #94 로 지웠고 {@code PROFILE_IMAGE}
 * 는 부르는 화면이 없다. 운영 DB 에 그 값의 행이 남아 있어 enum 에서 뺄 수 없다 — 빼면
 * 기존 행이 읽히지 않는다. 고아 청소({@code MediaOrphanSweeper})는 {@code POST_*} 만 본다.
 *
 * <h2>영상은 multipart 로 안 받는다</h2>
 * <p>{@code POST_VIDEO} 의 상한은 서버가 받는 크기가 아니라 <b>S3 에 직접 올린 뒤 서버가
 * 확인하는</b> 상한이다(#429). {@code api.pawloop.app} 앞의 Cloudflare 가 100MB 까지만
 * 받아서 영상은 서버를 안 지난다. {@code MediaController} 가 multipart 로 온 영상을 막는다.
 */
@Schema(description = "Upload category; controls S3 prefix, allowed MIME types and size limits")
public enum UploadCategory {
    JOURNEY_IMAGE("journeys", Set.of("image/jpeg","image/png","image/webp","image/gif"), 10 * 1024 * 1024L),
    PROFILE_IMAGE("profiles", Set.of("image/jpeg","image/png","image/webp"),              5  * 1024 * 1024L),
    REVIEW_IMAGE ("reviews",  Set.of("image/jpeg","image/png","image/webp"),              10 * 1024 * 1024L),

    /** 커뮤니티 글의 사진(#429). 앱이 1600px 로 다시 인코딩해 올린다 — EXIF 가 그때 사라진다. */
    POST_IMAGE   ("posts",    Set.of("image/jpeg","image/png","image/webp"),              10 * 1024 * 1024L),

    /** 커뮤니티 글의 영상(#429). 앱이 720p 로 다시 인코딩해 S3 에 직접 올린다. */
    POST_VIDEO   ("posts-video", Set.of("video/mp4","video/quicktime"),                   150 * 1024 * 1024L),

    /** 산책 중 찍은 사진(#450) — 산책 기록({@code walk})에 붙는다. 글 사진과 같은 크기 규칙. */
    WALK_IMAGE   ("walks",    Set.of("image/jpeg","image/png","image/webp"),              10 * 1024 * 1024L),

    /** 채팅 말풍선 사진(#452) — 메시지({@code chat_message})에 하나씩 붙는다. 글 사진과 같은 크기 규칙. */
    CHAT_IMAGE   ("chats",    Set.of("image/jpeg","image/png","image/webp"),              10 * 1024 * 1024L);

    public final String prefix;
    public final Set<String> allowed;
    public final long max;

    UploadCategory(String prefix, Set<String> allowed, long max) {
        this.prefix = prefix;
        this.allowed = allowed;
        this.max = max;
    }

    /** 영상인가. 서버가 받는 방식과 화면이 그리는 방식이 둘 다 여기서 갈린다. */
    public boolean isVideo() {
        return this == POST_VIDEO;
    }

    /** 글에 붙는 것인가 — 고아 청소와 글 삭제가 이 둘만 본다. */
    public boolean isPostMedia() {
        return this == POST_IMAGE || this == POST_VIDEO;
    }
}
