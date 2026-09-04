package com.heattrip.heat_trip_backend.security;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.ArrayList;
import java.util.List;

/**
 * 레이트리밋 설정 — {@code app.security.rate-limit.*}.
 *
 * <h2>왜 {@code config} 가 아니라 여기인가</h2>
 * <p>원래 {@code config.PublicSecurityProperties} 의 중첩 클래스였다. 그러면
 * {@code security} 가 {@code config} 를 알아야 하고, {@code config.SecurityConfig} 는 필터 체인을
 * 조립하려고 {@code security.ApiRateLimitFilter} 를 안다. <b>양쪽이 서로를 아는 순환</b>이다. (#106)
 *
 * <p>방향을 하나로 정했다 — <b>조립하는 쪽이 조립되는 쪽을 안다.</b> {@code SecurityConfig} 가
 * 필터를 아는 것은 자연스럽고, 필터가 애플리케이션 설정 클래스를 아는 것은 부자연스럽다.
 * 그래서 이 설정은 그것을 쓰는 모듈 안에 둔다.
 *
 * <p><b>설정 키는 한 글자도 안 바뀌었다.</b> 예전에는 {@code app.security} 접두사에 중첩 필드
 * {@code rateLimit} 이라 {@code app.security.rate-limit.*} 였고, 지금은 접두사가 통째로
 * {@code app.security.rate-limit} 이다. 바인딩 결과가 같다 —
 * {@code OAuthSecurityPropertiesBindingTest} 가 실제 값으로 확인한다.
 * 운영 환경변수({@code APP_SECURITY_RATE_LIMIT_*})도 그대로다.
 */
@Getter
@Setter
@ConfigurationProperties(prefix = "app.security.rate-limit")
public class RateLimitProperties {

    private boolean enabled = true;

    /**
     * 클라이언트 IP 를 실어 오는 헤더. <b>기본값이 {@code X-Real-IP} 인 것은 의도다.</b> (이슈 #14)
     *
     * <p>예전 기본값은 {@code X-Forwarded-For} 였고, 필터는 그 값의 <b>첫 원소</b>를 취했다.
     * 이 저장소의 nginx 템플릿은 {@code proxy_set_header X-Forwarded-For
     * $proxy_add_x_forwarded_for} 인데, nginx 의 그 변수는 <b>클라이언트가 보낸 값 뒤에</b>
     * 실제 IP 를 덧붙인다. 즉 첫 원소는 배포된 환경에서도 <b>공격자가 정하는 문자열</b>이었고,
     * 요청마다 다른 값을 적으면 카운터가 갈라져 한도가 통째로 사라졌다(429 0건 / 1000 요청).
     *
     * <p>같은 템플릿이 {@code proxy_set_header X-Real-IP $remote_addr} 로 이 헤더를
     * <b>덮어쓴다</b>. 덮어쓰기라 클라이언트가 무엇을 보내든 프록시가 본 주소만 남는다.
     *
     * <p>{@code X-Forwarded-For} 로 되돌리더라도 필터는 이제 <b>마지막</b> 원소를 취하고,
     * {@link #trustedProxies} 밖에서 온 연결의 헤더는 아예 읽지 않는다.
     */
    private String ipHeader = "X-Real-IP";

