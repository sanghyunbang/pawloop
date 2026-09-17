package com.heattrip.heat_trip_backend.user.mail;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;

/**
 * SMTP 로 보낸다 — 이슈 #635. 운영에서는 AWS SES 의 SMTP 끝점을 쓴다.
 *
 * <h2>왜 AWS SDK 가 아니라 SMTP 인가</h2>
 * <p>SES 는 SMTP 끝점을 준다({@code email-smtp.ap-northeast-2.amazonaws.com:587}). 그러면
 * 이미 있는 {@code spring-boot-starter-mail} 로 끝나고 <b>AWS SDK 의존성이 안 늘어난다.</b>
 * 나중에 발송처를 바꿔도 여기만 갈면 된다.
 *
 * <h2>실패를 삼킨다</h2>
 * <p>{@link Mailer} 의 약속대로 예외를 밖으로 던지지 않는다. 가입 요청이 500 으로 끝나면
 * 사용자는 무엇을 해야 할지 모르는데, 대기 행은 이미 있어서 <b>다시 보내기만 하면</b> 되는
 * 상태다.
 *
 * <p>대신 <b>왜 실패했는지는 남긴다.</b> SES 는 인증 안 된 발신 주소·샌드박스 밖 수신자를
 * 각각 다른 메시지로 거절하는데, 그 구분이 로그에 없으면 "메일이 안 간다" 만 남는다.
 */
public class SmtpMailer implements Mailer {

    private static final Logger log = LoggerFactory.getLogger(SmtpMailer.class);

    private final JavaMailSender sender;
    private final String from;

    public SmtpMailer(JavaMailSender sender, String from) {
        this.sender = sender;
        this.from = from;
    }

    @Override
    public boolean send(String to, String subject, String body) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(from);
        message.setTo(to);
        message.setSubject(subject);
        message.setText(body);
        try {
            sender.send(message);
            return true;
        } catch (RuntimeException failed) {
            // 주소는 가리고 사유는 남긴다. 본문(코드)은 절대 안 남긴다.
            log.warn("메일 발송 실패 — 받는 사람 {} · 사유 {}",
                    LoggingMailer.mask(to), failed.getMessage());
            return false;
        }
    }
}
