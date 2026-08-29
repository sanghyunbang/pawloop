package com.heattrip.heat_trip_backend.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

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
        private String ipHeader = "X-Forwarded-For";
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
