package com.heattrip.heat_trip_backend.user;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * {@code users} 의 시각 규약 — <b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b> 이슈 #248.
 *
 * <h2>무엇이 문제였나</h2>
 * <p>{@code User} 의 {@code @PrePersist}·{@code @PreUpdate} 가 {@code LocalDateTime.now()} 를
 * 썼다 — <b>JVM 기본 존</b>이다. 개발 기계는 KST 고 배포 컨테이너는 UTC 라, 같은 코드가
 * 환경마다 다른 값을 넣는다. dev DB 에 실제로 두 존이 섞여 있다(#248 에 실측을 적었다).
 *
 * <p>그리고 {@code GET /auth/me} 의 {@code createdAt}·{@code updatedAt} 이 <b>오프셋 없이</b>
 * 나갔다. 계약은 {@code format: date-time} 이라고 선언했고 그건 RFC3339 오프셋이 있어야
 * 성립한다 — 앱은 오프셋 없는 문자열을 기기 지역 시각으로 읽는다.
 *
 * <h2>왜 UTC 인가</h2>
 * <p>가입 시각과 수정 시각은 <b>서버가 찍는 순간</b>이지 사람이 고른 벽시계가 아니다. 케어의
 * {@code occurred_at} 처럼 하루 경계를 갖는 값이었다면 서비스 존이 맞겠지만(#247), 여기는
 * 아니다. 산책(#40)·커뮤니티·채팅이 이미 UTC 이고 같은 규약을 따른다.
 *
 * <h2>왜 클래스가 또 하나인가</h2>
 * <p>{@code user} 는 {@code allowedDependencies = &#123;&#125;} 다 — 다른 모듈을 하나도 못
 * 부른다. {@code CommunityTime} 도 {@code ChatTime} 도 여기서는 못 쓴다. 두 줄을 옮겨 적는
 * 대신 경계를 여는 것이 더 비싸다.
 *
 * <p>그렇다고 엔티티와 DTO 에 각각 적으면, 한쪽을 고치는 날 다른 쪽이 남는다 — 쓰는 존과
 * 읽는 존이 갈리면 <b>같은 값이 9시간 움직인다.</b> 그래서 한 곳이다.
 */
public final class UserTime {

    private UserTime() {
    }

    /** 지금을 UTC 로 눕힌 값. {@code @PrePersist}·{@code @PreUpdate} 가 부른다. */
    public static LocalDateTime nowUtc() {
        return LocalDateTime.ofInstant(Instant.now(), ZoneOffset.UTC);
    }

    /** 저장된 값을 다시 시각으로 세운다. 응답이 오프셋을 갖게 하는 자리다. */
    public static Instant toInstant(LocalDateTime storedAsUtc) {
        return storedAsUtc == null ? null : storedAsUtc.toInstant(ZoneOffset.UTC);
    }
}
