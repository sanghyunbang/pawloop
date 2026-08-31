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
}
