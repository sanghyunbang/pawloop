package com.heattrip.heat_trip_backend.chat;

import org.springframework.stereotype.Component;

import java.security.SecureRandom;

/**
 * 초대코드를 만든다 — 이슈 #75.
 *
 * <h2>{@link SecureRandom} 이어야 하는 이유</h2>
 * <p>이 코드는 <b>인증 없이 방에 들어오는 유일한 열쇠</b>다. {@code Random}·{@code Math.random}
 * 은 시드를 알면 다음 값을 계산할 수 있고, 초대코드에서 그건 곧 남의 가족 대화 입장권이다.
 * 자바에서 예측 불가 난수의 표준 출처는 {@link SecureRandom} 하나다.
 *
 * <h2>사람이 옮겨 적을 수 있어야 한다</h2>
 * <p>초대는 카톡으로 붙여넣기도 하지만 화면을 보고 손으로 옮겨 적기도 한다. 그래서 두 가지를
 * 함께 지킨다.
 * <ul>
 *   <li><b>헷갈리는 글자를 뺀다.</b> {@code 0}·{@code O}·{@code 1}·{@code I} 넷을 빼고 남은
 *       <b>32글자</b>를 쓴다(Crockford Base32 와 같은 계열). 빼지 않으면 "안 되는 코드"의
 *       상당수가 실은 오타이고, 그 문의는 서버 로그로 구별되지 않는다.
 *       <p><b>{@code L} 은 남겼다 — 그리고 그건 실수가 아니라 산수다.</b> 다섯 글자를 전부
 *       빼면 31글자라 아래 "글자당 5비트" 가 성립하지 않는다. {@code L} 을 헷갈리게 만드는
 *       짝({@code 1}·{@code I})이 둘 다 빠져 있으므로 남겨도 혼동이 생기지 않는다.
 *       2026-08 이전에는 이 문장과 계약이 "{@code 1}/{@code I}/{@code L} 을 뺀 32글자" 라고
 *       적었는데 그 숫자 자체가 성립하지 않았고, 그 서술로 입력 검증기를 만들면 실제 코드의
 *       약 27%(10글자 기준 1-(31/32)^10)를 "잘못된 코드" 로 튕긴다.
 *       {@code InviteCodeGeneratorTest} 가 이 알파벳을 런타임에 읽어 문장과 대조한다.</li>
 *   <li><b>가운데에 하이픈을 넣는다.</b> 다섯 글자씩 끊으면 눈이 자리를 잃지 않는다.
 *       계약({@code openapi.yaml})의 예시 {@code PAW-2K7Q} 도 같은 모양이다.</li>
 * </ul>
 *
 * <h2>길이의 근거</h2>
 * <p>글자 32개 = 글자당 5비트, 10글자 = <b>50비트</b>다. 추측 공격은 초당 몇 건이 아니라
 * 초당 수천 건을 던져야 의미가 생기는 크기이고, 그 앞단(참여 경로 rate limit)은 M2.6 이
 * 맡는다({@code ChatInviteController} 의 주석 참조). 여기서 길이를 줄이면 그 대비가 무의미해진다.
 *
 * <h3>이 값들은 {@code ChatLimits} 가 답하는 한도가 아니다</h3>
 * <p>글자 수는 요금제로 달라질 값이 아니라 <b>암호학적 강도</b>다. 플랜별로 초대코드를 짧게
 * 만들어 주는 제품은 없다.
 *
 * <h2>다중 인스턴스</h2>
 * <p>{@link SecureRandom} 인스턴스가 인스턴스마다 다른 것은 <b>문제가 아니라 요건</b>이다 —
 * 서로 다른 씨앗에서 서로 다른 코드가 나온다. 요청 사이에 살아남아야 하는 상태가 없으므로
 * 📌 #86 §2 의 표에 줄을 추가하지 않는다.
 */
@Component
public class InviteCodeGenerator {

    /**
     * {@code 0}·{@code O}·{@code 1}·{@code I} 를 뺀 32글자. <b>{@code L} 은 들어 있다</b> —
     * 이유는 클래스 javadoc.
     *
     * <p>{@code package-private} 인 것은 테스트가 이 배열을 <b>실제로 읽어</b> 금지 글자와
     * 길이를 검사하기 위해서다. 사본을 테스트에 적으면 둘이 나란히 낡는다
     * ({@code ChatLimitsTest} 가 한도를 다루는 방식과 같다).
     */
    static final char[] ALPHABET =
            "23456789ABCDEFGHJKLMNPQRSTUVWXYZ".toCharArray();

    private static final int CODE_LENGTH = 10;

    /** 하이픈으로 끊는 단위. */
    private static final int GROUP_SIZE = 5;

    private final SecureRandom random = new SecureRandom();

    /** {@code A2C4E-F6H8K} 모양의 코드 하나. 중복 여부는 부르는 쪽이 확인한다. */
    public String next() {
        StringBuilder code = new StringBuilder(CODE_LENGTH + 1);
        for (int i = 0; i < CODE_LENGTH; i++) {
            if (i > 0 && i % GROUP_SIZE == 0) {
                code.append('-');
            }
            code.append(ALPHABET[random.nextInt(ALPHABET.length)]);
        }
        return code.toString();
    }
}
