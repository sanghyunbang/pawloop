package com.heattrip.heat_trip_backend.community;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * 커뮤니티 세 표의 시각 규약 — <b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b>
 *
 * <h2>왜 {@code LocalDateTime.now()} 가 아닌가</h2>
 * <p>{@code Walk} 이 #40 에서 정한 것과 같은 규약이고, 그 클래스 javadoc 이 이유를 적어 뒀다.
 *
 * <blockquote>이 저장소의 다른 표들은 {@code LocalDateTime.now()} 를 쓴다 — 즉 <b>JVM 의 기본
 * 시간대</b>가 무엇이냐에 따라 담기는 값이 달라진다. 개발 기계는 KST 이고 CI 컨테이너는 UTC 라,
 * 같은 코드가 환경마다 다른 값을 넣는다. 평소에는 안 보이지만 <b>주 경계·날 경계를 계산하는
 * 순간 드러난다</b> — #40 에서 예산 테스트가 <b>00:00–09:00 KST 에만</b> 빨간불이 나던 것이
 * 정확히 그 문제였다.</blockquote>
 *
 * <p>#169 는 이 규약을 안 따르고 {@code LocalDateTime.now()} 를 썼다. 커뮤니티에서는 그것이
 * 두 가지로 새어 나왔다.
 *
 * <ol>
 *   <li><b>커서.</b> {@code created_at} 이 커서의 첫 축이다. 서버 시간대가 바뀌면(배포 환경이
 *       달라지거나 컨테이너 시계가 다르면) 새 행이 옛 행보다 <b>이른</b> 값을 갖게 되고,
 *       그러면 목록이 건너뛰거나 되돌아간다.</li>
 *   <li><b>응답.</b> {@code LocalDateTime} 은 Jackson 이 오프셋 없이 직렬화한다
 *       ({@code "2026-09-03T00:25:33.92"}). 계약은 {@code format: date-time} 이라고 선언해
 *       뒀는데 그건 오프셋이 있어야 성립하는 형식이다. 앱은 {@code DateTime.tryParse(...)}
 *       가 오프셋 없는 문자열을 <b>기기 지역 시각</b>으로 읽으므로, 서버와 기기의 시간대가
 *       다르면 그 차이만큼 어긋난 시각을 그린다.</li>
 * </ol>
 *
 * <h2>왜 컬럼을 {@code TIMESTAMP} 로 안 바꾸나</h2>
 * <p>{@code LocalDateTime} 은 <b>드라이버가 시간대 변환을 하지 않는 유일한 타입</b>이다
 * ({@code Walk} javadoc). JDBC URL 의 {@code serverTimezone} 이나 컨테이너 시계가 무엇이든
 * 넣은 값이 그대로 나온다. 그래서 컬럼은 그대로 두고 <b>넣는 값만</b> UTC 로 눕힌다.
 *
 * <p>패키지 루트에 둔다 — 엔티티 셋과 서비스가 함께 부르는 어휘라 어느 한 하위 패키지에
 * 속하지 않는다({@code dog.DogOwnership} 이 같은 자리에 있다).
 *
 * <p>이 클래스가 따로 있는 이유는 표가 셋이고 규약이 하나여야 하기 때문이다. 세 엔티티가
 * 각자 {@code Instant.now()} 를 부르면, 그중 하나를 고치는 날 나머지 둘이 남는다.
 */
public final class CommunityTime {

    private CommunityTime() {
    }

    /** 지금을 UTC 로 눕힌 값. {@code @PrePersist} 가 부른다. */
    public static LocalDateTime nowUtc() {
        return LocalDateTime.ofInstant(Instant.now(), ZoneOffset.UTC);
    }

    /** 저장된 값을 다시 시각으로 세운다. 응답이 오프셋을 갖게 하는 자리다. */
    public static Instant toInstant(LocalDateTime storedAsUtc) {
        return storedAsUtc == null ? null : storedAsUtc.toInstant(ZoneOffset.UTC);
    }
}
