package com.heattrip.heat_trip_backend.S3;

import java.util.Collection;
import java.util.List;
import java.util.Map;

/**
 * "이 사진·영상을 글에 붙여도 되는가" · "붙어 있는 것을 어떻게 그리나" — {@code S3} 모듈이
 * 밖으로 내놓는 <b>첨부에 관한 유일한 표면</b>이다. 이슈 #429.
 *
 * <h2>왜 {@code MediaService} 를 그대로 열지 않는가</h2>
 * <p>{@code community} 가 필요한 것은 셋뿐이다 — 붙이기, 붙은 것 읽기, 글이 사라질 때 함께
 * 지우기. {@code MediaService} 를 열면 업로드·교체·presigned 까지 따라 나가고, 그러면 다음
 * 사람이 <b>커뮤니티 코드에서 남의 미디어를 지울</b> 수도 있게 된다. {@code walk.CourseAttachment}
 * 가 같은 이유로 만들어졌다.
 *
 * <p>모듈 패키지 <b>바로 아래</b> 타입은 Spring Modulith 가 공개 표면으로 본다.
 * {@code S3.media.MediaService} 는 하위 패키지라 밖에서 쓰면 경계 위반이다 — 기준선 96 이
 * 그대로여야 한다(#95 §4).
 *
 * <h2>내 것이고 아직 안 붙은 것만 붙는다</h2>
 * <p>판정은 락이 아니라 <b>조건부 UPDATE 의 영향 행 수</b>다(#86 원칙 5). 같은 사진을 두
 * 글에 동시에 붙이면 먼저 UPDATE 한 쪽이 이기고 나머지는 0행이라 400 이다 — 유예 창도
 * 인메모리 락도 없다. 남의 {@code mediaId} 를 넣어도 0행이다.
 */
public interface MediaAttachment {

    /** 커뮤니티 글에 붙은 것의 {@code ref_type}. 이 어휘는 붙이는 쪽이 아니라 여기가 든다. */
    String REF_POST = "POST";

    /** 아이 프로필 사진 (#448). {@code refId} 는 {@code dog.id}. 한 아이에 한 장이다 — {@link #replace} 로 간다. */
    String REF_DOG = "DOG";

    /**
     * 붙인다. <b>내 것이고, 아직 어디에도 안 붙었고, {@code ready} 인 것</b>만 붙는다.
     *
     * <p>하나라도 아니면 아무것도 안 붙이고 {@link IllegalArgumentException} 이다 — 부르는
     * 쪽의 트랜잭션이 통째로 되돌아가 글도 안 생긴다. 반만 붙은 글을 남기지 않는다.
     *
     * @param mediaIds 앱이 올린 순서. 같은 id 가 두 번 오면 하나로 센다
     * @return 붙은 것 전부, {@code id} 오름차순 — 앱이 순서대로 올리므로 그것이 고른 순서다
     */
    List<AttachedMedia> attach(String refType, String refId, List<Long> mediaIds, long ownerId);

    /**
     * 붙은 것을 <b>통째로 갈아 끼운다</b> — 글 고치기가 부른다.
     *
     * <p>목록에서 빠진 것은 지운다(S3 객체까지). 새로 든 것은 {@link #attach} 와 같은 조건으로
     * 붙는다. 빈 목록이면 전부 뗀다.
     */
    List<AttachedMedia> replace(String refType, String refId, List<Long> mediaIds, long ownerId);

    /**
     * 글 목록·상세에 그릴 것들. 없는 글은 결과에서 빠진다.
     *
     * <p>목록이 한 번에 물어보는 이유는 N+1 을 만들지 않기 위해서다 — 글 스무 개짜리 피드가
     * 사진을 스무 번 물으면 그 화면이 느려진다. {@code CourseAttachment.cards} 와 같다.
     */
    Map<String, List<AttachedMedia>> attachedTo(String refType, Collection<String> refIds);

    /** 글이 사라질 때 함께 지운다 — 행과 S3 객체 둘 다. 없으면 아무 일도 안 한다. */
    void detachAll(String refType, String refId);

    /**
     * S3 objectKey 를 공개 URL 로. {@code dog.avatar} 처럼 <b>키만 저장한</b> 자리가 응답을 조립할 때
     * 쓴다 — 완성된 URL 을 저장하면 버킷·CDN 을 옮길 때 행마다 고쳐야 한다(#209 Dogs-medium-2).
     */
    String publicUrl(String objectKey);

    /** 화면이 그리는 종류. 카테고리에서 온다. */
    enum Kind {
        IMAGE("image"),
        VIDEO("video");

        private final String wire;

        Kind(String wire) {
            this.wire = wire;
        }

        /** 계약({@code PostMedia.kind})에 나가는 값. */
        public String wire() {
            return wire;
        }
    }

    /**
     * 카드에 그릴 만큼의 미디어.
     *
     * @param posterUrl  영상의 썸네일. 사진은 {@code null}
     * @param width      픽셀 폭. 앱이 준 값이라 없을 수 있다
     * @param durationMs 영상 길이. 사진은 {@code null}
     */
    record AttachedMedia(long id, Kind kind, String url, String posterUrl,
                         Integer width, Integer height, Integer durationMs,
                         /** S3 objectKey — 키만 저장하는 자리(dog.avatar)가 쓴다. */
                         String key) {
    }
}
