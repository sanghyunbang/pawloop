package com.heattrip.heat_trip_backend.chat;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * 채팅 다섯 표의 시각 규약 — <b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b> 이슈 #248.
 *
 * <h2>고치기 전에는 한 모듈 안에 존이 둘이었다</h2>
 * <p>같은 표에 값을 넣는 길이 둘인데 서로 다른 존을 읽고 있었다.
 *
 * <ul>
 *   <li>엔티티의 {@code @PrePersist} → {@code LocalDateTime.now()} = <b>JVM 기본 존</b></li>
 *   <li>{@code ChatRoomService} → {@code LocalDateTime.now(clock)} = <b>{@code Asia/Seoul}</b>
 *       ({@code ClockConfig} 가 #209 에서 그 존을 박았다)</li>
 * </ul>
 *
 * <p>개발 기계가 KST 라 둘이 같은 값을 낸다. <b>컨테이너는 UTC 다 — 실측</b>
 * ({@code mysql/post-start/12_walk.sql} 이 적어 뒀다). 거기서는 같은 행의
 * {@code created_at} 과 {@code expires_at} 이 9시간 어긋난다. 초대코드는 발급 순간
 * 만료된 것처럼 보이거나 TTL 보다 9시간 더 산다.
 *
 * <p>실제로 그렇게 섞여 있었다 — dev DB 의 {@code users} 15번은 {@code 01:07:38}(JVM 존)에
 * 만들어졌고 0.78초 뒤 쓴 글의 {@code created_at} 은 {@code 01:07:39}(UTC 규약)다.
 * <b>그 행을 쓴 JVM 은 UTC 였다.</b> 같은 표의 다른 행들은 KST 로 들어와 있다.
 *
 * <h2>왜 UTC 인가 — 서비스 존이 아니라</h2>
 * <p>이 값들은 <b>서버가 찍는 순간</b>이지 사람이 고른 벽시계가 아니다. 케어의
 * {@code occurred_at} 은 "아침에 밥 줬다" 는 벽시계라 하루 경계가 KST 여야 하지만(#247),
 * {@code created_at}·{@code joined_at} 에는 그런 뜻이 없다. 산책(#40)과 커뮤니티가 이미
 * UTC 를 골랐고 {@link com.heattrip.heat_trip_backend.community.CommunityTime} 이 그 이유를
 * 적어 뒀다 — 여기도 같은 규약이다.
 *
 * <h2>왜 컬럼을 {@code TIMESTAMP} 로 안 바꾸나</h2>
 * <p>{@code LocalDateTime} 은 드라이버가 시간대 변환을 하지 않는 유일한 타입이다. JDBC URL 의
 * {@code serverTimezone} 이 무엇이든 넣은 값이 그대로 나온다. 그래서 컬럼은 그대로 두고
 * <b>넣는 값만</b> 눕힌다.
 *
 * <h2>왜 {@code CommunityTime} 을 안 쓰나</h2>
 * <p>{@code chat} 은 {@code allowedDependencies = &#123;&#125;} 다 — 나가는 화살표가 0인
 * 유일한 도메인이고, {@code ChatBoundaryArchitectureTest} §B 가 그것을 import 든
 * 완전수식명이든 막는다. 그 경계를 시각 헬퍼 하나 때문에 열 이유가 없다.
 *
 * <p>모듈 패키지 <b>바로 아래</b>에 둔다. {@code chatweb} 과 {@code group} 이 이 타입으로
 * 응답을 세우므로 공개 표면이어야 한다 — 하위 패키지에 두면 그 둘이 모듈 경계를 넘는다.
 */
public final class ChatTime {

    private ChatTime() {
    }

    /** 지금을 UTC 로 눕힌 값. 엔티티의 {@code @PrePersist} 가 부른다. */
    public static LocalDateTime nowUtc() {
        return LocalDateTime.ofInstant(Instant.now(), ZoneOffset.UTC);
    }

    /**
     * 주입된 시계의 지금을 UTC 로 눕힌 값. 서비스가 부른다.
     *
     * <p><b>시계의 존을 안 읽는다.</b> {@link Clock#instant()} 만 쓰므로 빈이 주는 존이
     * {@code Asia/Seoul} 이어도 결과는 UTC 다 — 그 존은 케어의 "오늘" 경계를 위한 것이고
     * 여기서 따라가면 다시 존이 둘이 된다. 테스트가 고정하는 것은 <b>순간</b>이라
     * {@code Clock.fixed} 는 그대로 동작한다.
     */
    public static LocalDateTime nowUtc(Clock clock) {
        return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    }

    /** 저장된 값을 다시 시각으로 세운다. 응답이 오프셋을 갖게 하는 자리다. */
    public static Instant toInstant(LocalDateTime storedAsUtc) {
        return storedAsUtc == null ? null : storedAsUtc.toInstant(ZoneOffset.UTC);
    }
}
