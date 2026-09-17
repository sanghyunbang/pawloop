package com.heattrip.heat_trip_backend.user.mail;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.mail.MailSendException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.JavaMailSenderImpl;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

/**
 * <b>발송 자격이 없는 환경이 정상이다</b> — 이슈 #635.
 *
 * <h2>이 검사가 지키는 것</h2>
 *
 * <p>dev·테스트에는 SMTP 자격이 없고, 운영도 SES 프로덕션 액세스가 승인되기 전에는
 * 아무에게나 못 보낸다. 그 사이에 서버가 안 뜨거나 요청마다 예외가 나면, 이메일과 무관한
 * 모든 기능이 함께 멈춘다.
 *
 * <p>스프링 컨텍스트를 안 띄우고 {@link MailConfig#mailer} 를 직접 부른다 — 재려는 것이
 * "설정을 보고 무엇을 고르는가" 하나라서, 컨텍스트를 띄우면 그 판정이 다른 설정에 섞인다.
 */
class MailerSelectionTest {

    @Test
    @DisplayName("보내는 사람이 비어 있으면 안 보내고 로그만 남긴다 — 서버는 그대로 뜬다")
    void blankFromFallsBackToLogging() {
        Mailer mailer = new MailConfig().mailer(properties(""), provider(new JavaMailSenderImpl()));

        assertThat(mailer).isInstanceOf(LoggingMailer.class);
        assertThat(mailer.send("walker@example.test", "제목", "본문"))
                .as("안 보냈으면 거짓이어야 한다 — 참이면 앱이 '메일 확인하세요' 를 띄우고 사용자는 영원히 기다린다")
                .isFalse();
    }

    @Test
    @DisplayName("JavaMailSender 빈이 아예 없어도 뜬다 — spring.mail.host 가 없으면 그 빈이 안 만들어진다")
    void aMissingSenderBeanIsNotAnError() {
        // 여기서 컨텍스트가 죽던 자리다. ObjectProvider 가 아니라 직접 주입하면
        // 메일을 안 쓰는 환경 전부가 부팅에서 멈춘다.
        assertThatCode(() -> assertThat(
                new MailConfig().mailer(properties("Pawloop <no-reply@pawloop.app>"), provider(null)))
                .isInstanceOf(LoggingMailer.class))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("둘 다 있으면 SMTP 로 보낸다 — 보내는 사람이 실제로 실린다")
    void configuredSendsOverSmtp() {
        RecordingSender sender = new RecordingSender();

        Mailer mailer = new MailConfig()
                .mailer(properties("Pawloop <no-reply@pawloop.app>"), provider(sender));

        assertThat(mailer).isInstanceOf(SmtpMailer.class);
        assertThat(mailer.send("walker@example.test", "Pawloop 인증 코드", "012345")).isTrue();
        assertThat(sender.sent).hasSize(1);
        assertThat(sender.sent.get(0).getFrom())
                .as("SES 는 인증 안 된 발신 주소를 거절한다 — 안 실리면 전부 실패한다")
                .isEqualTo("Pawloop <no-reply@pawloop.app>");
    }

    @Test
    @DisplayName("발송이 터져도 던지지 않는다 — 대기 행은 이미 있고 다시 보내기만 하면 된다")
    void aFailedSendIsSwallowed() {
        Mailer mailer = new SmtpMailer(new FailingSender(), "no-reply@pawloop.app");

        assertThat(mailer.send("walker@example.test", "제목", "본문"))
                .as("실패를 참으로 돌려주면 '메일 안 왔어요' 에 앱이 해 줄 말이 없다")
                .isFalse();
    }

    @Test
    @DisplayName("로그에 주소를 통째로 안 남긴다")
    void addressesAreMaskedInLogs() {
        assertThat(LoggingMailer.mask("bangsanghyun@naver.com")).isEqualTo("ba***@naver.com");
        // 앞이 두 글자 이하면 가릴 것이 없다 — 그때는 통째로 가린다.
        assertThat(LoggingMailer.mask("ab@naver.com")).isEqualTo("***@naver.com");
        assertThat(LoggingMailer.mask("")).isEqualTo("(없음)");
        assertThat(LoggingMailer.mask(null)).isEqualTo("(없음)");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static MailProperties properties(String from) {
        MailProperties properties = new MailProperties();
        properties.setFrom(from);
        return properties;
    }

    /** {@code getIfAvailable()} 만 쓰는 자리라 그 하나만 답한다. */
    private static ObjectProvider<JavaMailSender> provider(JavaMailSender sender) {
        return new ObjectProvider<>() {
            @Override
            public JavaMailSender getIfAvailable() {
                return sender;
            }

            @Override
            public JavaMailSender getObject() {
                throw new UnsupportedOperationException();
            }

            @Override
            public JavaMailSender getObject(Object... args) {
                throw new UnsupportedOperationException();
            }

            @Override
            public JavaMailSender getIfUnique() {
                return sender;
            }
        };
    }

    private static final class RecordingSender extends JavaMailSenderImpl {
        private final List<SimpleMailMessage> sent = new ArrayList<>();

        @Override
        public void send(SimpleMailMessage simpleMessage) {
            sent.add(simpleMessage);
        }
    }

    private static final class FailingSender extends JavaMailSenderImpl {
        @Override
        public void send(SimpleMailMessage simpleMessage) {
            throw new MailSendException("SES 가 거절했다(샌드박스 밖 수신자)");
        }
    }
}
