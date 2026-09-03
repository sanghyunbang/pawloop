package com.heattrip.heat_trip_backend.user.entity;

import com.heattrip.heat_trip_backend.user.UserTime;

import org.springframework.modulith.NamedInterface;

import jakarta.persistence.*; // JPA 어노테이션 제공 (Entity, Id, Table 등)
import lombok.*;              // 롬복(Lombok) 어노테이션 제공 (자동 코드 생성)
import java.time.LocalDateTime; // 시간 정보 (생성일, 수정일)를 다루는 클래스

// 이 클래스는 DB 테이블과 연결되는 엔티티 클래스

/**
 * 이 모듈의 <b>유일한 공개 표면</b> — {@code user :: entity} (#105 · ADR-0012).
 *
 * <h2>왜 이걸 열었나</h2>
 * <p>{@code user} 는 루트 타입이 0개라 들어오는 참조가 예외 없이 전부 위반이었고, 그중 이 한
 * 타입이 압도적이었다. 실측으로 {@code user} 밖의 파일 34개가 이 타입을 부른다 —
 * {@code bookmark} · {@code care} · {@code schedules} · {@code feedback} · {@code group} ·
 * {@code social} · {@code S3} · {@code chatweb} · {@code OAuth}. 사실상 이 애플리케이션의
 * 공용 어휘다.
 *
 * <h2>{@code RefreshToken} 은 열지 않는다</h2>
 * <p>{@code user.entity} 에는 타입이 둘인데 패키지째 열지 않고 이 타입 하나에만 붙였다.
 * {@code RefreshToken} 은 <b>리프레시 토큰 원장</b>이고 밖에서의 참조가 <b>0건</b>이다.
 * 패키지째 열면 그게 공개 API 가 된다 — 인증 모듈에서 열어 줄 이유가 없다.
 *
 * <h2>이건 빚이다</h2>
 * <p>여는 것과 갚는 것은 다르다. 여기서 여는 것은 <b>"지금 이 참조들은 합법이다"</b> 이지
 * <b>"이대로가 옳다"</b> 가 아니다. 진짜 문제는 <b>경계를 넘는 JPA 연관</b> 이다 — 다른 모듈의
 * 엔티티가 {@code @ManyToOne User} 로 이 타입을 직접 물고 있으면, {@code user} 를 별도
 * 서비스로 떼는 순간 그 연관이 전부 깨진다. 그때는 조회 경로를 다시 짜야 한다.
 *
 * <p><b>갚는 조건.</b> {@code user} 를 실제로 분리하기로 결정하는 날, 또는 그 전에라도 아래
 * 엔티티들이 {@code @ManyToOne User} 를 {@code Long userId} 로 바꿀 때. 그 작업은 이 타입을
 * 여는 것과 별개로 이슈가 잡혀 있다 — 여덟 엔티티를 모듈별로 넷으로 묶었다.
 *
 * <table>
 *   <caption>경계를 넘는 JPA 연관</caption>
 *   <tr><th>이슈</th><th>엔티티</th></tr>
 *   <tr><td>#120</td><td>{@code bookmark/entity/Bookmark.java:26} ·
 *       {@code Collection.java:26} · {@code CollectionItem.java:26}</td></tr>
 *   <tr><td>#121</td><td>{@code care/entity/CareLog.java:146}({@code doneBy}) ·
 *       {@code WalkNote.java:123}({@code updatedBy}) — 둘 다 {@code ON DELETE SET NULL}(#76)</td></tr>
 *   <tr><td>#122</td><td>{@code schedules/entity/Journey.java:29} · {@code Schedule.java:33}</td></tr>
 *   <tr><td>#123</td><td>{@code feedback/entity/Feedback.java:31} — 가장 작다. 방법을 먼저
 *       확인하는 자리로 쓰는 것이 좋다</td></tr>
 * </table>
 *
 * <p>{@code user.repository} · {@code user.dto} · {@code user.service} 는 <b>열지 않았다.</b>
 * 리포지토리를 남이 직접 부르는 것은 공용 어휘가 아니라 그냥 새는 것이고, 건수가 적어 갚을
 * 만하다. 그것들은 위반으로 남아 있다.
 */
