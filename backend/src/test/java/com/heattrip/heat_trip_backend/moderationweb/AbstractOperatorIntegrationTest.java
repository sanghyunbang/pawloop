package com.heattrip.heat_trip_backend.moderationweb;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.S3.FileStorage;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.concurrent.atomic.AtomicLong;

/**
 * 운영자 경로 통합 테스트의 바닥 — 이슈 #718.
 *
 * <h2>설정을 한 곳에 두는 이유</h2>
 * <p>테스트 컨텍스트는 속성과 {@code @MockitoBean} 으로 캐시 키가 갈린다(#21 §5). 운영자 테스트마다 설정을 따로
 * 적으면 클래스 수만큼 스프링이 새로 뜬다. 여기 하나에 두면 운영자 테스트 전부가 한 컨텍스트를 쓴다.
 *
 * <h2>운영자 커넥터를 흉내 내는 법</h2>
 * <p>가짜 요청의 로컬 포트를 {@code app.operator.port} 와 같게 맞춘다({@link #onOperatorConnector}). 실제
 * 커넥터가 루프백에만 묶이는지는 {@code OperatorConnectorBindingTest} 가 따로 잰다.
 *
 * <h2>{@link FileStorage} 가 목인 이유</h2>
 * <p>글을 지우면 붙은 사진·영상은 커밋 뒤에 S3 에서 지운다. 그 호출이 나갔는지 보려면 목이 있어야 하고, 진짜
 * S3 는 테스트에서 밖이다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = "app.operator.port=" + AbstractOperatorIntegrationTest.OPERATOR_PORT)
abstract class AbstractOperatorIntegrationTest extends AbstractMySqlIntegrationTest {

    static final int OPERATOR_PORT = 19_091;

    /** 이메일·가짜 id 가 겹치지 않게 — 이 바닥을 쓰는 클래스 전부가 한 DB 를 쓴다. */
    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired protected MockMvc mockMvc;
    @Autowired protected UserRepository users;
    @Autowired protected JWTProvider jwtProvider;
    @MockitoBean protected FileStorage storage;

    /** 운영자 커넥터로 들어온 요청. */
    protected static MockHttpServletRequestBuilder onOperatorConnector(MockHttpServletRequestBuilder builder) {
        RequestPostProcessor operatorPort = request -> {
            request.setLocalPort(OPERATOR_PORT);
            return request;
        };
        return builder.with(operatorPort);
    }

    /** 약관에 동의한 사용자 — 커뮤니티 경로가 동의를 요구한다. */
    protected User user(String nickname) {
        return consented(users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("operator-%d@example.com".formatted(nextSerial()))
                .name(nickname)
                .nickname(nickname)
                .ageGroup(User.AgeGroup.OVER14)
                .build()));
    }

    protected String bearer(User user) {
        return "Bearer " + jwtProvider.createAccessToken(user.getId(), user.getRole());
    }

    protected static long nextSerial() {
        return SEQUENCE.incrementAndGet();
    }
}
