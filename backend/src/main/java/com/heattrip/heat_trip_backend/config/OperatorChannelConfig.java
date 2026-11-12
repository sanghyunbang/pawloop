package com.heattrip.heat_trip_backend.config;

import org.apache.catalina.connector.Connector;
import org.apache.coyote.AbstractProtocol;
import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.WebServerFactoryCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 운영자 커넥터를 연다 — 이슈 #718. 왜 따로 여는지는 {@link OperatorChannel} 에 있다.
 *
 * <p>{@code management.server.port}(액추에이터 전용 포트)를 쓰지 않는 이유: 그것을 켜면 헬스·지표가 8080
 * 에서 빠져 리버스 프록시의 헬스 경로, 컴포즈의 헬스체크, 지표 수집이 한꺼번에 깨진다. 여기서는 같은
 * 애플리케이션에 커넥터만 하나 더한다 — 같은 컨트롤러·같은 보안 체인을 지나고, 다른 것은 들어온 포트뿐이다.
 *
 * <p>꺼져 있으면({@code app.operator.port=0}) 아무것도 더하지 않는다. 테스트와 개발의 기본이 그렇다.
 */
@Configuration
public class OperatorChannelConfig {

    @Bean
    public WebServerFactoryCustomizer<TomcatServletWebServerFactory> operatorConnector(OperatorChannel channel) {
        return factory -> {
            if (!channel.enabled()) {
                return;
            }
            factory.addAdditionalTomcatConnectors(loopbackConnector(channel.port()));
        };
    }

    /**
     * 루프백에만 묶인 커넥터. 주소를 못 정하면 열지 않고 기동을 멈춘다 — 모든 주소({@code 0.0.0.0})에 열린
     * 운영자 커넥터는 이 설계에서 가장 나쁜 실패다.
     */
    static Connector loopbackConnector(int port) {
        Connector connector = new Connector(TomcatServletWebServerFactory.DEFAULT_PROTOCOL);
        connector.setPort(port);
        if (!(connector.getProtocolHandler() instanceof AbstractProtocol<?> protocol)) {
            throw new IllegalStateException("운영자 커넥터의 주소를 루프백으로 묶을 수 없습니다: "
                    + connector.getProtocolHandler().getClass().getName());
        }
        protocol.setAddress(OperatorChannel.LOOPBACK);
        return connector;
    }
}
