package com.heattrip.heat_trip_backend.push.fcm;

import com.heattrip.heat_trip_backend.push.PushMessage;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SDK 없이 결과 해석을 잰다 — 500개씩 자르는가, 죽은 토큰을 가려내는가.
 */
class FirebaseFcmClientTest {

    private static final PushMessage MESSAGE = new PushMessage("방", "본문", Map.of("kind", "chat.message"));

    /** 토큰마다 정해진 답을 주는 전송. 호출마다 받은 묶음을 기록한다. */
    static class ScriptedTransport implements FcmTransport {
        final List<List<String>> batches = new ArrayList<>();
        final Function<String, FcmDelivery> script;

        ScriptedTransport(Function<String, FcmDelivery> script) {
            this.script = script;
        }

        @Override
        public List<FcmDelivery> sendEach(List<String> tokens, PushMessage message) {
            batches.add(List.copyOf(tokens));
            return tokens.stream().map(script).toList();
        }
    }

    @Test
    @DisplayName("토큰 1,001개는 500·500·1 로 잘라 세 번 보낸다 — FCM 의 multicast 상한")
    void chunksByFiveHundred() {
        ScriptedTransport transport = new ScriptedTransport(t -> new FcmDelivery(t, true, null));
        List<String> tokens = IntStream.range(0, 1_001).mapToObj(i -> "tok-" + i).toList();

        FcmSendResult result = new FirebaseFcmClient(transport).send(tokens, MESSAGE);

        assertThat(transport.batches).extracting(List::size).containsExactly(500, 500, 1);
        assertThat(result.delivered()).isEqualTo(1_001);
        assertThat(result.failed()).isZero();
        assertThat(result.unregistered()).isEmpty();
    }

    @Test
    @DisplayName("UNREGISTERED · INVALID_ARGUMENT · SENDER_ID_MISMATCH 만 죽은 토큰이고, UNAVAILABLE 은 실패일 뿐이다")
    void onlyDeadTokenCodesAreReportedForRevocation() {
        ScriptedTransport transport = new ScriptedTransport(t -> switch (t) {
            case "gone" -> new FcmDelivery(t, false, "UNREGISTERED");
            case "garbage" -> new FcmDelivery(t, false, "INVALID_ARGUMENT");
            case "other-project" -> new FcmDelivery(t, false, "SENDER_ID_MISMATCH");
            case "later" -> new FcmDelivery(t, false, "UNAVAILABLE");
            default -> new FcmDelivery(t, true, null);
        });

        FcmSendResult result = new FirebaseFcmClient(transport)
                .send(List.of("ok", "gone", "garbage", "other-project", "later"), MESSAGE);

        assertThat(result.delivered()).isEqualTo(1);
        assertThat(result.failed()).isEqualTo(4);
        assertThat(result.unregistered())
                .as("일시 장애(UNAVAILABLE)로 토큰을 폐기하면 멀쩡한 기기가 알림을 영영 못 받는다")
                .containsExactly("gone", "garbage", "other-project");
    }

    @Test
    @DisplayName("빈 묶음은 전송을 한 번도 안 부른다")
    void nothingToSend() {
        ScriptedTransport transport = new ScriptedTransport(t -> new FcmDelivery(t, true, null));

        FcmSendResult result = new FirebaseFcmClient(transport).send(List.of(), MESSAGE);

        assertThat(transport.batches).isEmpty();
        assertThat(result).isEqualTo(FcmSendResult.NOTHING);
    }
}
