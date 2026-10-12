package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * <b>운영 기본 설정에서</b> {@code POST /api/blocks} 가 안 터지고 알림 경로가 돈다 — 애플 지침 1.2.
 *
 * <p>가짜를 하나도 안 끼운다. 운영이 실제로 도는 설정(신고 웹훅 비어 있음)에서 차단이 201 이고,
 * 안 나간 알림이 실패로 세어지는지 본다 — {@link ReportAlertDefaultConfigIntegrationTest} 와 같은 판단이다.
 *
 * <p><b>HTTP 로 부른다.</b> 커뮤니티의 "차단하기" 와 채팅의 "가리기" 가 둘 다 이 경로를 쓴다 — 서비스를
 * 직접 부르는 {@link BlockAlertIntegrationTest} 로는 그 사실을 못 잰다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} · {@code @AutoConfigureMockMvc} 두 줄뿐인 것은
 * {@code CommunityIntegrationTest} 등과 컨텍스트 캐시를 나누기 위해서다(#21 §5).
 */
@SpringBootTest
@AutoConfigureMockMvc
class BlockAlertDefaultConfigIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private BlockAlertListener listener;
    @Autowired private ObservabilityProperties props;
    @Autowired private UserRepository users;
    @Autowired private JWTProvider jwt;

    @Test
    @DisplayName("신고 웹훅이 비어 있으면 차단은 그대로 201 이고, 안 나간 알림이 '실패' 로 한 번 세어진다")
    void blockingWorksWithAlertsOff() throws Exception {
        assertThat(props.getSlack().getReportWebhookUrl())
                .as("이 검사는 운영 기본값(비어 있음)을 전제한다 — 채워져 있으면 다른 검사가 필요하다")
                .isNullOrEmpty();
        User me = account("차단하는기본");
        User troll = account("차단될기본");
        double before = listener.failureCount();

        block(me, troll.getId());

        waitUntilFailureCountLeaves(before);
        assertThat(listener.failureCount())
                .as("웹훅이 비어 안 나간 것도 '실패' 로 센다 — 켠 줄 알았는데 안 나가는 것을 지표로 본다")
                .isEqualTo(before + 1);
    }

    @Test
    @DisplayName("같은 사람을 다시 차단해도 201 이고, 알림 경로는 다시 안 돈다")
    void aRepeatedBlockOverHttpDoesNotAlertAgain() throws Exception {
        User me = account("다시차단하는");
        User troll = account("다시차단될");
        double before = listener.failureCount();
        block(me, troll.getId());
        waitUntilFailureCountLeaves(before);
        double afterFirst = listener.failureCount();

        block(me, troll.getId());
        Thread.sleep(1_000);

        assertThat(listener.failureCount())
                .as("두 번째 요청은 아무것도 안 바꾼다 — 알림이 또 돌면 운영자는 두 사건으로 읽는다")
                .isEqualTo(afterFirst);
    }

    private void block(User me, long targetUserId) throws Exception {
        mockMvc.perform(post("/api/blocks")
                        .header("Authorization", "Bearer " + jwt.createAccessToken(me.getId(), me.getRole()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":" + targetUserId + "}"))
                .andExpect(status().isCreated());
    }

    /** 실행기 스레드에서 catch 가 도는 순간까지 기다린다. 5초 안에 안 바뀌면 그대로 둔다 — 단언이 말한다. */
    private void waitUntilFailureCountLeaves(double before) throws InterruptedException {
        for (int i = 0; i < 100 && listener.failureCount() == before; i++) {
            Thread.sleep(50);
        }
    }

    private User account(String nickname) {
        return consented(users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("blockalert-%d-%d@example.com".formatted(System.nanoTime(), SEQUENCE.incrementAndGet()))
                .name(nickname)
                .nickname(nickname)
                .build()));
    }
}
