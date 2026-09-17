package com.heattrip.heat_trip_backend.moderation;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.text.Normalizer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * 게시 전 거르기 — 이슈 #681, 애플 App Review Guideline 1.2.
 *
 * <p>스프링을 띄우지 않는다 — 판정에 DB 도 요청도 없고, 컨텍스트를 하나 더 띄울 이유가
 * 없다(#21). 이 파일이 재는 것은 셋이다.
 * <ol>
 *   <li>명백한 금칙어가 <b>걸린다</b></li>
 *   <li>평범한 말이 <b>안 걸린다</b> — 과차단이 더 나쁜 버그다</li>
 *   <li>거절이 <b>무엇이 걸렸는지 안 알려 준다</b></li>
 * </ol>
 *
 * <p>글·댓글·채팅이 <b>같은</b> {@link ContentFilter} 를 부르므로 판정 자체는 여기서 한 번만
 * 잰다. 그 셋이 실제로 이것을 지나는지는 {@code ContentFilterIntegrationTest} 가 HTTP 로 잰다.
 */
class ContentFilterTest {

    private final ContentFilter filter = new ContentFilter();

    // ─────────────────────────── 걸린다 ───────────────────────────

    @ParameterizedTest(name = "[{index}] {0}")
    @ValueSource(strings = {
            "씨발 이게 뭐야",
            "시발 왜 안 되지",
            "개새끼야",
            "지랄하지 마라",
            "너 병신이냐",
            "야동 링크 여기",
            "조건만남 구합니다",
            "틀딱들은 빠져라",
            "맘충 진짜 싫다",
            // 문장 한가운데여도 걸린다 — 부분 문자열로 찾기 때문이다.
            "오늘 산책 갔는데 지랄맞게 더웠어요"
    })
    @DisplayName("명백한 욕설·성적 표현·혐오 표현은 400 이다")
    void obviousProfanityIsRejected(String text) {
        ResponseStatusException thrown =
                assertThrows(ResponseStatusException.class, () -> filter.requireClean(text));

        assertThat(thrown.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    @DisplayName("여럿 중 하나만 걸려도 거절한다 — 제목이 깨끗해도 본문에 있으면 막힌다")
    void oneDirtyFieldIsEnough() {
        assertThatThrownBy(() -> filter.requireClean("오늘의 산책 후기", "씨발 사람이 너무 많았다"))
                .isInstanceOf(ResponseStatusException.class);
    }

    @Test
    @DisplayName("자모가 풀려 온 글(NFD)도 걸린다 — iOS·macOS 가 그렇게 보낸다")
    void decomposedHangulIsStillCaught() {
        String decomposed = Normalizer.normalize("씨발", Normalizer.Form.NFD);

        assertThat(decomposed)
                .as("변형이 실제로 들어갔는지 먼저 확인한다 — 같은 문자열이면 이 테스트는 아무것도 안 잰다")
                .isNotEqualTo("씨발");
        assertThatThrownBy(() -> filter.requireClean(decomposed))
                .isInstanceOf(ResponseStatusException.class);
    }

    // ─────────────────────────── 안 걸린다 ───────────────────────────

    @ParameterizedTest(name = "[{index}] {0}")
    @ValueSource(strings = {
            "오늘 한강에서 30분 산책했어요",
            "강아지 사료 추천 부탁드립니다",

            // 아래 여섯은 목록을 넓히면 곧바로 막히는 평범한 문장들이다.
            // BannedWords javadoc 이 왜 이 낱말들을 뺐는지 적어 뒀다.
            "새벽에 개소리가 너무 커서 깼어요",
            "우리 강아지가 새끼를 다섯 낳았어요",
            "이 영상은 보지 마세요",
            "밤에 잘 자지 않아서 걱정이에요",
            "홍어회 먹으러 갔다가 산책도 했어요",
            "미친 듯이 뛰어다니는 걸 좋아해요",

            // 시발점·시발역은 SAFE_WORDS 가 먼저 지운다.
            "이 길이 산책로의 시발점이에요",
            "1호선 시발역에서 만나요"
    })
    @DisplayName("평범한 글은 그대로 지나간다 — 과차단이 더 나쁜 버그다")
    void ordinaryTextPasses(String text) {
        assertThatCode(() -> filter.requireClean(text)).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("null·빈 문자열은 검사할 것이 없는 자리다 — 안 보낸 필드와 캡션 없는 사진")
    void nothingToCheckPasses() {
        assertThatCode(() -> filter.requireClean(null, "", "   ")).doesNotThrowAnyException();
    }

    // ─────────────────────── 무엇이 걸렸는지 안 알려 준다 ───────────────────────

    @Test
    @DisplayName("거절 응답이 어느 낱말에 걸렸는지 안 알려 준다 — 알려 주면 우회법을 알려 주는 셈이다")
    void theRejectionNamesNothing() {
        ResponseStatusException thrown = assertThrows(ResponseStatusException.class,
                () -> filter.requireClean("씨발 진짜 지랄이네"));

        assertThat(thrown.getReason())
                .as("문구는 고정이다 — 여기에 걸린 낱말이 실리면 한 글자씩 바꿔 보며 목록을 뽑아낼 수 있다")
                .isEqualTo(ContentFilter.REJECTION_MESSAGE)
                .doesNotContain("씨발", "지랄");

        assertThat(ContentFilter.REJECTION_MESSAGE)
                .as("원문 자체를 되돌려 주지도 않는다 — 그 안에 걸린 낱말이 들어 있다")
                .doesNotContain("진짜");
    }
}
