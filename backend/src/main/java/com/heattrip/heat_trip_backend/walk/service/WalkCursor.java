package com.heattrip.heat_trip_backend.walk.service;

import com.heattrip.heat_trip_backend.walk.entity.Walk;

import java.nio.charset.StandardCharsets;
import java.time.DateTimeException;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.Optional;

/**
 * 목록 커서 — 이슈 #145. 계약의 {@code Page.nextCursor} 자리에 들어가는 <b>불투명 토큰</b>이다.
 *
 * <h2>왜 두 값인가</h2>
 * <p>{@code createdAt} 하나로는 부족하다. 같은 시각(마이크로초까지)에 만들어진 두 행이 있을
 * 수 있고 — 오프라인 큐가 한 번에 여러 건을 밀어 넣으면 실제로 생긴다 — 그때 장 경계에서
 * 행이 <b>중복되거나 건너뛰어진다.</b> {@code id} 로 한 번 더 가른다.
 *
 * <h2>왜 {@code startedAt} 이 아닌가</h2>
 * <p>그건 앱이 보낸 값이다. 오프라인에 쌓아 둔 산책이 며칠 뒤 <b>과거 시각</b>으로 들어오면,
 * 이미 발급된 커서보다 아래 날짜라 <b>영원히 건너뛰어진다.</b> {@code chat_message} 가
 * {@code room_seq} 로 피한 것과 같은 종류의 실패다.
 *
 * <h2>불투명하게 두는 이유</h2>
 * <p>base64 는 <b>암호가 아니다</b> — 누구나 풀 수 있고 그래도 된다. 이 안에 든 것은
 * 자기 산책의 시각과 id 뿐이라 숨길 것이 없다. 감싸는 이유는 <b>모양을 바꿀 여지를 남기기
 * 위해서</b>다. 날것으로 주면 앱이 그것을 파싱하기 시작하고, 그러면 커서 형식이 계약이 된다.
 *
 * <p>깨진 커서는 <b>400 이 아니라 첫 장</b>이다. 앱이 오래된 커서를 들고 있는 것은 흔한
 * 일이고, 거기서 오류를 내면 사용자는 목록을 아예 못 본다.
 */
record WalkCursor(LocalDateTime createdAt, long id) {

    private static final String SEPARATOR = ":";

    /**
     * 이 행 <b>다음</b>부터 달라는 토큰.
     *
     * <p><b>초와 나노초를 따로 싣는다.</b> {@code toEpochMilli()} 로 접으면 마이크로초가
     * 잘리는데, 컬럼은 {@code datetime(6)} 이라 실제 값에는 마이크로초가 있다. 잘린 커서로
     * 다음 장을 물으면 그 사이(예: {@code .123000} 과 {@code .123456})에 있는 행이
     * {@code < cursorAt} 도 {@code = cursorAt} 도 아니게 되어 <b>영원히 건너뛰어진다.</b>
     */
    static String of(Walk walk) {
        LocalDateTime at = walk.getCreatedAt();
        String raw = at.toEpochSecond(ZoneOffset.UTC)
                + SEPARATOR + at.getNano()
                + SEPARATOR + walk.getId();
        return Base64.getUrlEncoder().withoutPadding()
                .encodeToString(raw.getBytes(StandardCharsets.UTF_8));
    }

    /** @return 읽을 수 없으면 {@link Optional#empty()} — 부르는 쪽은 첫 장을 준다 */
    static Optional<WalkCursor> parse(String cursor) {
        if (cursor == null || cursor.isBlank()) {
            return Optional.empty();
        }
        try {
            String raw = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8);
            String[] parts = raw.split(SEPARATOR);
            if (parts.length != 3) {
                return Optional.empty();
            }
            return Optional.of(new WalkCursor(
                    LocalDateTime.ofEpochSecond(
                            Long.parseLong(parts[0]), Integer.parseInt(parts[1]), ZoneOffset.UTC),
                    Long.parseLong(parts[2])));
        } catch (IllegalArgumentException | ArithmeticException | DateTimeException unreadable) {
            return Optional.empty();
        }
    }
}
