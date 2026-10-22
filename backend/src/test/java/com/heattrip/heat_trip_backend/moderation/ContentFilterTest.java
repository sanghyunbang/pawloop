package com.heattrip.heat_trip_backend.moderation;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpStatus;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.web.server.ResponseStatusException;

import java.text.Normalizer;
import java.util.List;

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
 *   <li>명백한 것이 <b>걸린다</b></li>
 *   <li>평범한 글이 <b>안 걸린다</b> — 과차단이 더 나쁜 버그다</li>
 *   <li>거절이 <b>무엇이 걸렸는지 안 알려 준다</b></li>
 * </ol>
 *
 * <p>글·댓글·채팅이 <b>같은</b> {@link ContentFilter} 를 부르므로 판정 자체는 여기서 한 번만
 * 잰다. 그 셋이 실제로 이것을 지나는지는 {@code ContentFilterIntegrationTest} 가 HTTP 로 잰다.
 *
 * <h2>진짜 금칙어를 안 쓴다 — 이슈 #789</h2>
 * <p>예전에는 운영에서 쓰는 그 낱말들로 쟀다. 둘이 잘못됐다.
 *
 * <ul>
 *   <li><b>의존이 거꾸로다.</b> 운영에서 낱말 하나를 빼면 검사가 깨진다. 검사가 운영
 *       데이터를 붙들고 있는 모양이다.</li>
 *   <li><b>저장소가 공개된다.</b> 코드에서 목록을 뺐는데 검사에 그대로 남아 있으면
 *       뺀 뜻이 없다.</li>
 * </ul>
 *
 * <p>그래서 <b>지어낸 낱말</b>로 잰다. 이 검사가 답해야 하는 것은 "이 낱말이 걸리나" 가
 * 아니라 <b>"목록이 주어졌을 때 거르기·정규화·허용 낱말이 제대로 도는가"</b> 다.
 */
class ContentFilterTest {

    /** 지어낸 금칙어. 실제 목록과 아무 상관이 없다 — 위 javadoc 참고. */
    private static final List<String> FAKE_BANNED = List.of("가짜욕", "가짜혐오");

    /**
     * 지어낸 허용 낱말. <b>금칙어를 통째로 품고 있어야</b> 이 장치를 재는 뜻이 있다 —
     * "가짜욕역" 안에 "가짜욕" 이 들어 있다.
     */
    private static final List<String> FAKE_SAFE = List.of("가짜욕역", "가짜욕점");

    private final ContentFilter filter =
            new ContentFilter(new BannedWords(FAKE_BANNED, FAKE_SAFE, new MockEnvironment()));

    // ─────────────────────────── 걸린다 ───────────────────────────

