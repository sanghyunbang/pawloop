package com.heattrip.heat_trip_backend.community.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * 글 작성 요청 — 계약의 {@code PostInput}. {@code required} 는 {@code [board, title, body]}.
 *
 * <h2>{@code board} 값은 여기서 검증하지 않는다</h2>
 * <p>Bean Validation 으로 enum 을 검증하면 실패가 {@code 400} 이 되지만 <b>어떤 값이 유효한지</b>
 * 를 못 말한다. {@code CommunityService} 가 목록과 함께 던져 메시지에 실린다.
 *
 * <p><b>DB 의 {@code CHECK} 는 그 뒤에 있다.</b> #169 는 안 걸었고 그 이유를 "게시판은 제품이
 * 늘리는 목록이라 값이 늘 때마다 마이그레이션이 따라오면 그 자체가 비용이다" 라고 적었다.
 * #167 이 뒤집었다 — 비용은 사실이지만 <b>잘못 들어간 행이 더 비싸다.</b> 서비스를 안 지나는
 * 길(배치·수동 INSERT·다음 사람이 만들 관리 화면)로 들어온 값은 목록 쿼리에는 걸리는데 앱이
 * 라벨을 못 찾아 빈 칸으로 뜬다. {@code care_log.type} 이 이미 같은 값을 치르고 있다
 * (📌 #86 원칙 5). 지금 {@code chk_post_board} 가 {@code 14_community.sql} 에 있다.
 *
 * <h2>본문 길이</h2>
 * <p>{@code body} 는 {@code TEXT} 컬럼이다 — 상한이 없으면 {@code 65535}<b>바이트</b>까지
 * 들어가고, 한글은 utf8mb4 에서 한 자가 3바이트라 실질 상한이 약 21,800자다. 그 수는 제품이
 * 정한 것이 아니라 컬럼 타입이 흘린 것이다. 게다가 상한이 없으면 로그인한 사람 누구나
 * 수십 MB 짜리 본문을 밀어 넣을 수 있다.
 *
 * <p>그래서 {@link #MAX_BODY_LENGTH} 로 못 박는다. 앱의 입력칸도 이 수를 봐야 한다 —
 * {@code create_screen} 이 같은 이유를 적어 뒀다: "여기서 막지 않으면 501자를 쓴 사람이 저장을
 * 누른 뒤에야 400 을 받는다"(#161).
 */
public record PostRequest(

        @NotBlank(message = "게시판을 골라 주세요.")
        String board,

        @NotBlank(message = "제목을 적어 주세요.")
        @Size(max = 200, message = "제목은 200자를 넘을 수 없습니다.")
        String title,

        @NotBlank(message = "본문을 적어 주세요.")
        @Size(max = MAX_BODY_LENGTH, message = "본문은 " + MAX_BODY_LENGTH + "자를 넘을 수 없습니다.")
        String body,

        @Size(max = 100, message = "장소 이름은 100자를 넘을 수 없습니다.")
        String loc,

        /**
         * 연결 장소. {@code Place.contentId} 와 같은 키다(ADR-0017).
         *
         * <p>존재를 검증하지 않는다 — 장소는 KTO 프록시 <b>캐시</b>라 사용자가 고른 것의 행이
         * 아직 없을 수 있다. 검증하면 그때 글 작성이 실패한다.
         */
        @Size(max = 64, message = "장소 식별자가 너무 깁니다.")
        String contentId,

        /**
         * 붙일 코스 (#339). <b>내 것이면서 공개된 코스</b>만 붙는다 — 아니면 400 이다.
         *
         * <p>비공개를 붙이면 남들에게는 빈 자리로 보인다. 서버가 몰래 공개로 바꾸지 않고
         * 막는다 — 공개는 사용자가 하는 일이다. 앱이 "공개하고 붙이기" 를 권한다.
         *
         * <p>글을 고칠 때 이 키가 <b>오지 않으면 "안 바꿈"</b>, {@code null} 로 오면
         * "떼어 낸다" 이다.
         */
        Long courseId,

        /** 이 글에 찍힌 아이 (#451 5번). 내 아이의 id 만 받는다 — 남의 아이면 400. */
        Long dogId,

        /**
         * 붙일 사진·영상 (#429). <b>업로드가 먼저다</b> — {@code POST /media} 가 돌려준 id 를
         * 여기에 싣는다. 서버는 <b>내 것이고 아직 어디에도 안 붙은 것</b>만 붙이고, 하나라도
         * 아니면 400 이고 글은 안 생긴다. 순서는 이 목록의 순서가 아니라 올린 순서다.
         *
         * <p>없어도 된다. 사진 없는 글이 여전히 대부분이다.
         */
        @Size(max = MAX_MEDIA, message = "사진·영상은 한 글에 " + MAX_MEDIA + "개까지 붙일 수 있습니다.")
        List<Long> mediaIds) {

    /**
     * 한 글에 붙는 미디어의 상한. 열 장이면 카드 한 장의 그림으로 충분하고, 그보다 많으면
     * 목록 응답 하나가 URL 백 개를 실어 나른다. 앱의 고르기 화면도 이 수를 본다.
     */
    public static final int MAX_MEDIA = 10;

    /**
     * 본문의 최대 글자 수.
     *
     * <p>컬럼이 {@code TEXT}(65535바이트)라 utf8mb4 한글로도 약 21,800자가 들어간다. 그보다
     * 훨씬 낮게 잡는 이유는 <b>컬럼이 정한 수를 제품의 수로 쓰지 않기</b> 위해서다. 한 화면에서
     * 읽히는 글의 길이이고, 늘리는 것은 줄이는 것보다 쉽다.
     */
    public static final int MAX_BODY_LENGTH = 5000;
}
