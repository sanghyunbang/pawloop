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
 * <p>그래서 방향을 반대로 뒤집는 대신 <b>층을 하나 얇게 얹었다.</b> 이 패키지가 하는 일은 셋이다.
 * <ol>
 *   <li>토큰이 가리키는 사용자를 {@code long userId} 로 바꾼다,</li>
 *   <li>{@code ChatRoomService} 를 부른다,</li>
 *   <li>돌아온 값 레코드를 계약({@code openapi.yaml})의 모양으로 옮긴다.</li>
 * </ol>
 *
 * <h2>여기 있는 판정과 트랜잭션 — 셋뿐이고, 셋 다 이유가 같다</h2>
 * <p><b>이 문단은 원래 "판정도 트랜잭션도 여기 없다" 였다.</b> 그 말이 거짓이 된 것을 #518 이
 * 찾았다. 선언이 다음 사람의 기준인데 그 선언이 틀리면, 그 사람은 <b>있는 것을 없다고 읽고</b>
 * 같은 판정을 한 번 더 만든다. 지금 사실로 적는다.
 *
 * <p>셋의 이유는 하나다 — <b>{@code chat} 이 못 보는 것을 함께 봐야 하는 일</b>이다. 그것이
 * 이 패키지가 존재하는 이유이기도 하다(위 문단). 그래서 이 셋은 경계가 잘못 그어졌다는 신호가
 * <b>아니다.</b>
 * <ul>
 *   <li><b>트랜잭션 하나</b> — {@code ChatMessages} 가 메시지 삭제(톰스톤)와 사진 제거를 한
 *       경계에 묶는다. {@code chat} 은 {@code S3} 를 못 보므로 그 둘을 한 트랜잭션에 담을 수
 *       있는 자리가 여기뿐이다. <b>S3 호출은 그 트랜잭션 안에 없다</b> — 객체 삭제는 커밋
 *       뒤다(#512, {@code MediaService.remove}).</li>
 *   <li><b>요청 모양 판정 하나</b> — {@code contentTypeOf} 가 "사진이 있는데 종류가 text" 같은
 *       <b>요청 자체의 앞뒤가 안 맞는 경우</b>를 400 으로 거른다(#452). 이것은 도메인 규칙이
 *       아니라 계약의 모양이고, 모양을 보는 것이 어댑터의 일이다.</li>
 *   <li><b>만 14세 미만 정책 하나</b> — {@code MinorRoomPolicy}. 나이대({@code users})와 방의
 *       종류({@code origin_kind} 해석)를 <b>둘 다</b> 봐야 하는데 {@code chat} 은 둘 다 못
 *       본다(ADR-0011 결정 4 · {@code FamilyGroupService.ORIGIN_KIND} javadoc). 그 클래스의
 *       javadoc 이 같은 이유를 적어 뒀다.</li>
 * </ul>
 *
 * <p><b>그 밖의 판정과 트랜잭션은 {@code ChatRoomService} 안이다.</b> 인가(멤버인가 · 방장인가),
 * 순서와 번호({@code room_seq} · {@code last_change_seq}), 락 순서가 전부 거기 있다. 여기에
 * 그런 것이 생기기 시작하면 그때가 경계가 잘못 그어졌다는 신호다.
 *
 * <p>방향은 여전히 한쪽이다. 이 패키지는 chat 을 알고, chat 은 이 패키지를 모른다 —
 * {@code chatweb} 은 {@code chat} 이 아니므로 §B 의 금지 목록에 그대로 걸린다.
 *
 * <h2>모듈 선언 (#103 · ADR-0012)</h2>
 * <p>{@code "chat"} 은 이 패키지가 {@code chat} 모듈을 부른다는 선언이다.
 * 실측으로 {@code chatweb -> chat} 참조는 전부 {@code chat} 패키지 바로 아래 타입이고
 * {@code chat.entity} / {@code chat.repository} 를 부르는 것은 0건이다 — 위 문단이 적어 둔
 * "방향은 여전히 한쪽" 이 도구로도 확인된다.
 *
 * <p><b>{@code OAuth} 는 이제 여기 없다.</b> #107 이 {@code CurrentUser} 를 {@code user} 로
 * 옮기면서 이 패키지의 {@code OAuth} 의존이 <b>통째로 사라졌다.</b> 원래 이 패키지가
 * {@code OAuth} 에서 쓰던 것은 그 애노테이션 하나뿐이었다.
 *
 * <p>{@code "user"} 는 {@code user} 패키지 <b>루트</b>의 타입을 연다 — {@code CurrentUser} 와
 * {@code UnauthenticatedException} 이 거기 있다. {@code "user :: entity"} 는 그와 별개로
 * 이름 붙은 표면 하나를 더 여는 것이다({@code User}). <b>루트와 이름 붙은 표면은 따로 열어야
 * 한다</b> — {@code "user"} 만 적으면 {@code User} 를 못 부른다.
 *
 * <p><b>{@code user.repository.UserRepository} 는 아직 위반으로 남아 있다.</b>
 * {@code ChatSenderNames} 가 그걸 직접 부른다. 리포지토리를 남이 직접 부르는 것은 공용 어휘가
 * 아니라 그냥 새는 것이라 허용으로 덮지 않았다. 이 패키지가 필요한 것은 "userId 로 닉네임을
 * 얻는 것" 이므로, {@code user} 쪽이 그 일을 하는 표면을 내주는 것이 맞다.
 *
 * <p><b>{@code "S3"} 는 말풍선 사진(#452) 때문에 열었다.</b> {@code chat} 은 경계 밖을 못 보므로 사진을
 * 메시지에 붙이고 읽는 것은 이 패키지({@code ChatMessages})다 — 이름·가리기와 같은 자리. 부르는 것은
 * {@code S3} 루트의 {@code MediaAttachment}(그 안의 {@code AttachedMedia}·{@code Kind})뿐이고
 * {@code S3.media} 는 안 본다 — {@code walk}·{@code community} 가 쓰는 것과 같은 표면이다.
 */
@ApplicationModule(
        displayName = "Chat Web Adapter",
        allowedDependencies = { "chat", "moderation", "user", "user :: entity", "S3" })
package com.heattrip.heat_trip_backend.chatweb;

import org.springframework.modulith.ApplicationModule;
