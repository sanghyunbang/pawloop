package com.heattrip.heat_trip_backend.moderation;

import java.text.Normalizer;
import java.util.List;
import java.util.Locale;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/**
 * 게시 전에 거를 말들 — 이슈 #681.
 *
 * <h2>왜 이것이 필요한가 — 애플 App Review Guideline 1.2</h2>
 * <p>애플의 심사 지침 <b>1.2 Safety — User-Generated Content</b> 는 사용자가 글을 올리는 앱에
 * 넷을 <b>한 묶음으로</b> 요구한다. 불쾌한 내용을 <b>거르는 방법</b>, <b>신고</b>,
 * 거슬리는 사용자를 <b>차단</b>하는 방법, 그리고 <b>연락처 공개</b>다. 넷 중 하나라도 없으면
 * 그 조항으로 반려된다.
 *
 * <p>포루프에는 이미 셋이 있다 — 신고({@link Reports}, #166) · 차단({@link Blocks}, #82) ·
 * 연락처. <b>없던 하나가 거르기</b>이고, {@code CommunityService.create} 는 형식만 검증하고
 * 바로 저장했다. 이 파일이 그 하나다.
 *
 * <h2>왜 금칙어 목록인가 — 그리고 이것이 무엇이 아닌가</h2>
 * <p>외부 판정 API 도, 모델도 붙이지 않았다. 키가 없고, 붙이면 <b>글쓰기 한 번마다 외부
 * 왕복</b>이 생겨 그 서비스가 죽으면 우리 글쓰기도 죽는다. 지침이 요구하는 것은
 * "filtering method" 이지 "완벽한 판정" 이 아니다.
 *
 * <p><b>그래서 이것은 최소한이고, 한계를 그대로 적는다.</b>
 * <ul>
 *   <li><b>우회된다.</b> 글자 사이에 점을 찍거나(씨.발) 자모를 섞으면 안 걸린다. 막으려면
 *       사이 문자를 지우고 봐야 하는데, 그러면 <b>평범한 문장이 걸린다</b> — 공백을 지우면
 *       "이걸 시 발표할 때" 가 금칙어가 된다. 우회를 막는 값보다 그 오차단의 값이 크다.</li>
 *   <li><b>맥락을 못 본다.</b> 인용도, 자기 얘기도, 농담도 전부 같은 취급이다.</li>
 *   <li><b>목록에 없는 말은 그냥 지나간다.</b> 새 말은 계속 생긴다.</li>
 * </ul>
 * <p>그래서 이 필터가 <b>신고를 대신하지 않는다.</b> 여기를 지나간 것은 신고로 걸리고,
 * 신고된 것은 운영자가 본다. 둘이 함께 있어야 1.2 가 요구하는 모양이 된다.
 *
 * <h2>과차단이 더 나쁜 버그다</h2>
 * <p>말이 막힌 사람은 다시 쓰지 않는다. 그래서 <b>명백한 것만</b> 담았고, 흔하게 쓰이면서
 * 욕처럼 보이는 말은 일부러 뺐다. 실제로 뺀 것들 —
 * <ul>
 *   <li><b>"개소리"</b> — 반려견 앱이다. 개가 내는 소리를 그렇게 부른다.</li>
 *   <li><b>"새끼"</b> — "강아지 새끼 낳았어요" 가 이 앱에서 가장 평범한 문장 중 하나다.</li>
 *   <li><b>"보지"·"자지"</b> — 각각 "보지 마세요" · "밤에 자지 않아요" 의 부정형이다.
 *       넣으면 매일 수십 명이 이유도 모른 채 막힌다.</li>
 *   <li><b>"홍어"</b> — 생선이다. 먹는 얘기가 막힌다.</li>
 *   <li><b>"미친"</b> — "미친 듯이 뛰어요" 가 칭찬으로 쓰인다.</li>
 * </ul>
 *
 * <h2>허용 낱말이 있는 이유</h2>
 * <p>금칙어 중에는 <b>평범한 낱말 안에 통째로 들어앉는</b> 것이 있다. 흔한 욕 하나가 어떤
 * 지명이나 전문용어의 앞 두 글자와 같은 식이다. 그 욕을 빼자니 가장 흔한 표기를 놓치고,
 * 넣자니 그 지명을 쓴 사람이 이유도 모른 채 막힌다.
 *
 * <p>그래서 금칙어를 찾기 <b>전에</b> 그 평범한 낱말들을 먼저 지운다. 지우고 남은 자리에
 * 욕이 여전히 있으면 그때는 진짜 욕이다.
 *
 * <p><b>실제 짝은 여기 안 적는다.</b> 적으면 목록을 코드 밖으로 뺀 뜻이 없어진다(#789).
 * 운영 설정의 {@code MODERATION_SAFE_WORDS} 에 있다.
 *
 * <h2>왜 NFKC 로 고르는가</h2>
 * <p>iOS·macOS 가 보내는 한글은 자모가 풀린 형태(NFD)일 수 있다. 그대로 비교하면 눈에는
 * 같은 글자인데 {@code contains} 가 못 찾는다. {@link Normalizer.Form#NFKC} 는 그 자모를
 * 다시 한 글자로 합치고, 전각({@code ｓ})·호환 문자도 같은 자리로 모은다. 목록 자체도 같은
 * 방식으로 한 번 접어 둔다 — 한쪽만 접으면 비교가 어긋난다.
 */
