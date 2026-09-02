package com.heattrip.heat_trip_backend.community.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 글 작성 요청 — 계약의 {@code PostInput}. {@code required} 는 {@code [board, title, body]}.
 *
 * <h2>{@code board} 값은 여기서 검증하지 않는다</h2>
 * <p>Bean Validation 으로 enum 을 검증하면 실패가 {@code 400} 이 되지만 <b>어떤 값이 유효한지</b>
 * 를 못 말한다. {@code CommunityService} 가 목록과 함께 던져 메시지에 실린다.
 *
 * <p>DB 에는 {@code CHECK} 를 걸지 않았다({@code Post} 엔티티 javadoc) — 게시판은 제품이
 * 늘리는 목록이라 값이 늘 때마다 마이그레이션이 따라오면 그 자체가 비용이다. 그래서
 * <b>서비스가 유일한 방어선</b>이다.
 */
public record PostRequest(
        @NotBlank(message = "게시판을 골라 주세요.")
        String board,

        @NotBlank(message = "제목을 적어 주세요.")
        @Size(max = 200, message = "제목은 200자를 넘을 수 없습니다.")
        String title,

        @NotBlank(message = "본문을 적어 주세요.")
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
        String contentId) {
}
