package com.heattrip.heat_trip_backend.moderation;

import java.text.Normalizer;
import java.util.List;
import java.util.Locale;

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
 * <h2>{@link #SAFE_WORDS} 가 있는 이유</h2>
 * <p>"시발" 은 가장 흔한 표기라 빼기 아까운데, <b>"시발점"·"시발역"</b> 은 평범한 낱말이다.
 * 그래서 금칙어를 찾기 <b>전에</b> 이 낱말들을 먼저 지운다. 지우고 남은 자리에 "시발" 이
 * 여전히 있으면 그때는 욕이다.
 *
 * <h2>왜 NFKC 로 고르는가</h2>
 * <p>iOS·macOS 가 보내는 한글은 자모가 풀린 형태(NFD)일 수 있다. 그대로 비교하면 눈에는
 * 같은 글자인데 {@code contains} 가 못 찾는다. {@link Normalizer.Form#NFKC} 는 그 자모를
 * 다시 한 글자로 합치고, 전각({@code ｓ})·호환 문자도 같은 자리로 모은다. 목록 자체도 같은
 * 방식으로 한 번 접어 둔다 — 한쪽만 접으면 비교가 어긋난다.
 */
final class BannedWords {

    private BannedWords() {
    }

    /**
     * 걸러 낼 말. <b>부분 문자열</b>로 찾는다 — "씨발놈" 은 "씨발" 로 걸린다.
     *
     * <p>넓히기 전에 위 javadoc 의 "과차단이 더 나쁜 버그다" 를 먼저 읽어라. 한 낱말을 더할
     * 때마다 <b>그 낱말이 들어가는 평범한 문장이 있는지</b>를 먼저 찾아봐야 한다.
     */
    private static final List<String> RAW_WORDS = List.of(
            // ── 욕설·비속어 ──
            "씨발", "시발", "씨팔", "시팔", "씨빨", "십새끼", "씹새끼", "씹할",
            "개새끼", "개세끼", "개색기", "좆", "지랄", "병신", "븅신", "썅",
            "니미럴", "니애미", "느금마", "엠창",

            // ── 성적 표현 ──
            // 임상 용어("중성화"·"발정")는 이 앱에서 매일 쓰이는 말이라 넣지 않았다.
            "야동", "포르노", "조건만남", "섹파", "성매매", "몸캠",

            // ── 혐오 표현 ──
            // 특정 집단을 가리키는 멸칭만. 정치 진영 용어는 판단이 갈려서 넣지 않았다.
            "틀딱", "짱깨", "쪽바리", "쪽발이", "한남충", "김치녀", "맘충", "급식충");

    /**
     * 금칙어를 찾기 <b>전에</b> 지워 두는 평범한 낱말.
     *
     * <p>"시발점" 을 지우면 "시발" 이 남지 않는다. 이 목록이 없으면 지하철·버스 얘기를 하는
     * 사람이 이유도 모르고 막힌다.
     */
    private static final List<String> RAW_SAFE_WORDS = List.of(
            "시발점", "시발역", "시발지", "시발택시");

    private static final List<String> WORDS = RAW_WORDS.stream().map(BannedWords::fold).toList();

    private static final List<String> SAFE_WORDS =
            RAW_SAFE_WORDS.stream().map(BannedWords::fold).toList();

    /**
     * 이 글에 금칙어가 있는가.
     *
     * @param text 검사할 글. {@code null} 이거나 비어 있으면 {@code false} — 빈 글을
     *             막는 것은 이 파일의 일이 아니다(본문 필수 여부는 각 도메인이 이미 본다)
     */
    static boolean matches(String text) {
        if (text == null || text.isBlank()) {
            return false;
        }
        String folded = fold(text);
        for (String safe : SAFE_WORDS) {
            // 자리를 없애지 않고 공백으로 바꾼다 — 지워 붙이면 앞뒤 글자가 맞닿아
            // 원문에 없던 낱말이 생긴다.
            folded = folded.replace(safe, " ");
        }
        for (String word : WORDS) {
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
