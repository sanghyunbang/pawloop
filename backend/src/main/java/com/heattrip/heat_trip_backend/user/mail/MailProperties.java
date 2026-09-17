package com.heattrip.heat_trip_backend.user.mail;

import lombok.Getter;
import lombok.Setter;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 메일 발송 설정 — 이슈 #635.
 *
 * <p>{@link #from} 이 비어 있으면 <b>발송을 아예 안 한다</b>({@link LoggingMailer}). 자격이
 * 없는 환경에서 서버가 안 뜨거나 요청마다 예외가 나는 것보다, 안 보내고 그 사실을 로그에
 * 남기는 편이 낫다.
 *
 * <p>{@link #from} 은 <b>SES 에서 인증한 주소</b>여야 한다. 아무 주소나 넣으면 SES 가
 * 거절하고, 그 실패는 발송 시점에야 보인다.
 */
@Getter
@Setter
@ConfigurationProperties(prefix = "app.mail")
public class MailProperties {

    /** 보내는 사람. 비어 있으면 발송을 안 한다. 예: {@code Pawloop <no-reply@pawloop.app>} */
    private String from = "";

    /** 인증 코드가 사는 시간(분). 짧으면 메일이 늦게 올 때 못 쓰고, 길면 남의 메일함에 오래 산다. */
    private int codeTtlMinutes = 10;

    /** 한 코드에 허용하는 틀린 시도 횟수. 넘으면 그 코드를 죽인다 — 6자리는 100만분의 1이다. */
    private int maxAttempts = 5;

    public boolean isConfigured() {
        return from != null && !from.isBlank();
    }
}
