package com.heattrip.heat_trip_backend.user.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * Refresh Token 원장 한 행. (이슈 #9)
 *
 * <p><b>토큰 원문은 어디에도 저장하지 않는다.</b> {@link #tokenHash} 에는 SHA-256 hex(64자)만
 * 들어간다. 원문은 응답·딥링크로만 나가고 서버는 그 값을 다시 만들 수 없다.
 *
 * <p>해시가 <b>결정적</b>이어야 하는 이유: 회전은 {@code findByTokenHash} 인덱스 조회로 시작한다.
 * BCrypt 처럼 솔트가 매번 다른 함수를 쓰면 조회가 성립하지 않고 전 행을 스캔하며
 * {@code matches()} 를 돌려야 한다. 키 스트레칭은 저엔트로피 비밀번호를 위한 장치라
 * 256bit 균일 난수에는 이득이 없다.
 *
 * <p><b>{@code users} 로의 FK 를 걸지 않는다.</b> 사용자를 {@code Long userId} 로만 들고 있고
 * 연관 매핑({@code @ManyToOne})을 쓰지 않는다. 이유는 두 가지다.
 * <ul>
 *   <li>{@code Long} 필드에 대해 dev 의 {@code ddl-auto=update} 는 FK 를 만들지 않는다.
 *       마이그레이션 SQL 로만 FK 를 걸면 dev 와 prod 스키마가 갈라지고,
 *       {@code validate} 는 FK 를 검사하지 않아 그 차이를 아무도 모른다.</li>
 *   <li>{@code @ManyToOne} 으로 바꿔 dev/prod 를 맞추면 Hibernate 가
 *       {@code ON DELETE CASCADE} 를 만들어 주지 않으므로 FK 가 오히려
 *       {@code DELETE /auth/me} 를 막는다.</li>
 * </ul>
 * 탈퇴 정리는 {@code UserService.deleteMe} 가 사용자보다 <b>먼저</b> RT 를 지우는 것으로
 * 보장하고, {@code UserServiceTest} 의 {@code InOrder} 단언이 그 순서를 잠근다.
 *
 * <p>인덱스 세 개는 접근 경로 세 개와 1:1 이다 — 회전 조회(token_hash) / 전 기기 폐기·탈퇴
 * 삭제(user_id) / 만료 정리 범위 스캔(expires_at).
 *
 * <p>{@code device_id} 컬럼은 두지 않았다. 계약에 기기를 식별할 헤더가 없고 로그아웃은
 * 계약상 전 기기라, 기기별 폐기를 소비할 코드가 하나도 없다. 소비자 없이 형식만 먼저 박지
 * 않는다 — {@code jti}·{@code prv} 에 대해 #5 가 세운 판단과 같다.
 */
@Entity
@Table(
        name = "refresh_token",
        uniqueConstraints = {
                @UniqueConstraint(name = "uk_refresh_token_token_hash", columnNames = {"token_hash"})
        },
        indexes = {
                @Index(name = "idx_refresh_token_user_id", columnList = "user_id"),
                @Index(name = "idx_refresh_token_expires_at", columnList = "expires_at")
        }
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class RefreshToken {

    /** SHA-256 을 hex 로 적으면 정확히 64자다. 컬럼 길이가 이 사실에 묶여 있다. */
    public static final int TOKEN_HASH_LENGTH = 64;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** {@code users.id}. 연관 매핑이 아니다(위 javadoc 참조). */
    @Column(name = "user_id", nullable = false)
    private Long userId;

    /**
     * 토큰 원문의 SHA-256 hex.
     *
     * <p>UNIQUE 다. "해시 1개 = 행 1개"가 깨지면 {@code findByTokenHash} 가 어느 행을 줄지
     * 미정이 되고, 재사용 감지의 전제가 사라진다. 마이그레이션 SQL 의 사후 검증이
     * 운영 스키마에서 이 제약을 다시 확인한다 — {@code validate} 는 UNIQUE 를 보지 않는다.
     */
    @Column(name = "token_hash", nullable = false, length = TOKEN_HASH_LENGTH)
    private String tokenHash;

    @Column(name = "expires_at", nullable = false)
    private LocalDateTime expiresAt;

    /**
     * 폐기 시각. null 이면 살아 있다.
     *
     * <p><b>폐기해도 행을 지우지 않는다.</b> 지우면 "이미 회전된 RT 가 다시 왔다"를 구분할 수
     * 없어져 재사용 감지가 불가능해진다. 행 정리는 만료 뒤 {@code purgeExpired()} 가 한다.
     */
    @Column(name = "revoked_at")
    private LocalDateTime revokedAt;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;
}
