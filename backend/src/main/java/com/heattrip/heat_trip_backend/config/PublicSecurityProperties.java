package com.heattrip.heat_trip_backend.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.ArrayList;
import java.util.List;

@Getter
@Setter
@ConfigurationProperties(prefix = "app.security")
public class PublicSecurityProperties {

    private boolean docsPublic = false;
    private String allowedOrigins = "http://localhost:8080,http://10.0.2.2:8080";
    private RateLimit rateLimit = new RateLimit();

    @Getter
    @Setter
    public static class RateLimit {
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
    }
}