@Component
class BannedWords {

    private static final Logger log = LoggerFactory.getLogger(BannedWords.class);

    /**
     * 걸러 낼 말과, 찾기 전에 지워 둘 평범한 낱말.
     *
     * <h2>왜 코드에 안 적혀 있나 — 이슈 #789</h2>
     * <p>예전에는 이 자리에 낱말이 그대로 적혀 있었다. 둘 때문에 뺐다.
     *
     * <ul>
     *   <li><b>저장소를 공개로 돌린다.</b> 거르려고 만든 목록을 거르려는 사람이 그대로
     *       읽는다. "숨김에 기대지 말라" 는 원칙의 몇 안 되는 예외가 이 종류다 —
     *       금칙어는 본질적으로 숨어 있어야 작동한다.</li>
     *   <li><b>운영하면서 계속 는다.</b> 새 욕설, 새 우회 표기, 신고를 받고 알게 되는
     *       말들. 그때마다 코드를 고치고 빌드하고 배포해야 한다면 자리가 틀린 것이다.
     *       <b>공개와 무관하게 옮기는 게 맞다.</b></li>
     * </ul>
     *
     * <p>값은 운영 설정(SSM 의 {@code .env})에서 온다. 쉼표로 가른다.
     * 고치는 법은 {@code scripts/set-prod-env.sh}, 먹이는 법은
     * {@code scripts/refresh-prod-env.sh} 다.
     *
     * <p><b>히스토리에는 옛 목록이 남는다.</b> 공개로 돌리면 누구나 {@code git log} 로
     * 읽을 수 있다. 히스토리 전체의 해시를 다시 쓰는 것보다, <b>옮긴 뒤 목록을 한 번
     * 손보는 것</b>이 싸고 확실하다 — 그러면 공개된 것은 옛 목록이고 도는 것은 다른
     * 목록이다.
     */
    private final List<String> words;

    private final List<String> safeWords;

    BannedWords(
            @Value("${app.moderation.banned-words:}") List<String> words,
            @Value("${app.moderation.safe-words:}") List<String> safeWords,
            Environment environment) {
        this.words = folded(words);
        this.safeWords = folded(safeWords);
        requireWordsWhereItMatters(environment);
    }

    /**
     * 목록이 비면 <b>운영에서는 뜨지 않는다.</b>
     *
     * <p>비어 있어도 {@link #matches}는 조용히 {@code false}만 돌려준다 — 필터가 <b>있는
     * 척</b>만 하고 아무것도 안 거른다. 로그 한 줄도 없다. 애플 지침 1.2 가 요구하는 넷 중
     * 하나가 그렇게 조용히 사라지면 다음 심사에서야 안다.
     *
     * <p>뜨지 않게 하는 쪽이 안전하다. 블루/그린 배포(#787)가 새 쪽의 healthy 를 기다렸다가
     * 안 되면 <b>옛 쪽을 그대로 두므로</b>, 설정을 빠뜨린 배포는 서비스에 닿지 않고 멈춘다.
     *
     * <p>dev·test 에서는 비어도 된다. 검사는 자기 목록을 직접 넣어 돌린다.
     */
    private void requireWordsWhereItMatters(Environment environment) {
        boolean prod = List.of(environment.getActiveProfiles()).contains("prod");
        if (!words.isEmpty()) {
            log.info("[MODERATION] 금칙어 {}개 · 허용 낱말 {}개", words.size(), safeWords.size());
            return;
        }
        if (prod) {
            throw new IllegalStateException(
                    "app.moderation.banned-words 가 비어 있다. 운영에서 금칙어 없이 뜨면 "
                            + "글 거르기가 통째로 사라진다 (애플 지침 1.2). "
                            + "운영 설정에 MODERATION_BANNED_WORDS 를 넣어라 — 이슈 #789.");
        }
        log.warn("[MODERATION] 금칙어 목록이 비었다 — 아무것도 안 거른다. "
                + "운영이 아니라 넘어간다(프로필: {})", (Object) environment.getActiveProfiles());
    }

    /** 목록과 입력에 똑같은 모양을 건다. 빈 줄은 버린다 — 설정이 비면 빈 원소가 하나 온다. */
    private static List<String> folded(List<String> raw) {
        return raw == null ? List.of()
                : raw.stream().map(String::strip).filter(s -> !s.isEmpty())
                        .map(BannedWords::fold).toList();
    }

    /**
     * 이 글에 금칙어가 있는가.
     *
     * @param text 검사할 글. {@code null} 이거나 비어 있으면 {@code false} — 빈 글을
     *             막는 것은 이 파일의 일이 아니다(본문 필수 여부는 각 도메인이 이미 본다)
     */
    boolean matches(String text) {
        if (text == null || text.isBlank()) {
            return false;
        }
        String folded = fold(text);
        for (String safe : safeWords) {
            // 자리를 없애지 않고 공백으로 바꾼다 — 지워 붙이면 앞뒤 글자가 맞닿아
            // 원문에 없던 낱말이 생긴다.
            folded = folded.replace(safe, " ");
        }
        for (String word : words) {
            if (folded.contains(word)) {
                return true;
            }
        }
        return false;
    }

    /** 비교의 기준 모양 — 자모를 합치고(NFKC) 대소문자를 없앤다. 목록과 입력에 똑같이 건다. */
    private static String fold(String text) {
        return Normalizer.normalize(text, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT);
    }
}
