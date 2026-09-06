package com.heattrip.heat_trip_backend.push;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * {@code app.push.*} — 푸시 발송 설정 (이슈 #83).
 *
 * <h2>키 자리는 비어 있어도 된다</h2>
 * <p>Firebase 서비스 계정 키는 사장님이 Firebase 콘솔에서 받는다(절차는 {@code .env.example}).
 * 둘 중 하나로 준다 — 파일 경로({@link Firebase#getCredentialsFile()}) 또는 JSON 을 base64 로 한 줄
 * ({@link Firebase#getCredentialsJson()}). 둘 다 비어 있으면 {@link #isConfigured()} 가 false 이고
 * {@code PushConfig} 가 발송을 끈 클라이언트를 든다. 토큰 등록·설정·음소거는 그대로 저장된다.
 *
 * <h2>상한 둘</h2>
 * <ul>
 *   <li><b>타임아웃</b> — 밖으로 나가는 호출에는 상한이 있어야 한다(#86 원칙 3). 발송 스레드가
 *       FCM 을 기다리다 굳으면 큐가 차고, 그다음 메시지의 알림이 조용히 버려진다.</li>
 *   <li><b>사용자당 살아 있는 토큰 수</b> — 앱을 지우고 다시 깔 때마다 토큰이 새로 나온다.
 *       상한이 없으면 한 사람의 행이 끝없이 늘고 발송 한 번에 죽은 토큰 수십 개를 두드린다.</li>
 * </ul>
 */
@Getter
@Setter
@ConfigurationProperties(prefix = "app.push")
public class PushProperties {

    private final Firebase firebase = new Firebase();

    /** 한 사용자가 동시에 들 수 있는 살아 있는 토큰 수. 넘치면 가장 오래 안 보인 것부터 폐기한다. */
    private int maxActiveTokensPerUser = 10;

    public boolean isConfigured() {
        return firebase.isConfigured();
    }

    @Getter
    @Setter
    public static class Firebase {
        /** 서비스 계정 JSON 파일 경로. 컨테이너라면 마운트한 자리다. */
        private String credentialsFile;
        /** 서비스 계정 JSON 을 base64 로 한 줄. 파일을 못 두는 환경(CI 시크릿)용이다. */
        private String credentialsJson;
        private int connectTimeoutMs = 5_000;
        private int readTimeoutMs = 10_000;

        public boolean isConfigured() {
            return present(credentialsFile) || present(credentialsJson);
        }

        private static boolean present(String value) {
            if (value == null || value.isBlank()) {
                return false;
            }
            String v = value.strip();
            return !v.startsWith("change-me") && !v.startsWith("dev-");
        }
    }
}
