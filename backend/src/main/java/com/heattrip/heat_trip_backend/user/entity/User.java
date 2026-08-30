package com.heattrip.heat_trip_backend.user.entity;

import jakarta.persistence.*; // JPA 어노테이션 제공 (Entity, Id, Table 등)
import lombok.*;              // 롬복(Lombok) 어노테이션 제공 (자동 코드 생성)
import java.time.LocalDateTime; // 시간 정보 (생성일, 수정일)를 다루는 클래스

// 이 클래스는 DB 테이블과 연결되는 엔티티 클래스

@Entity // JPA가 이 클래스를 엔티티로 인식하도록 하는 어노테이션 => DB 테이블과 매핑됨
// 소셜 계정의 식별 키는 (provider, social_id) 쌍이다. 이메일이 아니다. (이슈 #7)
// 카카오는 account_email 이 '선택 동의'라서 이메일을 주지 않을 수 있고, 그러면 이메일로는
// 같은 사람을 다시 알아볼 수 없다. 이 UNIQUE 제약이 "한 소셜 계정 = 한 행"을 DB 수준에서 보증한다.
// NULL 은 서로 다른 값으로 취급되므로(MySQL·H2 동일) 이메일 가입자(social_id = NULL)는
// 여러 명이 있어도 제약에 걸리지 않는다. — UserRepositoryTest 가 실제로 확인한다.
@Table(
        name = "users",
        uniqueConstraints = {
                @UniqueConstraint(name = "uk_users_provider_social_id",
                        columnNames = {"provider", "social_id"})
        }
)
@Getter // Lombok의 @Getter 어노테이션을 사용하여 모든 필드에 대한 getter 메서드를 자동 생성
@Setter // Lombok의 @Setter 어노테이션을 사용하여 모든 필드에 대한 setter 메서드를 자동 생성

@NoArgsConstructor // Lombok : 파라미터가 없는 기본 생성자 자동으로 생성
@AllArgsConstructor // Lombok : 모든 필드를 파라미터로 받는 생성자 자동으로 생성

@Builder // Lombok : 빌더 패턴을 사용하여 객체 생성 시 가독성을 높임
// - 빌더 패턴은 객체 생성 시 가독성을 높이고, 필수/선택 필드를 명확히 구분할 수 있게 해줌
// - 예: User user = User.builder().username("john").email("
public class User {

    /** 이메일/비밀번호로 가입한 사용자의 provider 값. 계약(openapi.yaml)의 User.provider enum 과 같은 문자열이다. */
    public static final String PROVIDER_LOCAL = "local";

    /** 기본 권한. DB 에 role 컬럼이 생기기 전에는 토큰 발급 때마다 하드코딩되던 값이다. (이슈 #7) */
    public static final String ROLE_USER = "ROLE_USER";

    @Id // 이 필드가 엔티티의 기본 키임을 나타냄
    @GeneratedValue(strategy = GenerationType.IDENTITY) // 기본 키 생성 전략을 지정 (자동 증가)
    private Long id; // 사용자 ID(PK)

    private String name; // 사용자 이름
    private String nickname; // 사용자 닉네임

    // enum : 제한된 값만 가질 수 있는 데이터 타입
    @Enumerated(EnumType.STRING) // enum 타입을 문자열로 저장
    private Gender gender; 

    private Integer age; // 사용자 나이

    /**
     * 레거시 소셜 식별자 (예: google_123456).
     *
     * <p>이제 식별 키가 아니다 — {@link #provider} + {@link #socialId} 가 정본이다.
     * 그래도 남겨 두는 이유:
     * <ul>
     *   <li>운영 DB 에 이 값만 들어 있는 행이 있고, 백필 SQL
     *       (backend/mysql/post-start/04_users_social_account_model.sql)이 돌기 전에도
     *       {@code UserRepository.findByUsername} 으로 그 행을 찾아 새 컬럼을 채워 넣어야 한다.
     *       (컬럼을 지우면 그 행들이 로그인할 때마다 중복 생성된다.)</li>
     *   <li>운영 프로파일은 {@code ddl-auto=validate} 라 JPA 쪽에서 필드를 지워도 컬럼은 남는다.
     *       삭제는 되돌릴 수 없으므로 백필 검증이 끝난 뒤 별도 이슈에서 다룬다.</li>
     * </ul>
     * 신규 소셜 가입 시에도 계속 채워 둔다(= {@code provider + "_" + socialId}).
     */
    private String username;

    /**
     * 계정 출처. {@code local} · {@code kakao} · {@code google}.
     * 계약(openapi.yaml)의 {@code User.provider} enum 과 값이 같아야 한다.
     *
     * <p>{@code naver} 는 ADR-0010 이 보류로 확정해 계약 enum 에서 빠졌다. 다만 <b>컬럼 값에
     * 제약이 있는 것은 아니다</b> — 운영 DB 에 {@code provider='naver'} 인 옛 행이 남아 있을
     * 수 있고, 백필 SQL 도 그 행을 다룬다({@code 04_users_social_account_model.sql}).
     */
    @Column(length = 20)
    private String provider;

