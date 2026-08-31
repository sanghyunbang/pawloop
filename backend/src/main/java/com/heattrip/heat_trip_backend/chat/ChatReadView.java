package com.heattrip.heat_trip_backend.chat;

/**
 * 읽음 워터마크를 올린 <b>결과</b> — 이슈 #79.
 *
 * <p>보낸 값을 그대로 돌려주지 않는다. 서버가 실제로 쓴 값은
 * {@code GREATEST(last_read_seq, LEAST(:seq, room.last_seq))} 라 요청한 값과 다를 수 있고,
 * 두 경우 모두 <b>정상</b>이다 — 뒤늦게 도착한 작은 값은 무시되고(뒤로 안 감), 방의 마지막
 * 번호를 넘는 값은 잘린다(미읽음이 음수가 되지 않게). 앱이 낙관적으로 그린 뱃지를 서버
 * 기준으로 되맞추려면 <b>쓰인 값</b>이 필요하다.
 *
 * @param unread {@code room.last_seq − last_read_seq}. 상한이 걸려 있으므로 음수가 아니다
 */
public record ChatReadView(long lastReadSeq, long unread) {
}
