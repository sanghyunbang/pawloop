package com.heattrip.heat_trip_backend.user.mail;

/**
 * 메일 한 통을 보낸다 — 이슈 #635.
 *
 * <h2>왜 인터페이스인가</h2>
 * <p>발송 자격이 <b>없는 환경이 정상</b>이기 때문이다. dev 와 테스트에는 SMTP 자격이 없고,
 * prod 도 SES 프로덕션 액세스가 승인되기 전에는 아무에게나 못 보낸다. 그 사이에 서버가
 * 안 뜨면 이메일과 무관한 모든 기능이 함께 멈춘다.
 *
 * <p>{@code APPLE_TEAM_ID} 셋이 비었을 때 Apple 버튼만 막고 나머지는 그대로 사는 것과
 * 같은 판단이다(#301).
 *
 * <h2>실패를 던지지 않는다</h2>
 * <p>보내기가 실패해도 <b>예외를 밖으로 던지지 않는다.</b> 가입 요청이 500 으로 끝나면
 * 사용자는 무엇을 해야 할지 모르는데, 실제로는 대기 행이 이미 만들어져 있어 <b>코드를 다시
 * 받기만 하면</b> 되는 상태다. 대신 {@link #send}가 {@code false} 를 돌려주고 부르는 쪽이
 * "메일을 못 보냈어요 · 다시 보내기" 를 말한다.
 */
public interface Mailer {

    /**
     * 보낸다. 성공하면 {@code true}.
     *
     * @param to      받는 사람
     * @param subject 제목
     * @param body    본문(평문). HTML 을 안 쓰는 것은 의도다 — 인증 코드 한 줄에 HTML 이
     *                필요 없고, 평문이 스팸 판정에도 유리하다
     */
    boolean send(String to, String subject, String body);
}
