package com.heattrip.heat_trip_backend.user.entity;

import jakarta.persistence.*; // JPA 어노테이션 제공 (Entity, Id, Table 등)
import lombok.*;              // 롬복(Lombok) 어노테이션 제공 (자동 코드 생성)
import java.time.LocalDateTime; // 시간 정보 (생성일, 수정일)를 다루는 클래스

// 이 클래스는 DB 테이블과 연결되는 엔티티 클래스

@Entity // JPA가 이 클래스를 엔티티로 인식하도록 하는 어노테이션 => DB 테이블과 매핑됨
@Table(name = "users") // 이 엔티티가 매핑될 테이블 이름 지정
@Getter // Lombok의 @Getter 어노테이션을 사용하여 모든 필드에 대한 getter 메서드를 자동 생성
@Setter // Lombok의 @Setter 어노테이션을 사용하여 모든 필드에 대한 setter 메서드를 자동 생성

@NoArgsConstructor // Lombok : 파라미터가 없는 기본 생성자 자동으로 생성
@AllArgsConstructor // Lombok : 모든 필드를 파라미터로 받는 생성자 자동으로 생성

@Builder // Lombok : 빌더 패턴을 사용하여 객체 생성 시 가독성을 높임
// - 빌더 패턴은 객체 생성 시 가독성을 높이고, 필수/선택 필드를 명확히 구분할 수 있게 해줌
// - 예: User user = User.builder().username("john").email("
public class User {

    @Id // 이 필드가 엔티티의 기본 키임을 나타냄
    @GeneratedValue(strategy = GenerationType.IDENTITY) // 기본 키 생성 전략을 지정 (자동 증가)
    private Long id; // 사용자 ID(PK)

    private String name; // 사용자 이름
    private String nickname; // 사용자 닉네임

    // enum : 제한된 값만 가질 수 있는 데이터 타입
    @Enumerated(EnumType.STRING) // enum 타입을 문자열로 저장
    private Gender gender; 

    private Integer age; // 사용자 나이

    private String username; // 소셜 로그인 식별자 (예: google_123456)

    @Column(unique = true)
    private String email; // 로그인용 id
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
