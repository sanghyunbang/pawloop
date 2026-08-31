/**
 * 채팅 도메인 — 이슈 #74 · #75 · #78 · #79.
 *
 * <h2>이 모듈은 아무도 부르지 않는다</h2>
 * <p>{@code allowedDependencies = {}} 는 <b>빈 배열</b>이고, 속성을 안 쓴 것과 다르다.
 * 안 쓰면 "제한 없음", 빈 배열은 "다른 모듈을 하나도 못 부른다" 이다. 여기는 후자다.
 *
 * <p>이건 새 제약이 아니라 <b>이미 지켜지고 있는 것을 애노테이션으로 옮겨 적은 것</b>이다.
 * {@code ChatBoundaryArchitectureTest} 의 §B 가 "chat 의 main 소스 어디에도 다른 도메인
 * 패키지 이름이 나오면 안 된다" 를 import 든 완전수식명이든 상관없이 막고 있고, 실측으로
 * {@code chat} 이 다른 모듈로 나가는 참조는 0건이다. 나가는 화살표가 없는 유일한 도메인이다.
 *
 * <h2>그러면 도구가 둘인가</h2>
 * <p>그렇다. 그리고 그건 의도다(ADR-0012 §5 "나쁜 점" 1번). 두 검사가 보는 것이 다르다.
 * <ul>
 *   <li>{@code @ApplicationModule} — 모듈 <b>사이</b>의 의존 방향. 바이트코드를 본다.</li>
 *   <li>{@code ChatBoundaryArchitectureTest} §C·§D — 쿼리 문자열과 정본 SQL. 바이트코드에
 *       안 남는 것들이라 구조 검사로는 절대 못 잡는다.</li>
 * </ul>
 * 그래서 저 테스트는 이 애노테이션으로 대체되지 않는다.
 *
 * <h2>HTTP 표면은 여기 없다</h2>
 * <p>컨트롤러는 {@code chatweb} 에 있다. 왜 밖으로 뺐는지는 그쪽
 * {@code package-info.java} 에 적혀 있다 — 인증 주체 해석 때문이고, §B 에 예외를 여는 대신
 * 층을 얇게 얹는 쪽을 골랐다.
 */
@ApplicationModule(displayName = "Chat", allowedDependencies = {})
package com.heattrip.heat_trip_backend.chat;

import org.springframework.modulith.ApplicationModule;
