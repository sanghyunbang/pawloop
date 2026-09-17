package com.heattrip.heat_trip_backend.user.mail;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 안 보내고 로그만 남긴다 — 이슈 #635. 발송 자격이 없는 환경의 기본값이다.
 *
 * <h2>코드를 로그에 찍는다 — dev 에서만</h2>
 * <p>에뮬레이터로 가입을 걸어 보려면 코드를 알아야 한다. 메일이 안 가는 환경에서 그 코드를
 * 아무 데도 안 남기면 <b>가입 흐름 자체를 시험할 수 없다.</b>
 *
 * <p>운영에서는 이 구현이 안 쓰인다({@code from} 이 설정돼 있으면 {@link SmtpMailer} 다).
 * 그래도 혹시 설정을 빠뜨린 채 뜬 운영 서버가 <b>인증 코드를 로그에 뿌리는</b> 일은 막아야
 * 하므로, 본문은 {@code debug} 로만 남긴다 — 운영 로그 수준은 {@code info} 다.
 */
public class LoggingMailer implements Mailer {

    private static final Logger log = LoggerFactory.getLogger(LoggingMailer.class);

    @Override
    public boolean send(String to, String subject, String body) {
        log.info("메일을 안 보냈다 — app.mail.from 이 비어 있다. 받는 사람 {} · 제목 {}",
                mask(to), subject);
        log.debug("메일 본문(dev 전용)\n{}", body);
        return false;
    }

    /** 로그에 주소를 통째로 남기지 않는다. {@code ab***@naver.com} */
    static String mask(String email) {
        if (email == null || email.isBlank()) {
            return "(없음)";
        }
        int at = email.indexOf('@');
        if (at <= 2) {
            return "***" + (at < 0 ? "" : email.substring(at));
        }
        return email.substring(0, 2) + "***" + email.substring(at);
    }
}
