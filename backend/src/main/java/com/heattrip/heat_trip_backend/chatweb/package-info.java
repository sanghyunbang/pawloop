/**
 * chat 모듈의 <b>HTTP 어댑터</b> — 이슈 #75.
 *
 * <h2>왜 {@code chat} 패키지 안이 아닌가</h2>
 * <p>컨트롤러는 인증 주체를 해석해야 하고, 이 저장소에서 그 일을 하는 것은
 * {@code OAuth.principal.CurrentUser} 하나다(#5 가 컨트롤러 8곳의 중복 해석을 걷어내고 만든
 * 단일 지점이다). 그런데 {@code ChatBoundaryArchitectureTest} 의 §B 는 <b>chat 의 main 소스
 * 어디에도 다른 도메인 패키지 이름이 나오면 안 된다</b>고 못 박는다 — import 든 완전수식명이든.
 *
 * <p>그 규칙에 "{@code OAuth.principal} 은 예외" 를 다는 선택지가 있었다. 고르지 않았다.
 * §B 의 javadoc 이 <b>줄 단위 import 판정을 버린 이유</b>를 적어 놨다: 예외를 하나 열면 다음
 * 사람은 그 예외가 어디까지인지를 판단해야 하고, 그 판단은 결국 리뷰어의 기억력에 걸린다
 * (📌 #86 원칙 6). 게이트가 무디기 때문에 값을 하는 자리다.
 *
 * <p>그래서 방향을 반대로 뒤집는 대신 <b>층을 하나 얇게 얹었다.</b> 이 패키지는 셋만 한다.
 * <ol>
 *   <li>토큰이 가리키는 사용자를 {@code long userId} 로 바꾼다,</li>
 *   <li>{@code ChatRoomService} 를 부른다,</li>
 *   <li>돌아온 값 레코드를 계약({@code openapi.yaml})의 모양으로 옮긴다.</li>
 * </ol>
 * 판정도 트랜잭션도 여기 없다 — 전부 {@code ChatRoomService} 안이다. 이 패키지가 두꺼워지기
 * 시작하면 그것이 경계가 잘못 그어졌다는 신호다.
 *
 * <p>방향은 여전히 한쪽이다. 이 패키지는 chat 을 알고, chat 은 이 패키지를 모른다 —
 * {@code chatweb} 은 {@code chat} 이 아니므로 §B 의 금지 목록에 그대로 걸린다.
 *
 * <h2>모듈 선언 (#103 · ADR-0012)</h2>
 * <p>{@code allowedDependencies = { "chat" }} 는 <b>이 패키지가 chat 만 부른다</b>는 선언이다.
 * 실측으로 {@code chatweb -> chat} 참조는 전부 {@code chat} 패키지 바로 아래 타입이고
 * {@code chat.entity} / {@code chat.repository} 를 부르는 것은 0건이다 — 위 문단이 적어 둔
 * "방향은 여전히 한쪽" 이 도구로도 확인된다.
 *
 * <p>{@code OAuth} 와 {@code user} 는 아직 여기 없다. 이 패키지가 그 둘을 부르는 것은 맞지만,
 * 그건 <b>그 두 모듈이 공개 표면을 안 갖고 있어서</b> 생기는 위반이라 여기서 허용으로 덮으면
 * 원인이 가려진다. 표면을 정하는 것은 #104 · #105 다.
 */
@ApplicationModule(displayName = "Chat Web Adapter", allowedDependencies = { "chat" })
package com.heattrip.heat_trip_backend.chatweb;

import org.springframework.modulith.ApplicationModule;
