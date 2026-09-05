package com.heattrip.heat_trip_backend.consent.controller;

import com.heattrip.heat_trip_backend.consent.dto.ConsentsRequest;
import com.heattrip.heat_trip_backend.consent.dto.ConsentsResponse;
import com.heattrip.heat_trip_backend.consent.service.ConsentService;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.Valid;

import lombok.RequiredArgsConstructor;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 약관 동의 — 이슈 #190. 계약은 {@code docs/04-api/openapi.yaml} 의 {@code /api/consents} 다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — {@code SecurityConfig} 의 {@code anyRequest().authenticated()} 가 받는다.
 *       {@code publicMatchers} 에 줄을 더하지 않는다({@code DogController} 와 같다).</li>
 *   <li><b>주체</b> — 경로에 사용자 id 가 없다. 언제나 <b>토큰의 주인</b>이다. 남의 동의를
 *       읽거나 적는 길이 없다.</li>
 *   <li><b>rate limit</b> — {@code PUT} 은 {@code group-write} 버킷이다
 *       ({@code ApiRateLimitFilter.resolveRule}). 요청 한 건이 행을 만들기 때문이고,
 *       {@code POST /api/dogs} 와 같은 판단이다. {@code GET} 은 다른 인증 읽기와 같이 버킷이
 *       없다 — 앱이 로그인 때 한 번 부른다.</li>
 * </ul>
 *
 * <h2>{@code PUT} 인 이유</h2>
 * <p>동의 화면이 넷을 한 번에 보낸다. "지금 상태를 이렇게 둔다" 는 뜻이라 {@code PUT} 이
 * 맞고, 서버 쪽에서는 그것이 <b>새 행 추가</b>로 구현된다(이력). 같은 요청을 두 번 보내면
 * 행이 둘 쌓이지만 "지금 상태" 는 같다 — 그 뜻에서 멱등이다.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/consents")
public class ConsentController {

    private final ConsentService consents;

    /** 내 동의 상태 — 문서별 마지막 기록. 한 번도 안 적은 문서는 목록에 없다. */
    @GetMapping
    public ConsentsResponse current(@CurrentUser User me) {
        return new ConsentsResponse(consents.current(me.getId()));
    }

    /** 동의(또는 철회)를 남기고 지금 상태를 돌려준다. */
    @PutMapping
    public ConsentsResponse record(@CurrentUser User me, @Valid @RequestBody ConsentsRequest body) {
        return new ConsentsResponse(consents.record(me.getId(), body.consents()));
    }
}
