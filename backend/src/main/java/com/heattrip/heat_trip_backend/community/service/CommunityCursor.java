package com.heattrip.heat_trip_backend.community.service;

import java.nio.charset.StandardCharsets;
import java.time.DateTimeException;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.Optional;

/**
 * 목록 한 장의 끝을 가리키는 토큰 — 이슈 #170.
 *
 * <h2>{@code WalkCursor} 와 같은 모양이다. 왜 합치지 않았나</h2>
 * <p>{@code walk.service.WalkCursor} 가 글자 그대로 같은 일을 하는데 <b>package-private</b>
 * 이라 여기서 못 쓴다. 공용으로 올리려면 {@code walk} 를 건드려야 하고, 그건 이 이슈의
 * 범위 밖이다.
 *
 * <p><b>합치는 날의 조건을 적어 둔다</b> — 세 번째가 생기면 그때다(rule of three). 지금
 * 둘뿐일 때 공용 타입을 만들면 "어느 도메인의 정렬 축인가" 를 파라미터로 받는 물건이 되고,
 * 그건 두 곳에 각각 있는 것보다 읽기 어렵다.
 *
 * <h2>초와 나노초를 따로 싣는다</h2>
 * <p>{@code toEpochMilli()} 로 접으면 마이크로초가 잘리는데 컬럼은 {@code datetime(6)} 이라
 * 실제 값에는 마이크로초가 있다. 잘린 커서로 다음 장을 물으면 그 사이(예: {@code .123000} 과
 * {@code .123456})에 있는 행이 <b>영원히 건너뛰어진다.</b>
 *
 * <h2>깨진 커서는 400 이 아니라 첫 장이다</h2>
 * <p>앱이 오래된 커서를 들고 있는 것은 흔한 일이고, 거기서 오류를 내면 <b>사용자는 목록을
 * 아예 못 본다.</b> {@code WalkCursor} 가 정한 판정을 그대로 따른다.
 *
 * <p>이슈 #170 의 완료 조건 8 은 "잘못된 커서는 400" 이라고 적었는데, 그건 이 저장소가
 * 이미 정한 것과 반대다. <b>규약을 따르고 이슈 쪽을 고친다</b> — 한 계약 안에서 같은 실패가
 * 두 코드로 답하면 앱이 두 갈래를 다뤄야 한다.
 *
 * <p>base64 로 감싸는 것은 암호가 아니라 <b>모양을 바꿀 여지</b>다. 날것으로 주면 앱이
 * 파싱하기 시작하고 커서 형식이 계약이 된다.
 */
record CommunityCursor(LocalDateTime createdAt, long id) {

    private static final String SEPARATOR = ":";

    static String of(LocalDateTime createdAt, long id) {
        String raw = createdAt.toEpochSecond(ZoneOffset.UTC)
                + SEPARATOR + createdAt.getNano()
                + SEPARATOR + id;
        return Base64.getUrlEncoder().withoutPadding()
                .encodeToString(raw.getBytes(StandardCharsets.UTF_8));
    }

    /** @return 읽을 수 없으면 {@link Optional#empty()} — 부르는 쪽은 첫 장을 준다 */
    static Optional<CommunityCursor> parse(String cursor) {
        if (cursor == null || cursor.isBlank()) {
            return Optional.empty();
        }
        try {
            String raw = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8);
            String[] parts = raw.split(SEPARATOR);
            if (parts.length != 3) {
                return Optional.empty();
            }
            return Optional.of(new CommunityCursor(
                    LocalDateTime.ofEpochSecond(
                            Long.parseLong(parts[0]), Integer.parseInt(parts[1]), ZoneOffset.UTC),
                    Long.parseLong(parts[2])));
        } catch (IllegalArgumentException | ArithmeticException | DateTimeException unreadable) {
            // Base64 깨짐 · parseLong 실패 · LocalDateTime 범위 초과. 셋 다 첫 장이다.
            return Optional.empty();
        }
    }
}
