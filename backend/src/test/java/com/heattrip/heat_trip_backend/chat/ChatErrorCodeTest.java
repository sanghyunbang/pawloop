package com.heattrip.heat_trip_backend.chat;

import com.heattrip.heat_trip_backend.S3.media.error.GlobalExceptionHandler;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.Arrays;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 한도 위반 4종의 코드·상태와, 그것이 <b>기존 봉투로</b> 나가는지 확인한다 — 이슈 #74.
 *
 * <p>봉투를 새로 만들지 않는 것이 이 파일이 지키는 것의 절반이다. 앱은
 * {@code error.code} 로 분기하므로 형태가 두 벌이 되면 한쪽만 낡는다.
 * {@code ApiRateLimitFilter} 가 이미 같은 봉투를 재사용하는 선례다.
 *
 * <p>스프링을 띄우지 않는다 — 핸들러를 {@code new} 로 만들어 직접 부른다. 이 경로에는
 * 요청도 DB 도 필요 없고, 컨텍스트를 하나 더 띄울 이유가 없다(#21).
 */
class ChatErrorCodeTest {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    @DisplayName("코드마다 HTTP 상태가 계약대로다 — 한도 넷(409 둘 · 410 둘) · 신고 여섯(전부 400)")
    void everyCodeCarriesTheAgreedStatus() {
        assertThat(ChatErrorCode.ROOM_MEMBER_LIMIT.status()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(ChatErrorCode.INVITE_EXPIRED.status()).isEqualTo(HttpStatus.GONE);
        assertThat(ChatErrorCode.INVITE_REVOKED.status()).isEqualTo(HttpStatus.GONE);
        assertThat(ChatErrorCode.INVITE_USES_EXHAUSTED.status()).isEqualTo(HttpStatus.CONFLICT);

        assertThat(ChatErrorCode.REPORT_EMPTY.status()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(ChatErrorCode.REPORT_MESSAGE_LIMIT.status()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(ChatErrorCode.REPORT_MIXED_SENDERS.status()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(ChatErrorCode.REPORT_SELF.status()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(ChatErrorCode.REPORT_MESSAGE_NOT_FOUND.status()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(ChatErrorCode.REPORT_REASON_UNKNOWN.status()).isEqualTo(HttpStatus.BAD_REQUEST);

        assertThat(ChatErrorCode.values())
                .as("""
                        열이다. 늘리려면 앱의 분기도 함께 는다 — 조용히 추가하지 마라.
                        계약(openapi.yaml)의 code 어휘도 함께 늘어야 한다 — AuthContractSpecTest 가
                        그 둘이 갈라지는 것을 잡는다.
                        넷에서 열이 된 것은 #82 의 신고 여섯이다.""")
                .hasSize(10);
    }

    @Test
    @DisplayName("문구에 식별자가 섞이지 않는다 — 이 값은 그대로 응답 본문이 된다")
    void messagesCarryNoIdentifiers() {
        assertThat(Arrays.stream(ChatErrorCode.values()).map(ChatErrorCode::message))
                .allSatisfy(message -> assertThat(message)
                        .as("방 id·초대코드·사용자 id 가 문구에 들어가면 그 순간 유출 경로다 (#6)")
                        .doesNotContainPattern("\\d"));
    }

    @Test
    @DisplayName("한도 위반은 GlobalExceptionHandler 의 봉투 그대로 나간다 — {error:{code,message,traceId}}")
    void violationsGoOutThroughTheSharedEnvelope() {
        for (ChatErrorCode code : ChatErrorCode.values()) {
            ResponseEntity<GlobalExceptionHandler.ErrorResponse> response =
                    handler.handleChatLimitViolation(new ChatLimitViolationException(code));

            assertThat(response.getStatusCode())
                    .as("%s 의 상태", code)
                    .isEqualTo(code.status());
            assertThat(response.getBody()).isNotNull();
            assertThat(response.getBody().error().code())
                    .as("앱은 문구가 아니라 이 값으로 갈라진다 — 유료 유도 화면이 붙을 분기점이다")
                    .isEqualTo(code.name());
            assertThat(response.getBody().error().message()).isEqualTo(code.message());
        }
    }

    @Test
    @DisplayName("코드를 HTTP 상태에서 파생하지 않는다 — 같은 409 안에서 뜻이 갈린다")
    void twoDifferentMeaningsShareOneStatus() {
        var limit = handler.handleChatLimitViolation(
                new ChatLimitViolationException(ChatErrorCode.ROOM_MEMBER_LIMIT));
        var exhausted = handler.handleChatLimitViolation(
                new ChatLimitViolationException(ChatErrorCode.INVITE_USES_EXHAUSTED));

        assertThat(limit.getStatusCode()).isEqualTo(exhausted.getStatusCode());
        assertThat(limit.getBody().error().code())
                .as("상태에서 코드를 뽑으면 둘 다 CONFLICT 가 되고, 앱은 '정원이 찼다' 와 "
                        + "'초대코드를 다 썼다' 를 구분할 수 없다")
                .isNotEqualTo(exhausted.getBody().error().code());
    }
}
