// src/main/java/com/heattrip/heat_trip_backend/feedback/entity/Feedback.java
package com.heattrip.heat_trip_backend.feedback.entity;

import com.heattrip.heat_trip_backend.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import java.time.LocalDateTime;

/** 사용자 피드백을 저장하는 JPA 엔티티 */
@Entity // JPA가 이 클래스를 테이블로 매핑하도록 표시
@Table(name = "feedback") // 테이블명을 명시(생략 시 클래스명 기반)
@Getter @Setter // 롬복: 모든 필드 getter/setter 생성
@NoArgsConstructor @AllArgsConstructor // 기본/전체 생성자 자동 생성
@Builder // 롬복: 빌더 패턴으로 객체 생성
public class Feedback {

    @Id // PK
    @GeneratedValue(strategy = GenerationType.IDENTITY) // DB의 auto-increment 사용
    private Long id;

    /**
     * 작성자(로그인 사용자면 연결, 비로그인 허용하려면 nullable)
     * FetchType.LAZY: 실제로 user가 필요할 때만 쿼리(지연 로딩)
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id") // FK 컬럼명
    @OnDelete(action = OnDeleteAction.SET_NULL) // 작성자가 삭제돼도 의견은 남게
    private User user; // nullable 허용

    @Lob // 긴 텍스트 저장(내용이 길 수 있으므로)
    private String content;

    // 선택 정보들(카테고리/앱버전/디바이스)
    @Column(length = 50)
    private String category;

    @Column(length = 50)
    private String appVersion;

    @Column(length = 120)
    private String deviceInfo;

    /**
     * 상태 필드 - 문자열로 저장(NEW/IN_PROGRESS/RESOLVED)
     * EnumType.STRING: 숫자 대신 문자열로 저장하여 가독성과 변경 안정성↑
     */
    @Enumerated(EnumType.STRING)
    private Status status;

    public enum Status { NEW, IN_PROGRESS, RESOLVED }

    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    @PrePersist // INSERT 전 자동 호출(생성/수정일 초기화, 상태 기본값)
    void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
        if (this.status == null) this.status = Status.NEW;
    }

    @PreUpdate // UPDATE 전 자동 호출(수정일 갱신)
    void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }
}
