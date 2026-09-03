package com.heattrip.heat_trip_backend.care;

import com.heattrip.heat_trip_backend.care.dto.CareLogResponse;
import com.heattrip.heat_trip_backend.care.entity.CareLog;
import com.heattrip.heat_trip_backend.care.entity.CareType;
import com.heattrip.heat_trip_backend.config.ClockConfig;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.TimeZone;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * "오늘" 의 경계와 시각의 오프셋 — 이슈 #209({@code Groups-medium-6}).
 *
 * <h2>무엇이 문제였나</h2>
 * <p>{@code ClockConfig} 가 {@code systemDefaultZone()} 이었다. 그건 <b>배포 환경의
 * {@code TZ} 환경변수 하나로 조용히 바뀐다</b> — 서버를 UTC 로 옮기면 KST 00:00~08:59 에 찍은
 * 케어 기록이 '어제' 가 되어 <b>이중 급여 방지 화면에서 사라진다.</b> 밥을 두 번 주지 않게
 * 하는 것이 그 기능의 목적이라 조용히 틀리는 것이 가장 나쁘다.
 *
 * <p>그리고 응답의 {@code occurredAt} 이 <b>오프셋 없이</b> 나갔다. 계약은
 * {@code format: date-time} 이라고 선언했고 그건 RFC3339 오프셋이 있어야 성립한다 —
 * 앱은 오프셋 없는 문자열을 기기 지역 시각으로 읽으므로 해외에 있는 가족이 보면 어긋난다.
 *
 * <h2>스프링을 안 띄운다</h2>
 * <p>재는 것이 <b>존 계산</b>뿐이라 컨텍스트가 필요 없다(#21).
 *
 * <p><b>직렬화는 여기서 안 잰다.</b> 이 클래스가 만든 {@code ObjectMapper} 는 앱의 매퍼가
 * 아니다 — 부트가 자동 구성으로 {@code WRITE_DATES_AS_TIMESTAMPS} 를 끄는데, 손으로 만든
 * 매퍼는 그것이 켜져 있어 {@code Instant} 를 <b>숫자</b>로 낸다. 그 차이를 모르고 여기서
 * 단언하면 앱이 받는 것과 다른 것을 재게 된다. 실제 응답의 형식은
 * {@code CareSharingIntegrationTest} 가 HTTP 로 잰다.
 */
class CareTimeZoneTest {

    /** KST 2026-09-03 00:30 — UTC 로는 아직 9월 2일이다. 여기가 갈리는 자리다. */
    private static final LocalDateTime EARLY_MORNING_KST =
            LocalDateTime.of(2026, 9, 3, 0, 30);

    @Test
    @DisplayName("서비스 존이 Asia/Seoul 로 박혀 있다 — JVM 기본 존을 UTC 로 바꿔도 안 따라간다")
    void serviceZoneIsPinnedRegardlessOfTheJvmDefault() {
        assertThat(ClockConfig.SERVICE_ZONE).isEqualTo(ZoneId.of("Asia/Seoul"));

        // **JVM 기본 존을 실제로 바꿔서 본다.** 개발 기계가 이미 KST 라, 그냥 빈의 존만
        // 견주면 systemDefaultZone() 으로 되돌려도 초록불이 난다 — 그 테스트는 CI(UTC)에서만
        // 값을 하고 여기서는 아무것도 안 지킨다. 실제로 그렇게 확인했다.
        TimeZone original = TimeZone.getDefault();
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
            assertThat(new ClockConfig().clock().getZone())
                    .as("""
                            빈이 주는 시계의 존이 곧 '오늘' 의 경계다. systemDefaultZone() 이면 \
                            배포의 TZ 환경변수 하나로 바뀌고, KST 새벽 기록이 '어제' 가 된다.""")
                    .isEqualTo(ClockConfig.SERVICE_ZONE);
        } finally {
            TimeZone.setDefault(original);
        }
    }

    @Test
    @DisplayName("배포가 UTC 여도 KST 새벽 기록이 '오늘' 에 남는다 — 이게 이중 급여를 막는 자리다")
    void earlyMorningRecordStaysInToday() {
        Instant moment = EARLY_MORNING_KST.atZone(ClockConfig.SERVICE_ZONE).toInstant();

        // 배포 환경이 UTC 라고 가정한 시계. 고친 뒤에는 존이 빈에 박히므로 이 시계를 쓰는 일이
        // 없지만, 고치기 전 코드가 무엇을 봤는지가 그대로 드러난다.
        LocalDate asUtcDeployment = LocalDate.now(Clock.fixed(moment, ZoneOffset.UTC));
        LocalDate asService = LocalDate.now(Clock.fixed(moment, ClockConfig.SERVICE_ZONE));

        assertThat(asService).isEqualTo(LocalDate.of(2026, 9, 3));
        assertThat(asUtcDeployment)
                .as("""
                        UTC 로 자르면 같은 순간이 '어제' 다. 존을 안 박으면 배포 환경에 따라 \
                        이 둘 사이를 오간다 — 아침에 준 밥이 목록에서 사라진다.""")
                .isEqualTo(LocalDate.of(2026, 9, 2));
        assertThat(asService).isNotEqualTo(asUtcDeployment);
    }

    @Test
    @DisplayName("컬럼의 로컬 시각을 서비스 존에서 인스턴트로 세운다 — 다른 존에서 세우면 9시간 어긋난다")
    void theStoredLocalTimeIsInterpretedInTheServiceZone() {
        CareLogResponse response = CareLogResponse.of(CareLog.builder()
                .id(1L)
                .type(CareType.MEAL)
                .occurredAt(EARLY_MORNING_KST)
                .build());

        assertThat(response.occurredAt())
                .isEqualTo(EARLY_MORNING_KST.atZone(ClockConfig.SERVICE_ZONE).toInstant());
        assertThat(response.occurredAt())
                .as("UTC 로 세우면 같은 문자열이 9시간 뒤의 순간이 된다")
                .isNotEqualTo(EARLY_MORNING_KST.toInstant(ZoneOffset.UTC));
    }
}
