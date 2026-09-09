package com.heattrip.heat_trip_backend.crew.entity;

import com.heattrip.heat_trip_backend.crew.CrewTime;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

import org.hibernate.annotations.Check;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 동네 반려인 모임 하나 — 이슈 #417. 문서는 {@code docs/03-database/schema.md}.
 *
 * <h2>멤버십이 여기 없다</h2>
 * <p>{@code crew_member} 표를 안 만든다. 크루의 멤버는 <b>그 크루 방의 멤버</b>이고,
 * 그것은 {@code chat_room_member} 다 — ADR-0011 이 "채팅은 가족 그룹 종속이 아니라 범용
 * 다중 방" 이라고 정하면서 {@code chat_room.origin_kind}/{@code origin_ref} 를 열어 뒀고,
 * 그 컬럼 주석이 이미 <b>"가족방도 산책 크루 방도 같은 표에 산다"</b> 고 적고 있다.
 *
 * <p>표를 따로 만들면 멤버십이 <b>두 곳</b>에 생긴다. 그러면 "크루는 나갔는데 방에는 남아
 * 있는" 계정이 언젠가 만들어지고, 그 사람은 크루 화면에서 안 보이는 채로 대화를 읽는다.
 * {@code family_group} 이 같은 이유로 사용자 컬럼을 안 갖는다.
 *
 * <h2>동네는 행정동 코드다 — 좌표가 아니다</h2>
 * <p>A안(#235)에서 좌표는 기기를 안 떠난다. {@code neighborhood_code} 는 <b>사용자가 스스로
 * 고른 값</b>(#342)이라 위치정보가 아니고, 찾기는 앞 다섯 자리(시군구)로 한다.
 *
 * <h2>정원은 방이 아니라 여기 있다</h2>
 * <p>{@code chat_room} 의 정원은 {@code ChatLimits} 가 정하는 <b>서비스 전체의 상한</b>이고,
 * 크루의 정원은 <b>방장이 정하는 값</b>이다. 둘은 뜻이 다르다 — 20명짜리 모임을 만든 사람이
 * 21번째를 받고 싶지 않은 것은 서비스 정책이 아니라 그 모임의 규칙이다.
 */
@Entity
@Table(
        name = "crew",
        indexes = {
                // "우리 동네 공개 크루" — 이 표에 오는 유일한 목록 질문이다. 시군구 앞자리로
                // LIKE 를 거는 것이 이 인덱스를 탄다(users.neighborhood 가 같은 방식이다).
                @Index(name = "idx_crew_public", columnList = "visibility, neighborhood_code")
        })
@Check(name = "ck_crew_visibility", constraints = "visibility in ('invite','public')")
@Check(name = "ck_crew_capacity", constraints = "capacity between 2 and 100")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class Crew {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "name", nullable = false, length = 30)
    private String name;

    /** 한 줄 소개. 없어도 된다 — 이름만으로 충분한 모임이 있다. */
    @Column(name = "intro", length = 200)
    private String intro;

    /**
     * 행정동 코드 열 자리(#342). <b>좌표가 아니다</b> — 클래스 javadoc 참조.
     *
     * <p>{@code null} 일 수 있다 — 동네를 안 고른 사람이 만든 크루다. 그때 그 크루는
     * 우리 동네 목록에 안 뜨고 코드로만 들어온다.
     */
    @Column(name = "neighborhood_code", length = 10)
    private String neighborhoodCode;

    @Convert(converter = CrewVisibility.Codec.class)
    @Column(name = "visibility", nullable = false, length = 10)
    private CrewVisibility visibility;

    /** 방장이 정한 정원. 클래스 javadoc 참조. */
    @Column(name = "capacity", nullable = false)
    private Integer capacity;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    /** 크루의 기본 정원. 동네 모임이 이 정도를 넘으면 이름을 아는 사이가 아니게 된다. */
    public static final int DEFAULT_CAPACITY = 20;

    public static final int MIN_CAPACITY = 2;

    /** 상한. {@code chat_room} 의 서비스 정원과 별개다 — 클래스 javadoc 참조. */
    public static final int MAX_CAPACITY = 100;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = CrewTime.nowUtc();
        }
        if (visibility == null) {
            visibility = CrewVisibility.INVITE;
        }
        if (capacity == null) {
            capacity = DEFAULT_CAPACITY;
        }
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = CrewTime.nowUtc();
    }

    /**
     * 방장이 고친다. <b>이름은 방 이름이기도 하다</b> — 부르는 쪽이 방도 함께 고친다.
     *
     * <p>정원을 <b>지금 인원보다 작게</b> 줄이는 것은 막지 않는다. 이미 든 사람을 밀어낼
     * 수 없고, 줄인 값은 "더 안 받는다" 는 뜻으로 그대로 성립한다.
     */
    public void edit(String name, String intro, String neighborhoodCode,
                     CrewVisibility visibility, int capacity) {
        this.name = name;
        this.intro = intro;
        this.neighborhoodCode = neighborhoodCode;
        this.visibility = visibility;
        this.capacity = capacity;
    }
}