    /**
     * 소셜 공급자가 발급한 사용자 고유 ID. 이메일 가입자는 null.
     * 191 자 = utf8mb4 기준 InnoDB 단일 컬럼 인덱스 상한(767바이트)에 맞춘 관례값.
     */
    @Column(name = "social_id", length = 191)
    private String socialId;

    /**
     * 권한. 토큰 발급 시 이 값을 쓴다. 비어 있으면 {@link #ROLE_USER} 로 채운다.
     *
     * <p>{@code nullable = false} 는 마이그레이션 SQL
     * (backend/mysql/post-start/04_users_social_account_model.sql §A)의
     * {@code role VARCHAR(20) NOT NULL DEFAULT 'ROLE_USER'} 와 정의를 맞추기 위한 것이다.
     * 이게 없으면 dev(ddl-auto=update)는 nullable 컬럼을, prod 는 NOT NULL 컬럼을 갖게 되고
     * Hibernate 의 validate 는 nullability 를 검사하지 않아 그 차이를 끝까지 알려주지 않는다.
     * 값은 {@code @Builder.Default} 와 {@code @PrePersist} 가 함께 보장한다.
     */
    @Builder.Default
    @Column(length = 20, nullable = false)
    private String role = ROLE_USER;

    /**
     * 로그인용 id.
     *
     * <p><b>nullable 이다.</b> 카카오 {@code account_email} 은 선택 동의라서 사용자가 거부하면
     * 이메일이 오지 않는다. 그 계정도 가입에 성공해야 한다(이슈 #7 완료 조건 1).
     * unique 는 유지한다 — MySQL·H2 모두 UNIQUE 인덱스에서 NULL 을 서로 다른 값으로 보므로
     * 이메일 없는 사용자가 여럿이어도 충돌하지 않는다.
     */
    @Column(unique = true, nullable = true)
    private String email;

    /**
     * 로그인용 비밀번호(BCrypt 해시).
     *
     * <p><b>절대 직렬화하지 않는다.</b> 이 엔티티는 {@code UserResponse} 를 거치지 않고 응답에
     * 실리는 경로가 있다 — {@code Schedule.user} 가 그렇다. {@code POST /public/schedules} 의
     * 응답이 {@code Schedule} 엔티티를 통째로 내보내면서 이 해시가 그대로 나가고 있었다(실측 확인).
     * 로그·예외 메시지에서 식별자를 걷어낸 규약(#6)이 응답 본문에서 뚫려 있던 자리다.
     *
     * <p>여기(엔티티 필드)에 붙이는 이유는 소비처가 아니라 원천을 막기 위해서다 — 아홉 번째
     * 컨트롤러가 엔티티를 그대로 반환해도 해시는 나가지 않는다. 역직렬화도 함께 막히지만
     * {@code User} 를 {@code @RequestBody} 로 받는 곳은 없다(확인함). 가입 비밀번호는
     * {@code SignupRequest} 로 들어온다.
     * 잠그는 테스트: ScheduleWriteBoundaryIntegrationTest.
     */
    @com.fasterxml.jackson.annotation.JsonIgnore
    private String password; // 로그인용 비밀번호

    private String travelType;
    private String imageUrl;

    private LocalDateTime createdAt; // 생성일
    private LocalDateTime updatedAt; // 수정일

    // ✅ 나이 구분 (만 14세 이상/미만)
    @Enumerated(EnumType.STRING)
    private AgeGroup ageGroup;    // OVER14 / UNDER14

    // ✅ 동의 플래그
    private Boolean agreeTos;         // 필수
    private Boolean agreePrivacy;     // 필수
    private Boolean agreeMarketing;   // 선택

    // ✅ 동의 버전 및 시각
    private String tosVersion;
    private String privacyVersion;
    private String marketingVersion;
    private LocalDateTime tosAgreedAt;
    private LocalDateTime privacyAgreedAt;
    private LocalDateTime marketingAgreedAt;

//    // 엔티티가 수정되기 전 자동으로 실행
//    @PrePersist // 엔티티가 처음 저장되기 전에 실행
//    public void prePersist() {
//        this.updatedAt = LocalDateTime.now(); // 현재 시간으로 수정일 설정
//    }
    @PrePersist
    public void prePersist() {
        this.createdAt = (this.createdAt == null) ? LocalDateTime.now() : this.createdAt;
        this.updatedAt = LocalDateTime.now();
        // @Builder.Default 는 빌더 경로에서만 적용된다. new User() 로 만든 행도 권한이 비면 안 된다.
        if (this.role == null || this.role.isBlank()) {
            this.role = ROLE_USER;
        }
    }

    @PreUpdate
    public void preUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    // Enum 선언 해놓기 : Gender는 세 값 중 하나만 가질 수 있음
    public enum Gender {
        MALE, // 남성
        FEMALE, // 여성
        OTHER // 기타   
    }

    // [0911 추가]
    public enum AgeGroup { OVER14, UNDER14 }

}
