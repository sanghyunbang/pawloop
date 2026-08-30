package com.heattrip.heat_trip_backend.chat;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.HashSet;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 초대코드의 알파벳이 <b>문서가 적은 그 알파벳</b>인지 본다 — 이슈 #75.
 *
 * <h2>왜 이 테스트가 있나</h2>
 * <p>{@code InviteCodeGenerator} 의 javadoc 과 계약({@code openapi.yaml})이 둘 다
 * "{@code 0}/{@code O}, {@code 1}/{@code I}/{@code L} 을 뺀 <b>32글자</b>" 라고 적었는데,
 * 실제 알파벳에는 {@code L} 이 들어 있었다. 다섯 글자를 전부 빼면 31글자라 <b>32 라는 숫자
 * 자체가 성립하지 않는</b> 서술이었다.
 *
 * <p>기능은 안 깨졌지만 {@code openapi.yaml} 은 앱이 보고 만드는 단일 출처다. 그 서술로
 * 입력 검증기나 입력 마스크를 만들면 {@code L} 이 섞인 코드를 거절한다 — 10글자 기준
 * {@code 1-(31/32)^10 ≈ 27%} 의 실제 코드가 "잘못된 코드" 로 튕긴다.
 *
 * <p><b>사본을 적지 않는다.</b> {@link InviteCodeGenerator#ALPHABET} 을 실제로 읽어 검사한다
 * ({@code ChatLimitsTest} 가 한도를 다루는 방식과 같다). 알파벳을 바꾸면 이 테스트와 문서가
 * 함께 빨간불이 되고, 문서만 고치는 것으로는 초록이 되지 않는다.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다(#21).
 */
class InviteCodeGeneratorTest {

    /** 손으로 옮겨 적을 때 서로 헷갈리는 짝. 알파벳에 <b>같이</b> 있으면 안 된다. */
    private static final String[][] CONFUSABLE_PAIRS = {
        {"0", "O"},
        {"1", "I"},
        {"1", "L"},
        {"I", "L"},
    };

    @Test
    @DisplayName("알파벳은 32글자이고 중복이 없다 — 32 는 '글자당 5비트' 라는 길이 근거 그 자체다")
    void theAlphabetIsExactlyThirtyTwoDistinctCharacters() {
        char[] alphabet = InviteCodeGenerator.ALPHABET;

        Set<Character> distinct = new HashSet<>();
        for (char c : alphabet) {
            distinct.add(c);
        }

        assertThat(alphabet.length)
                .as("""
                        32 가 아니면 '글자 32개 = 글자당 5비트, 10글자 = 50비트' 라는 javadoc 의 \
                        길이 근거가 그 자리에서 무너진다. 글자를 빼려면 길이도 함께 다시 계산해야 한다.""")
                .isEqualTo(32);
        assertThat(distinct).hasSize(32);
    }

    @Test
    @DisplayName("헷갈리는 짝이 둘 다 들어 있는 경우는 없다 — 그게 글자를 뺀 이유다")
    void noConfusablePairSurvivesTogether() {
        String alphabet = new String(InviteCodeGenerator.ALPHABET);

        for (String[] pair : CONFUSABLE_PAIRS) {
            assertThat(alphabet.contains(pair[0]) && alphabet.contains(pair[1]))
                    .as("""
                            '%s' 와 '%s' 가 같이 있으면 손으로 옮겨 적은 코드의 상당수가 오타가 되고, \
                            그 문의는 서버 로그로 '없는 코드' 와 구별되지 않는다. \
                            L 이 남아 있는 것은 짝인 1·I 가 둘 다 빠졌기 때문이다.""",
                            pair[0], pair[1])
                    .isFalse();
        }
    }

    @Test
    @DisplayName("계약이 적은 알파벳이 실제 알파벳과 글자 그대로 같다 — 앱은 이 문장을 보고 검증기를 만든다")
    void theContractSpellsOutTheSameAlphabet() throws IOException {
        String contract = Files.readString(
                TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8);

        assertThat(contract)
                .as("""
                        계약이 알파벳을 말로만 설명하면(예: '헷갈리는 글자를 뺀 32글자') 그 말과 \
                        실제 글자가 갈렸는지 아무도 모른다 — 실제로 갈려 있었다. \
                        글자를 그대로 적어 두면 이 단언이 그 갈림을 잡는다.""")
                .contains(new String(InviteCodeGenerator.ALPHABET));
    }

    @Test
    @DisplayName("만든 코드는 계약이 적은 모양(다섯 글자-다섯 글자)이고 알파벳 밖 글자가 없다")
    void generatedCodesMatchTheDocumentedShape() {
        InviteCodeGenerator generator = new InviteCodeGenerator();
        String alphabet = new String(InviteCodeGenerator.ALPHABET);

        for (int i = 0; i < 200; i++) {
            String code = generator.next();

            assertThat(code)
                    .as("계약의 예시가 A2C4E-F6H8K 다. 모양이 바뀌면 앱의 입력 마스크가 깨진다")
                    .matches("^[^-]{5}-[^-]{5}$");
            for (char c : code.replace("-", "").toCharArray()) {
                assertThat(alphabet.indexOf(c))
                        .as("알파벳 밖 글자 '%s' 가 나왔다 — 문서대로 만든 검증기가 이 코드를 거절한다", c)
                        .isNotNegative();
            }
        }
    }
}