    @ParameterizedTest(name = "[{index}] {0}")
    @ValueSource(strings = {
            "가짜욕",
            "가짜혐오",
            // 문장 한가운데여도 걸린다 — 부분 문자열로 찾기 때문이다.
            "오늘 산책 갔는데 가짜욕 진짜 짜증났다",
            // 대소문자·전각은 NFKC 가 같은 자리로 모은다.
            "가짜욕!!!"
    })
    @DisplayName("목록에 있는 말은 400 이다")
    void bannedWordsAreRejected(String text) {
        ResponseStatusException thrown =
                assertThrows(ResponseStatusException.class, () -> filter.requireClean(text));

        assertThat(thrown.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    @DisplayName("여럿 중 하나만 걸려도 거절한다 — 제목이 깨끗해도 본문에 있으면 막힌다")
    void oneDirtyFieldIsEnough() {
        assertThatThrownBy(() -> filter.requireClean("오늘의 산책 후기", "가짜욕 사람이 너무 많았다"))
                .isInstanceOf(ResponseStatusException.class);
    }

    @Test
    @DisplayName("자모가 풀려 온 글(NFD)도 걸린다 — iOS·macOS 가 그렇게 보낸다")
    void decomposedHangulIsStillCaught() {
        String decomposed = Normalizer.normalize("가짜욕", Normalizer.Form.NFD);

        assertThat(decomposed)
                .as("NFD 로 풀리지 않았다 — 이 검사가 재려던 것이 사라졌다")
                .isNotEqualTo("가짜욕");
        assertThatThrownBy(() -> filter.requireClean(decomposed))
                .isInstanceOf(ResponseStatusException.class);
    }

    // ─────────────────────────── 안 걸린다 ───────────────────────────

    @ParameterizedTest(name = "[{index}] {0}")
    @ValueSource(strings = {
            "오늘 한강에서 30분 걸었어요",
            "우리 강아지가 산책을 정말 좋아해요",

            // 허용 낱말이 먼저 지워진다. 지우고 남은 자리에 금칙어가 없으므로 통과한다.
            "1호선 가짜욕역에서 만나요",
            "가짜욕점 근처 공원 추천합니다"
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

    // ─────────────────────── 목록이 비면 ───────────────────────

    /**
     * <b>이것이 통과한다고 안심하면 안 된다.</b> 목록이 비면 필터가 <b>있는 척</b>만 하고
     * 아무것도 안 거른다 — 그래서 운영 프로필에서는 {@link BannedWords} 가 아예 못 뜨게
     * 막는다. 여기서는 그 "아무것도 안 거른다" 가 사실임을 못 박아 둔다.
     */
    @Test
    @DisplayName("목록이 비면 아무것도 안 걸린다 — 그래서 운영에서는 비면 서버가 안 뜬다")
    void anEmptyListFiltersNothing() {
        ContentFilter empty =
                new ContentFilter(new BannedWords(List.of(), List.of(), new MockEnvironment()));

        assertThatCode(() -> empty.requireClean("가짜욕", "가짜혐오"))
                .as("""
                        목록이 비었는데 무언가 걸렸다. 어디선가 낱말이 코드에 다시 박혔다는 \
                        뜻이다 — 이슈 #789 가 뺀 그것이다.""")
                .doesNotThrowAnyException();
    }

    // ─────────────────── 운영에서 목록이 비면 ───────────────────

    /**
     * 목록 없이 운영에 올라가면 <b>아예 뜨지 않는다.</b>
     *
     * <p>이것이 이슈 #789 의 안전망이다. 낱말을 코드에서 설정으로 옮겼으니 <b>설정을
     * 빠뜨린 배포</b>라는 새 실패가 생겼고, 그 실패가 조용하면 옮긴 값이 깎인다 —
     * 거르기가 사라진 채로 한참 돌다가 다음 심사에서야 안다.
     *
     * <p>뜨지 않는 쪽이 안전한 이유는 블루/그린(#787)이다. 새 쪽이 healthy 가 될 때까지
     * 기다렸다가 안 되면 <b>옛 쪽을 그대로 두므로</b>, 설정을 빠뜨린 배포는 서비스에
     * 닿지 못하고 멈춘다.
     */
    @Test
    @DisplayName("운영 프로필에서 목록이 비면 아예 못 뜬다 — 조용히 안 거르는 것보다 낫다")
    void prodRefusesToStartWithoutWords() {
        MockEnvironment prod = new MockEnvironment();
        prod.setActiveProfiles("prod");

        assertThatThrownBy(() -> new BannedWords(List.of(), List.of(), prod))
                .as("""
                        목록이 비었는데 운영에서 떴다. 거르기가 조용히 사라진 채 \
                        서비스가 돈다 — 애플 지침 1.2 가 요구하는 넷 중 하나다.""")
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("MODERATION_BANNED_WORDS");
    }

    @Test
    @DisplayName("운영이어도 목록이 있으면 뜬다 — 막는 것은 빈 목록뿐이다")
    void prodStartsWhenTheListIsThere() {
        MockEnvironment prod = new MockEnvironment();
        prod.setActiveProfiles("prod");

        assertThatCode(() -> new BannedWords(FAKE_BANNED, FAKE_SAFE, prod))
                .as("목록이 있는데도 막혔다 — 이러면 운영이 뜨지 못한다")
                .doesNotThrowAnyException();
    }

    // ─────────────────────── 무엇이 걸렸는지 안 알려 준다 ───────────────────────

    @Test
    @DisplayName("거절 문구가 무엇이 걸렸는지 안 알려 준다 — 목록을 떠보는 길이 된다")
    void theRejectionNamesNothing() {
        ResponseStatusException thrown = assertThrows(ResponseStatusException.class,
                () -> filter.requireClean("가짜욕"));

        assertThat(thrown.getReason())
                .as("거절 이유에 걸린 낱말이 실렸다 — 하나씩 넣어 보면 목록이 복원된다")
                .isEqualTo(ContentFilter.REJECTION_MESSAGE)
                .doesNotContain("가짜욕", "가짜혐오");

        assertThat(ContentFilter.REJECTION_MESSAGE)
                .as("고정 문구에 낱말이 섞여 있다")
                .doesNotContain("가짜욕");
    }
}
