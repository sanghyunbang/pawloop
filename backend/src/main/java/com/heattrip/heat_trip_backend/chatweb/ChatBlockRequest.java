package com.heattrip.heat_trip_backend.chatweb;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/**
 * 가리기 요청 본문 — 이슈 #82. 계약이 {@code required: [userId]} 로 선언했다.
 *
 * @param userId 가릴 사람의 {@code users.id}
 */
public record ChatBlockRequest(Long userId) {

    /**
     * 없으면 400.
     *
     * <p>{@code @NotNull} 을 안 쓰는 이유는 이 패키지의 다른 요청들과 같다 — 검증기를
     * 하나 더 켜는 대신 여기서 같은 봉투({@code GlobalExceptionHandler})로 떨어뜨린다.
     *
     * <p><b>{@code long} 으로 안 받는 것</b>이 요점이다. 원시 타입으로 받으면 JSON 에
     * {@code userId} 가 없을 때 <b>조용히 0 </b>이 되고, 0 을 가린 행이 하나 생긴다.
     */
    long requireUserId() {
        if (userId == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "userId 가 필요합니다.");
        }
        return userId;
    }
}
