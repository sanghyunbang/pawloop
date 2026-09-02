package com.heattrip.heat_trip_backend.community.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.util.List;

/**
 * 글 하나의 반응 집계 — 계약의 {@code ReactionSummary}.
 *
 * <h2>{@code mine} 은 {@code null} 과 {@code []} 가 다르다</h2>
 * <pre>
 *   null   비인증 요청이다. 누가 눌렀는지 물을 대상이 없다
 *   []     로그인했고, 아무것도 안 눌렀다
 * </pre>
 * <p>둘을 같게 두면 {@code []} 가 게스트에게 <b>거짓말</b>을 한다(ADR-0017 규약 6).
 * 그래서 {@code @JsonInclude} 를 쓰지 않는다 — {@code null} 을 <b>명시적으로</b> 실어야 한다.
 *
 * <h2>카운트는 "몇 번" 이지 "몇 명" 이 아니다</h2>
 * <p>한 사람이 셋을 다 누를 수 있다(ADR-0016 결정 2). 화면이 "7명이 공감했어요" 로
 * 읽히게 쓰면 거짓말이 된다.
 */
@JsonInclude(JsonInclude.Include.ALWAYS)
public record ReactionSummaryResponse(int help, int cute, int empathy, List<String> mine) {

    /** 반응이 하나도 없는 글. {@code mine} 은 부르는 쪽이 정한다. */
    public static ReactionSummaryResponse of(int help, int cute, int empathy, List<String> mine) {
        return new ReactionSummaryResponse(help, cute, empathy, mine);
    }
}
