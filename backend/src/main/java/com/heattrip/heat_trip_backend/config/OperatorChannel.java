package com.heattrip.heat_trip_backend.config;

import java.net.InetAddress;
import java.net.UnknownHostException;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import jakarta.servlet.http.HttpServletRequest;

/**
 * 운영자 통로 — 이슈 #718.
 *
 * <h2>왜 앱 안에 관리자가 없나</h2>
 * <p>신고된 글을 지우고 사람을 정지시키는 길(애플 지침 1.2 — "24시간 안에 콘텐츠를 내리고 작성자를
 * 내보낸다")이 필요하다. 그런데 그 권한을 <b>토큰</b>에 실으면 토큰을 훔치거나, {@code users.role} 칸을 쓰는
 * 버그 하나로 남의 글을 지울 수 있게 된다 — 토큰을 만드는 세 곳이 전부 그 칸을 JWT 의 {@code role} 로
 * 복사한다. 그래서 운영자 경로({@code /internal/**})는 <b>누가</b> 불렀는지가 아니라 <b>어디로</b> 들어왔는지만
 * 본다.
 *
 * <h2>어디로 — 컨테이너 안의 루프백에만 묶인 두 번째 커넥터</h2>
 * <p>{@link OperatorChannelConfig} 가 {@link #port()} 에 커넥터를 하나 더 열고 {@link #LOOPBACK} 에만 묶는다.
 * 그 주소는 앱 컨테이너 안에서만 닿는다 — 리버스 프록시도, 호스트도, 다른 컨테이너도 못 닿는다. 운영자는
 * 서버에 들어가 {@code docker exec … curl} 로 부른다({@code backend/scripts/moderate.sh}). 그러니 이 통로를
 * 쓸 수 있는 사람은 서버에 들어갈 수 있는 사람과 같다 — 그 사람은 이미 DB 를 직접 만질 수 있으므로, 이 통로가
 * 새로 주는 권한은 없다.
 *
 * <h2>판정은 소켓의 포트로 — {@link #carries}</h2>
 * <p>{@link HttpServletRequest#getLocalPort()} 는 요청을 받은 소켓 자신의 포트다. 헤더로 바꿀 수 없다 — 이
 * 앱에는 {@code server.forward-headers-strategy} 도 RemoteIpValve 도 없다. 그런 설정을 켜는 날에도
 * RemoteIpValve 는 기본으로 로컬 포트를 안 바꾼다({@code changeLocalPort=false}).
 *
 * <p>포트가 0 이면 통로가 꺼진 것이고, 그때는 어떤 요청도 운영자 경로에 못 들어간다 — {@code port > 0} 을
 * 빼면 커넥터가 없는데도 "로컬 포트 0" 인 요청(테스트의 가짜 요청 같은)이 통과할 수 있다.
 *
 * <h2>켜는 곳</h2>
 * <p>{@code app.operator.port} — 기본 0(꺼짐). 운영 프로필만 9091 을 기본으로 둔다
 * ({@code application-prod.properties}). 운영 설정 저장소를 고치지 않아도 배포하면 켜진다.
 */
@Component
public class OperatorChannel {

    /** 운영자 경로의 접두사. {@code SecurityConfig} 의 규칙과 컨트롤러가 이것을 쓴다. */
    public static final String PATH_PATTERN = "/internal/**";

    /** 커넥터를 묶는 주소 — IPv4 루프백. 이름 조회를 안 거치게 바이트로 만든다. */
    static final InetAddress LOOPBACK = loopback();

    private final int port;

    public OperatorChannel(@Value("${app.operator.port:0}") int port,
                           @Value("${server.port:8080}") int serverPort) {
        if (port < 0 || port > 65_535) {
            throw new IllegalStateException("app.operator.port 는 0(꺼짐) 이거나 1~65535 여야 합니다: " + port);
        }
        if (port != 0 && port == serverPort) {
            // 같은 포트면 커넥터를 둘 열 수 없어 기동이 어차피 죽는다. 그 전에 이유를 말한다.
            throw new IllegalStateException(
                    "app.operator.port 가 server.port(" + serverPort + ") 와 같습니다 — 운영자 통로는 따로 열어야 합니다");
        }
        this.port = port;
    }

    /** 통로가 켜졌는가. */
    public boolean enabled() {
        return port > 0;
    }

    /** 운영자 커넥터의 포트. 꺼졌으면 0. */
    public int port() {
        return port;
    }

    /** 이 요청이 운영자 커넥터로 들어왔는가. 꺼졌으면 언제나 거짓이다. */
    public boolean carries(HttpServletRequest request) {
        return port > 0 && request.getLocalPort() == port;
    }

    private static InetAddress loopback() {
        try {
            return InetAddress.getByAddress(new byte[] {127, 0, 0, 1});
        } catch (UnknownHostException impossible) {
            // 길이 4 인 바이트 배열에는 던지지 않는다.
            throw new IllegalStateException(impossible);
        }
    }
}
