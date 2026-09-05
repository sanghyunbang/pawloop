package com.heattrip.heat_trip_backend.consent.entity;

import com.heattrip.heat_trip_backend.consent.ConsentKind;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

import org.hibernate.annotations.Check;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 동의 한 건 — <b>덧붙이기만 한다</b>. 이슈 #190.
 *
 * <h2>행을 고치지 않는다</h2>
 * <p>동의도 철회도 새 행이다. "지금 상태" 는 계정·문서별 <b>마지막 행</b>이다. 그래서
 * 세터가 없다. 고치는 순간 "그때 무엇에 동의했는가" 가 사라진다.
 *
 * <h2>{@code users} 로 FK 를 안 건다</h2>
 * <p>{@code report} 와 같은 판단이다. 탈퇴가 {@code users} 행을 물리 삭제하는데
 * ({@code UserService.deleteMe}), CASCADE 면 "동의했었다" 는 기록이 탈퇴와 함께 사라지고
 * RESTRICT 면 동의한 사람은 영구히 탈퇴 불가가 된다. 값으로만 가리킨다.
 *
 * <h2>{@code createdAt} 은 UTC 다</h2>
 * <p>{@code ConsentTime} 참조. {@code @PrePersist} 를 안 두는 이유는 그 훅이 {@code null}
 * 일 때만 채우는 모양이 되기 쉬워서다 — 서비스가 시계를 받아 직접 찍는다.
 */
@Entity
@Table(name = "user_consent",
        indexes = @Index(name = "idx_user_consent_user", columnList = "user_id, id"))
@Check(name = "chk_user_consent_kind",
        constraints = "kind in ('TERMS','PRIVACY','LOCATION','MARKETING')")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class UserConsent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    /**
     * {@link ConsentKind#name()} 을 담는 <b>문자열</b>이다 — 자바 enum 으로 매핑하지 않는다.
     *
     * <p>Hibernate 6 은 {@code @Enumerated(STRING)} 을 MySQL 에서 {@code enum('...')} 컬럼으로
     * 뽑고, VARCHAR 로 강제해도 <b>이름 없는 CHECK 를 하나 더</b> 뽑는다({@code user_consent_chk_1},
     * 실측). 그러면 정본 스키마에 같은 제약이 둘이 되고 마이그레이션은 하나만 만든다.
     * {@code report_snapshot.target_type} 처럼 문자열 + 이름 있는 {@code @Check} 하나로 둔다 —
     * 종류가 늘면 CHECK 만 고친다. 타입 안전은 {@link #kind()} 가 돌려준다.
     */
    @Column(name = "kind", nullable = false, length = 16)
    private String kind;

    /** 문서 버전. {@code v1.2} 모양이다 — 계약이 패턴으로 잠근다. */
    @Column(name = "version", nullable = false, length = 16)
    private String version;

    /** {@code false} 는 철회다. 행을 지우는 것이 아니라 새 행으로 남긴다. */
    @Column(name = "agreed", nullable = false)
    private boolean agreed;

    /** 서버가 찍은 시각. 담긴 값이 UTC 다. */
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /** 저장된 문자열을 enum 으로. CHECK 가 넷만 허용하므로 여기서 실패할 값은 없다. */
    public ConsentKind kind() {
        return ConsentKind.valueOf(kind);
    }
}
