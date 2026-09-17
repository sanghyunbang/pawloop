package com.heattrip.heat_trip_backend.user.mail;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.mail.javamail.JavaMailSender;

/**
 * 어느 {@link Mailer} 를 쓸지 고른다 — 이슈 #635.
 *
 * <p>설정이 있으면 SMTP, 없으면 로그다. <b>고르는 자리가 하나</b>여야 "이 서버가 메일을
 * 보내는가" 를 한 줄로 답할 수 있다.
 *
 * <p>{@code JavaMailSender} 를 {@link ObjectProvider} 로 받는 것은 {@code spring.mail.host}
 * 가 없으면 그 빈이 아예 안 만들어지기 때문이다. 직접 주입하면 그때 컨텍스트가 죽는다 —
 * 메일을 안 쓰는 dev·테스트가 전부 못 뜬다.
 */
@Configuration
@EnableConfigurationProperties(MailProperties.class)
public class MailConfig {

    private static final Logger log = LoggerFactory.getLogger(MailConfig.class);

    @Bean
    public Mailer mailer(MailProperties properties, ObjectProvider<JavaMailSender> senders) {
        JavaMailSender sender = senders.getIfAvailable();
        if (!properties.isConfigured() || sender == null) {
            log.info("메일 발송이 꺼져 있다 — app.mail.from {} · JavaMailSender {}",
                    properties.isConfigured() ? "있음" : "없음", sender == null ? "없음" : "있음");
            return new LoggingMailer();
        }
        log.info("메일 발송이 켜져 있다 — 보내는 사람 {}", LoggingMailer.mask(properties.getFrom()));
        return new SmtpMailer(sender, properties.getFrom());
    }
}