    /**
     * {@link #ipHeader} 를 믿어도 되는 <b>연결 반대편</b>의 주소 대역(CIDR).
     *
     * <p>헤더는 요청을 보낸 쪽이 적는 문자열이라 그 자체로는 아무것도 증명하지 않는다.
     * 증명할 수 있는 값은 {@code request.getRemoteAddr()} 하나뿐이므로, 그 주소가 이
     * 목록 안에 있을 때만 헤더를 해석한다. 밖이면 헤더를 무시하고 실제 연결 주소를 쓴다.
     *
     * <p>기본값은 루프백과 사설 대역이다 — nginx 가 같은 호스트({@code 127.0.0.1}),
     * 도커 브리지 너머({@code 172.17.0.1}), 사설망의 다른 호스트({@code 10.x}) 인
     * 세 배포 형태를 덮는다. <b>공인 대역을 넣지 말 것</b>: 넣는 순간 그 대역의 누구나
     * 헤더로 자기 IP 를 정할 수 있고, 이 목록이 있는 이유가 사라진다.
     */
    private List<String> trustedProxies = new ArrayList<>(List.of(
            "127.0.0.1/32",
            "::1/128",
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16"));

    private long windowSeconds = 60;
    private int loginMaxRequests = 10;

    /**
     * 인증 버킷의 창당 한도 — {@code POST /auth/token/refresh},
     * {@code POST /auth/oauth/{provider}/callback}, {@code /oauth2/authorization/*}.
     *
     * <p>버킷을 셋이 공유하는 것은 의도다. 셋 다 "자격증명을 만들거나 바꾸는" 경로이고,
     * 정상 클라이언트가 한 창(기본 60초) 안에 이 셋을 합쳐 20번 넘게 두드릴 일이 없다.
     * 로그인(10)보다 넉넉한 이유는 갱신이 <b>앱이 자동으로</b> 때리는 경로라서다 —
     * 사람이 누르는 로그인과 달리 화면 전환이 겹치면 짧은 시간에 몇 번 몰릴 수 있다.
     *
     * <p><b>알려진 한계:</b> 카운터의 열쇠는 IP 다. 같은 공유 IP(사내망·CGNAT) 뒤의
     * 사용자들이 한 버킷을 나눠 쓴다. 그 상황에서 한도를 낮게 잡으면 정상 사용자가
     * 갱신에 실패해 로그아웃되므로, 낮추기 전에 실측을 보라.
     */
    private int authMaxRequests = 20;
    private int curationMaxRequests = 30;
    private int uploadMaxRequests = 20;
    private int feedbackMaxRequests = 30;
    private int searchMaxRequests = 120;

    /**
     * {@code /api/explore/places} 의 읽기 다섯 — 이슈 #232. 분당 120.
     *
     * <p><b>이 경로들은 인증이 없다</b>({@code SecurityConfig.PUBLIC_MATCHERS} 의
     * {@code /api/explore/**}). 남은 방어선이 한도 하나뿐인데, 2026-09-03 이전에는 표에
     * 아예 없어서 <b>인증도 한도도 없는 경로 다섯</b>이었다 — 표에 없으면 한도가 0 이 아니라
     * 무한이다.
     *
     * <p>숫자가 {@link #searchMaxRequests} 와 같은 것은 <b>같은 도메인·같은 비용 등급</b>
     * 이라서다 — 둘 다 인증 없이 DB 만 읽는다. {@code places}(60)·{@code places-detail}(30)
     * 보다 넉넉한 이유는 그쪽이 KTO 일일 예산을 태우기 때문이고, 여기는 안 태운다.
     *
     * <p><b>검색과 버킷을 합치지 않는다.</b> 하나가 소진돼도 다른 하나가 살아 있어야 한다 —
     * 목록을 스크롤하다 검색이 막히면 사용자는 앱이 고장 난 것으로 읽는다.
     */
    private int exploreReadMaxRequests = 120;

    /**
     * 가족·채팅 쓰기 버킷의 창당 한도 — {@code POST /api/groups},
     * {@code POST /api/chat/rooms/{roomId}/invites}. (이슈 #75)
     *
     * <p>둘 다 요청 한 건이 <b>행을 만드는</b> 경로다. 표에 없던 동안 실제로 무제한이었고
     * (한 계정으로 200번씩 불러 429 가 0건), 그 상태는 {@code POST /auth/signup} 이
     * 무제한이었던 것과 같은 모양이다(📌 #86 원칙 4).
     *
     * <p>30 인 이유: 사람이 가족을 만들거나 초대 링크를 새로 뽑는 것은 한 창(기본 60초)에
     * 몇 번이면 충분하고, 30 이면 화면을 잘못 눌러 몇 번 반복하는 정상 사용자는 절대
     * 닿지 않는다. 낮추면 "가족 만들기가 가끔 안 돼요" 가 되고, 이 한도의 목적은 사람을
     * 막는 것이 아니라 <b>스크립트가 행을 무한히 만드는 것</b>을 막는 것이다.
     *
     * <p><b>계정 기준 상한이 아니다.</b> 카운터의 열쇠는 IP 라, 계정 하나가 만들 수 있는
     * 방의 총 개수를 정하지는 못한다. 그 상한은 {@code ChatLimits} 자리에 두는 것이 맞고
     * (한도의 출처가 한 곳), 지금은 "이미 가족이 있으면 409"({@code FamilyGroupService})
     * 가 그 역할의 대부분을 한다.
     */
    private int groupWriteMaxRequests = 30;

    /**
     * 산책 쓰기 버킷 — {@code POST /api/walks} · {@code DELETE /api/walks/{walkId}}. (이슈 #145)
     *
     * <p><b>{@code group-write} 에 얹지 않았다.</b> 성격이 다르다 — 산책 저장은
     * <b>오프라인 큐가 한 번에 여러 건을 밀어 넣는다.</b> 지하철에서 걸어 하루 못 보낸 것이
     * 쌓였다가 신호가 잡히는 순간 한꺼번에 나가는 것이 <b>정상 동작</b>이다. 가족 만들기와
     * 같은 숫자로 묶으면 그 순간 정상 사용자가 <b>자기 기록을 못 올린다.</b>
     *
     * <p>60 인 이유: 하루에 산책을 60번 하는 사람은 없으므로 이 숫자가 막는 것은 사람이
     * 아니라 <b>스크립트가 행을 무한히 만드는 것</b>이다. 동시에 밀린 큐 하나(며칠치라도
     * 수십 건)는 한 창 안에 다 나간다. 낮추면 "며칠 만에 켰더니 기록이 일부만 올라갔어요"
     * 가 되고, 그건 이 이슈가 없애려던 바로 그 경험이다.
     *
     * <p><b>계정 기준 상한이 아니다.</b> 카운터의 열쇠는 IP 다. 계정 하나가 만들 수 있는
     * 산책의 총 개수는 여기서 정해지지 않는다 — 지금 그것을 막는 것은
     * {@code uq_walk_client}(같은 산책이 두 줄이 되지 않는다)뿐이다.
     */
    private int walkWriteMaxRequests = 60;

    /**
     * 채팅 폴링 버킷 — {@code GET /api/chat/rooms} · {@code GET /rooms/{id}/messages} ·
     * {@code POST /rooms/{id}/read}. (이슈 #80)
     *
     * <p><b>이 셋만 사용자 단위로 센다.</b> {@link ChatRateLimitFilter} 가 인증 뒤에 있어서
     * 가능하다. 나머지 버킷은 IP 로 세는데, 채팅은 가족 넷이 한 공유기에서 동시에 폴링하는 것이
     * 정상 사용이라 IP 로 세면 넷이 한 카운터로 합쳐진다.
     *
     * <p>120 인 이유: #81 의 폴링 정책이 방을 보는 중 3초다. 스트림 하나당 분당 20회,
     * 방 목록과 메시지를 함께 보면 40회, 화면 전환과 포그라운드 복귀를 더해도 60회를 넘기
     * 어렵다. 정상 사용자의 두 배를 준다.
     *
     * <p>낮추기 전에 {@code chat.poll} 메트릭의 {@code result=empty} 비율을 보라. 빈 응답이
     * 대부분이면 한도를 낮출 것이 아니라 <b>간격을 늘려야</b> 한다 — 비용은 DB 를 읽는 것이
     * 아니라 아무것도 없는데 왕복하는 것이다.
     */
    private int chatPollMaxRequests = 120;

    /**
     * 채팅 전송 버킷 — {@code POST /api/chat/rooms/{id}/messages}. (이슈 #80)
     *
     * <p>60 인 이유: 사람이 1초에 한 번씩 1분 내내 보내는 것이 상한이고 실제로는 훨씬 적다.
     * 이 숫자가 막는 것은 사람이 아니라 <b>스크립트</b>다.
     *
     * <p>전송은 행을 만들고 방 단위 직렬화 지점({@code room_seq})을 지난다. 그래서 폴링과
     * 버킷을 나눈다 — 한쪽을 조일 때 다른 쪽이 함께 조여지면 안 된다.
     */
    private int chatSendMaxRequests = 60;

    /**
     * 초대코드 참여 버킷 — {@code POST /api/chat/invites/{code}/join}. (이슈 #80 · #75)
     *
     * <p>이 경로는 #75 가 "코드 추측 공격을 견디는지는 M2.6 의 rate limit 이슈에서 다룬다" 로
     * 미뤄 둔 자리다. 그동안 <b>무제한이었다</b> — 표에 없는 경로는 한도가 0 이 아니라 무한이다.
     *
     * <p>10 인 이유: 사람이 방에 들어가는 것은 한 번이면 된다. 코드가 잘못됐을 때 다시 치는
     * 것을 감안해도 분당 10회면 충분하다.
     *
     * <p>초대코드는 50비트라({@code InviteCodeGenerator}) 추측이 현실적이지 않다. 그래도
     * <b>그 하나에만 기대지 않는다</b> — 길이가 줄어드는 변경이 언젠가 올 수 있고, 그때 이
     * 한도가 두 번째 벽이 된다.
     */
    private int chatJoinMaxRequests = 10;

    /**
     * 신고 버킷 — {@code POST /api/chat/rooms/{id}/reports}. (이슈 #82)
     *
     * <p>신고는 <b>쓰기</b>다. 한 사람이 같은 방을 계속 신고하면 운영자가 봐야 할 표가 그만큼
     * 늘고, 그건 진짜 신고를 묻는 방식의 공격이 된다.
     *
     * <p>10 인 이유: 사람이 한 방에서 분당 10건을 신고할 일이 없다. 한 신고에 메시지를 3개까지
     * 담을 수 있으니({@code ChatReportService#MAX_MESSAGES_PER_REPORT}) 분당 30개까지는 정상
     * 경로로 신고할 수 있다.
     *
     * <p>참여 버킷과 같은 숫자인 것은 우연이 아니다 — 둘 다 "사람이 손으로 하는 드문 행동" 이다.
     * 다만 <b>버킷을 따로 두는 이유</b>는 하나가 소진돼도 다른 하나가 살아 있어야 하기
     * 때문이다. 신고를 쏟아부어 방 참여를 막을 수 있으면 안 된다.
     */
    private int chatReportMaxRequests = 10;

    /**
     * 커뮤니티 신고 — 이슈 #166. 분당 10.
     *
     * <p><b>커뮤니티 쓰기(60)와 합치지 않는다.</b> 합치면 글·댓글·반응을 쏟아부어 <b>신고를
     * 막을 수 있다</b> — 신고 수단을 없애는 가장 값싼 방법이 그것이다. {@code chat-report} 가
     * 같은 이유로 채팅 쓰기와 갈라져 있다.
     *
     * <p>숫자가 채팅과 같은 것도 같은 근거다 — 신고는 "사람이 손으로 하는 드문 행동" 이다.
     * 그리고 요청 하나가 <b>본문 사본 행</b>을 만드는 무거운 쓰기라, 글쓰기와 같은 한도를
     * 주는 것이 헐겁다.
     */
    private int communityReportMaxRequests = 10;

    /**
     * 주변 장소 버킷 — {@code GET /api/places/nearby}. (이슈 #40)
     *
     * <p>지도 화면이 부르는 경로다. 앱의 산책 화면은 위치가 5m 움직일 때마다 다시 묻고,
     * 격자 캐시가 그 대부분을 흡수하지만 <b>요청 자체는 그대로 온다.</b>
     *
     * <p>60 인 이유: 산책 중 분당 13~27회가 실측 범위이고 거기에 여유를 뒀다. 앱이 그
     * 재호출을 고치면 30 으로 내릴 수 있다.
     *
     * <p><b>이 한도가 KTO 쿼터를 지키는 것이 아니다.</b> 그건 {@code KtoCallBudget} 의 일이고,
     * 여기는 우리 서버가 한 IP 에 잡아먹히는 것을 막는다. 둘은 다른 것을 지킨다.
     */
    private int placesMaxRequests = 60;

    /**
     * 장소 상세 버킷 — {@code GET /api/places/&#123;contentId&#125;}. (이슈 #40)
     *
     * <p>버킷을 <b>따로</b> 두는 이유: 상세를 쏟아부어 지도를 막을 수 없어야 한다.
     * 사람이 상세를 여는 빈도는 지도를 보는 빈도보다 훨씬 낮으므로 30 이면 넉넉하다.
     */
    private int placesDetailMaxRequests = 30;

    /**
     * 전국 카탈로그 버킷 — {@code GET /api/places/catalog}. (이슈 #273)
     *
     * <p><b>이 경로만 응답이 메가바이트 단위다.</b> 전국 한 벌이 2.83MB, gzip 0.44MB 다
     * (실측 2026-09-04). 다른 버킷과 같은 숫자를 주면 안 되는 이유가 그것이다 —
     * {@code places-detail} 의 30 을 그대로 받으면 한 IP 가 분당 85MB 를 뽑아 간다.
     *
     * <p>5 인 이유: 앱은 이 경로를 <b>하루에 한 번쯤</b> 부른다. 기기에 한 벌을 두고
     * {@code If-None-Match} 로 갱신만 확인하기 때문이다. 분당 5 는 앱을 껐다 켜기를
     * 반복해도 남는 여유이고, 그보다 잦게 부르는 것은 정상 사용이 아니다.
     *
     * <p><b>304 도 이 한도를 쓴다.</b> 본문이 안 나가도 요청은 왔고, 그 판정을 하려면
     * 서버가 행을 읽어야 한다. 429 를 받은 앱은 기기에 있는 한 벌을 계속 쓰면 된다 —
     * 지도가 죽지 않는다.
     */
    private int placesCatalogMaxRequests = 5;

    /**
     * 커뮤니티 읽기 버킷 — {@code GET /api/community/posts} 계열 셋. (이슈 #170)
     *
     * <p><b>이 버킷이 없으면 한도가 0 이 아니라 무한이다.</b> 표에 없는 경로는
     * {@code resolveRule} 이 {@code null} 을 돌려주고 필터가 그대로 통과시킨다. 지금까지
     * 커뮤니티 읽기를 막고 있던 것은 {@code anyRequest().authenticated()} 였는데,
     * ADR-0016 결정 3 이 그것을 게스트에게 열면서 <b>그 방어선이 사라진다.</b>
     *
     * <p>{@code POST /api/groups} 와 초대 발급이 정확히 그 상태였다 — 한 계정으로 200번
     * 불러 429 가 0건이었다(#75). 같은 사고를 세 번 반복하지 않는 자리다.
     *
     * <p>120 인 이유: 목록·상세·댓글을 오가는 화면이라 한 창(기본 60초)에 수십 번이
     * 정상이고, 검색 버킷과 같은 급이다. <b>인증이 없는 경로라 열쇠가 IP 뿐</b>이므로
     * 너무 조이면 같은 공유기 뒤의 여러 사람이 서로를 막는다.
     */
    private int communityReadMaxRequests = 120;

    /**
     * 커뮤니티 쓰기 버킷 — 글·댓글 작성과 반응 둘. (이슈 #170)
     *
     * <p>읽기와 <b>버킷을 나누는 이유</b>는 하나가 소진돼도 다른 하나가 살아 있어야
     * 하기 때문이다. 목록을 새로고침하다 한도에 닿아 글을 못 쓰게 되면 안 된다.
     *
     * <p>반응이 여기 함께 있는 것은 의도다. 멱등이라 같은 요청을 반복해도 행이 안 늘지만,
     * <b>요청 자체는 그대로 오고</b> 매번 집계 쿼리가 돈다.
     *
     * <p>60 인 이유: 사람이 한 창에 글·댓글·반응을 합쳐 60번 넘게 만지는 것은 정상이
     * 아니고, 그 아래로는 반응을 여러 번 눌러 보는 사용자가 걸린다.
     */
    private int communityWriteMaxRequests = 60;
}
