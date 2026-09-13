package com.heattrip.heat_trip_backend.community.dto;

import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * 글 수정 요청 — 계약의 {@code PostPatch}. 이슈 #211.
 *
 * <h2>왜 {@code PostRequest} 를 재사용하지 않나</h2>
 * <p>그 스키마는 {@code required: [board, title, body]} 다. 그대로 쓰면 제목만 고치려는
 * 사람도 본문을 다시 보내야 하고, 그 사이 다른 기기에서 고친 본문을 <b>조용히 되돌린다.</b>
 * ADR-0017 규약 4 가 부분 수정에는 전용 {@code *Patch} 스키마를 쓰라고 정한 이유다.
 * {@code DogController} 가 {@code PATCH} 를 안 만든 이유도 같은 자리에 적혀 있다.
 *
 * <h2>{@code null} 은 "안 바꿈" 이다</h2>
 * <p>비우기가 아니다. 그래서 <b>세 필드는 비울 수 없다</b> — 어차피 {@code NOT NULL} 컬럼이라
 * 비울 수 있어야 할 이유도 없다.
 *
 * <p><b>{@code loc}·{@code contentId} 는 이 요청으로 못 바꾼다.</b> 그 둘은 비울 수 있어야
 * 하는데(장소 연결 해제), 그러려면 JSON 의 <b>"키가 없음" 과 "명시적 null"</b> 을 구별해야
 * 한다. Jackson 은 record 로 받으면 둘 다 {@code null} 이라 구별이 안 되고, 구별하려면
 * 래퍼 타입이나 {@code JsonNullable} 이 필요하다 — 저장소 최초의 {@code PATCH} 를 그
 * 결정과 함께 들이지 않는다. 지금 필요한 것은 <b>잘못 쓴 글을 고쳐 쓰는 것</b>이고 장소
 * 연결은 지우고 다시 쓰면 된다. 필요해지는 날 그 자리에서 정한다.
 *
 * <h2>{@code minProperties: 1} 은 서비스가 잰다</h2>
 * <p>Bean Validation 에 그런 제약이 없다. 셋 다 없는 요청은 아무 일도 안 하면서 200 을
 * 주는데, 그건 "고쳐졌다" 로 읽힌다.
 */
public record PostPatchRequest(

        String board,

        @Size(max = 200, message = "제목은 200자를 넘을 수 없습니다.")
        String title,

        @Size(max = PostRequest.MAX_BODY_LENGTH,
                message = "본문은 " + PostRequest.MAX_BODY_LENGTH + "자를 넘을 수 없습니다.")
        String body,

        /**
         * 붙은 사진·영상을 <b>통째로 갈아 끼운다</b> (#429). 키가 없으면 안 바꾸고, 빈 배열이면
         * 전부 뗀다 — 위의 "null 은 안 바꿈" 규약과 같다. 목록에서 빠진 것은 지워진다.
         * 사용자가 고치기 화면에서 뗀 것이다. 새로 든 것은 {@code PostRequest.mediaIds} 와
         * 같은 조건으로 붙는다(내 것 · 아직 안 붙음 · ready).
         */
        @Size(max = PostRequest.MAX_MEDIA,
                message = "사진·영상은 한 글에 " + PostRequest.MAX_MEDIA + "개까지 붙일 수 있습니다.")
        List<Long> mediaIds) {

    /** 계약의 {@code minProperties: 1}. 넷 다 없으면 고칠 것이 없다. */
    public boolean isEmpty() {
        return board == null && title == null && body == null && mediaIds == null;
    }

    /**
     * 있는 값은 공백만이어서는 안 된다.
     *
     * <p>{@code @NotBlank} 를 쓸 수 없다 — 없는 것({@code null})은 통과해야 하는데 그 어노테이션은
     * {@code null} 도 막는다. 그렇다고 안 재면 {@code {"title": "   "}} 이 제목 없는 글을 만든다.
     */
    public boolean hasBlank() {
        return isBlank(board) || isBlank(title) || isBlank(body);
    }

    private static boolean isBlank(String value) {
        return value != null && value.isBlank();
    }
}
