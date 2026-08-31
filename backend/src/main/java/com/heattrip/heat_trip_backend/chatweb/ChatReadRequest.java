package com.heattrip.heat_trip_backend.chatweb;

/**
 * 읽음 보고 본문 — 계약({@code openapi.yaml})의
 * {@code POST /api/chat/rooms/&#123;roomId&#125;/read}. 이슈 #79.
 *
 * <p>필드가 {@code long} 이 아니라 {@link Long} 인 것은 <b>"안 보냈다" 와 "0 을 보냈다" 를
 * 구별하기 위해서</b>다. 원시 타입이면 Jackson 이 빠진 필드를 0 으로 채우고, 그러면
 * {@code {}} 라는 본문이 "0 까지 읽었다" 라는 정상 요청이 되어 400 대신 200 이 나간다.
 * 워터마크는 뒤로 가지 않으므로 데이터가 깨지지는 않지만, 앱은 자기 요청이 먹혔다고 믿는다.
 */
public record ChatReadRequest(Long lastReadSeq) {

    /**
     * @throws IllegalArgumentException 400 — 값이 없으면. 메시지에 입력값을 되싣지 않는다(#6)
     */
    long requireLastReadSeq() {
        if (lastReadSeq == null) {
            throw new IllegalArgumentException("읽음 위치가 필요합니다.");
        }
        return lastReadSeq;
    }
}