@NamedInterface("entity")
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

    /**
     * 이름을 알 수 없을 때 화면에 쓰는 자리. 계약이 {@code ChatMessage.senderName} 에 쓰는 문구와 같다.
     *
     * <p>탈퇴한 계정·닉네임과 이름이 모두 빈 계정이 여기로 온다.
     */
    public static final String UNKNOWN_DISPLAY_NAME = "알 수 없음";

    /**
     * 닉네임의 최대 글자 수 — 이슈 #229.
     *
     * <p><b>컬럼이 정한 수가 아니다.</b> {@code nickname} 은 {@code varchar(255)} 인데 그건
     * 저장 한계이지 제품이 고른 수가 아니다. 앱의 프로필 편집 화면이 이미 20 으로 막고
     * 있어서 그 수를 서버 쪽 정본으로 올린다.
     *
     * <p><b>이 값이 모든 도메인으로 번진다.</b> {@code post.handle}·{@code comment.handle} ·
     * {@code chat_message.sender_name} 이 이것을 스냅샷하고, 가족 멤버 목록과 케어 기록이
     * 이것을 표시한다. #170 에서 {@code post.handle} 이 {@code VARCHAR(50)} 이라 51자
     * 닉네임을 가진 사람의 <b>모든 글쓰기가 영구히 500</b> 이 된 적이 있는데, 그 진짜 원인이
     * 여기 상한이 없다는 것이었다.
     *
     * <p>2026-09-03 이전에는 가입·프로필 수정 어느 쪽에도 {@code @Size} 가 없었고
     * {@code @Valid} 조차 없었다.
     */
    public static final int MAX_NICKNAME_LENGTH = 20;

    /** 이름의 최대 글자 수. 닉네임이 비었을 때의 대체 표시값이라 같은 이유로 막는다(#229). */
    public static final int MAX_NAME_LENGTH = 50;

    /**
     * 공급자가 준 표시 이름을 상한 안으로 자른다 — <b>거절하지 않는다.</b>
     *
     * <p>소셜 로그인은 앱을 안 지나므로 클라이언트 상한이 닿지 않는다. 여기서 400 을 주면
     * <b>이름이 긴 사람은 로그인 자체가 안 된다</b> — 긴 닉네임보다 훨씬 나쁘다. 자른 뒤에는
     * 사용자가 프로필에서 고칠 수 있다.
     *
     * @return {@code null} 이거나 공백뿐이면 {@code null}
     */
    public static String clamp(String value, int max) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        return trimmed.length() <= max ? trimmed : trimmed.substring(0, max);
    }

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
        // UTC 로 눕혀 넣는다 — LocalDateTime.now() 는 JVM 기본 존이라 개발 기계(KST)와
        // 배포 컨테이너(UTC)가 같은 코드로 다른 값을 넣었다. 이유는 UserTime. (#248)
        this.createdAt = (this.createdAt == null) ? UserTime.nowUtc() : this.createdAt;
        this.updatedAt = UserTime.nowUtc();
        // @Builder.Default 는 빌더 경로에서만 적용된다. new User() 로 만든 행도 권한이 비면 안 된다.
        if (this.role == null || this.role.isBlank()) {
            this.role = ROLE_USER;
        }
    }

    @PreUpdate
    public void preUpdate() {
        this.updatedAt = UserTime.nowUtc();
    }

    /**
     * 만 14세 미만이라고 <b>선언한</b> 계정인가. (이슈 #82)
     *
     * <h2>왜 {@code getAgeGroup() == UNDER14} 를 밖에서 안 쓰게 하는가</h2>
     * <p>{@link AgeGroup} 은 <b>중첩 타입</b>이라 {@code User} 가 공개 표면이어도 그 표면을
     * 물려받지 않는다 — 밖에서 그것을 부르면 모듈 경계 위반이다({@code ModularityBaselineTest}
     * 가 {@code User$Gender}·{@code User$UserBuilder} 를 여전히 위반으로 세고 있는 것과 같다).
     * 판정을 여기 두면 밖으로 나가는 것이 {@code boolean} 하나다.
     *
     * <p>어휘가 여기 있어야 하는 이유이기도 하다. "만 14세 미만" 이 무엇인지는 {@code user}
     * 가 정한다 — 등급이 셋이 되는 날 고칠 자리가 한 곳이어야 한다.
     *
     * <h2>{@code null} 은 미성년이 아니다</h2>
     * <p>{@code age_group} 은 {@code DEFAULT NULL} 이고 소셜 로그인으로 들어온 예전 계정들이
     * 비어 있다. 모르는 것을 미성년으로 다루면 <b>그 계정들이 오늘부터 기능을 잃는다.</b>
     * 나이대를 채우게 하는 것은 가입·프로필 쪽 일이다. <b>판단이지 누락이 아니다.</b>
     */
    public boolean isUnder14() {
        return ageGroup == AgeGroup.UNDER14;
    }

    /**
     * 화면에 쓸 이름 — 닉네임 · 이름 · {@link #UNKNOWN_DISPLAY_NAME} 순서다.
     *
     * <p>이 규칙이 <b>여기 한 곳</b>에 있는 이유: 가족 멤버 목록({@code GroupMemberResponse.nickname})
     * 과 케어 기록의 수행자({@code CareLogResponse.doneBy.nickname}) 가 같은 사람을 가리키는데
     * 규칙이 갈리면 같은 화면 안에서 한 사람이 두 이름으로 보인다. 소셜 가입 경로는 닉네임을
     * 설정하지 않을 수 있어서(#7) 이 폴백이 실제로 자주 발동한다.
     */
    public String displayName() {
        if (nickname != null && !nickname.isBlank()) {
            return nickname;
        }
        if (name != null && !name.isBlank()) {
            return name;
        }
        return UNKNOWN_DISPLAY_NAME;
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
