package com.heattrip.heat_trip_backend.dog.entity;

import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ForeignKey;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import org.hibernate.annotations.Check;
import org.hibernate.annotations.ColumnDefault;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;
import org.springframework.modulith.NamedInterface;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * 반려동물 프로필 — 이슈 #145, 문서는 {@code docs/03-database/schema.md §3}.
 *
 * <h2>이 표가 없어서 막혀 있던 것들</h2>
 * <p>계약의 {@code WalkInput.dogId} 가 <b>필수</b>라 이 표 없이는 산책을 저장할 수 없었다.
 * {@code care_log.dog_id} 도 "표가 생기는 날 FK 를 건다" 는 상태로 컬럼만 있었다 — FK 는
 * #154 에서 걸었고({@code ON DELETE SET NULL}) 값은 아직 항상 {@code null} 이다({@code CareLog} javadoc).
 *
 * <h2>표 이름이 {@code dog} 인데 고양이도 들어온다</h2>
 * <p>{@link PetSpecies} 참조. 이름을 옮기지 않은 이유가 거기 적혀 있다.
 *
 * <h2>{@code @NamedInterface} 를 붙인 이유</h2>
 * <p>{@code walk.entity.Walk} 가 {@code @ManyToOne Dog} 를 <b>들어야</b> Hibernate 가
 * {@code fk_walk_dog} 를 만든다. 스칼라 {@code Long dogId} 로 두면 {@code 01_schema.sql} 을
 * 재생성할 때 <b>FK 가 조용히 사라진다</b> — 그 파일은 살아 있는 DB 에서
 * {@code SHOW CREATE TABLE} 로 뽑은 것이라 엔티티가 만들지 않은 제약은 담기지 않는다.
 *
 * <p>그런데 모듈 밖에서 이 타입을 참조하는 것은 기본적으로 위반이다. {@code user.entity.User}
 * 가 같은 처지에서 {@code @NamedInterface("entity")} 로 열려 있고(#105), 여기도 <b>같은
 * 처리</b>다. 애너테이션은 <b>패키지가 아니라 타입</b>에 붙는다.
 *
 * <h2>탈퇴하면 함께 사라진다</h2>
 * <p>{@code ON DELETE CASCADE} 다({@code schema.md §3} 그대로). {@code UserService.deleteMe}
 * 가 {@code users} 행을 <b>물리 삭제</b>하기 때문이다 — {@code RESTRICT} 로 두면 반려동물을
 * 한 번이라도 등록한 사람은 <b>영구히 탈퇴 불가</b>가 된다(MySQL 1451).
 *
 * <h2>삭제는 소프트 삭제다 — {@code deleted_at} (#156)</h2>
 * <p>{@code walk.fk_walk_dog} 도 {@code CASCADE} 다. 그래서 이 행을 물리 삭제하면
 * <b>그 반려동물의 산책 이력 전부가 조용히 함께 사라진다.</b> 되돌릴 수 없고, 사용자는
 * "프로필만 지웠다" 고 생각한다. FK 를 {@code RESTRICT} 로 바꾸는 것은 답이 아니다 — 위의
 * 탈퇴 문제가 되돌아온다. 안전은 FK 가 아니라 {@link #deletedAt} 으로 산다.
 *
 * <p>{@code DELETE /api/dogs/{dogId}} 는 그 값을 찍고 행을 남긴다. <b>모든 조회가
 * {@code deleted_at is null} 을 건다</b>({@code DogRepository} 의 세 쿼리 전부) — 하나만
 * 빠져도 지운 아이가 어딘가에서 되살아난다. 산책 목록·통계는 이 컬럼을 보지 않는다 —
 * 그 아이와 걸은 거리는 걸은 것이다("계속 센다", #156 4번). {@code ?dogId=} 로 그 아이를
 * 지목하면 404 다 — 지운 아이는 어느 조회에도 없다.
 */
@Entity
@Table(
        name = "dog",
        indexes = @Index(name = "idx_dog_user", columnList = "user_id"))
// DB 가 마지막 방어선이다 (📌 #86 원칙 5). PetSpecies.of / DogSize.of 가 뚫리거나 누가 손으로
// INSERT 해도 계약 밖의 값은 들어가지 못한다.
//
// 둘을 하나로 합치지 않는 이유: 합치면 Hibernate 가 이름을 dog_chk_1 로 만들고, 그러면
// 마이그레이션의 사후 검증이 **어느 쪽이 빠졌는지** 말해 주지 못한다. ck_carelog_type 과
// 같은 방식으로 이름을 붙인다.
@Check(name = "ck_dog_species", constraints = "species in ('dog','cat','other')")
@Check(name = "ck_dog_size", constraints = "size in ('small','medium','large')")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
@NamedInterface("entity")
public class Dog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 주인. <b>토큰의 사용자</b>이지 요청 본문의 값이 아니다 — 본문으로 받으면 남의 계정에
     * 반려동물을 꽂을 수 있다.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_dog_user"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private User user;

    @Column(name = "name", nullable = false, length = 50)
    private String name;

    /** 종. 값을 안 보내면 {@code dog} 다 — 이 컬럼이 없던 때 만들어진 앱과 맞춘다. */
    @Convert(converter = PetSpecies.Codec.class)
    @Column(name = "species", nullable = false, length = 10)
    @ColumnDefault("'dog'")
    @Builder.Default
    private PetSpecies species = PetSpecies.DEFAULT;

    /** 품종. 모르면 비운다 — 유기·믹스가 흔해서 필수로 두면 거짓을 적게 만든다. */
    @Column(name = "breed", length = 50)
    private String breed;

    @Convert(converter = DogSize.Codec.class)
    @Column(name = "size", nullable = false, length = 10)
    @ColumnDefault("'small'")
    @Builder.Default
    private DogSize size = DogSize.SMALL;

    /**
     * 생일.
     *
     * <p>나이를 개월 수로 저장하지 않는 이유는 <b>저장하는 순간 낡기 때문</b>이다. 앱은
     * 개월로 보여 주지만 정본은 생일이고, 개월은 응답에서 파생한다({@code ageMonths}).
     */
    @Column(name = "birth")
    private LocalDate birth;

    @Column(name = "neutered", nullable = false)
    @ColumnDefault("false")
    @Builder.Default
    private boolean neutered = false;

    /**
     * 아바타.
     *
     * <p><b>#145 는 업로드를 구현하지 않는다.</b> 컬럼만 두는 이유는 나중에 넣으면 운영
     * 데이터 위의 {@code ALTER} 가 되기 때문이고, {@code care_log.dog_id} 를 미리 넣어 둔
     * 것과 같은 판단이다. 값은 항상 {@code null} 이다.
     *
     * <p>넣는 날 저장할 것은 <b>S3 objectKey</b> 이지 완성된 URL 이 아니다 — URL 을 박으면
     * 버킷·CDN 을 못 바꾼다({@code docs/02-architecture/backend/dogs.md} §6.5).
     */
    @Column(name = "avatar", length = 255)
    private String avatar;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    /**
     * 소프트 삭제 시각(<b>UTC</b>). {@code null} 이면 살아 있다 — 클래스 javadoc 의 삭제 절.
     * {@code DogService.delete} 가 서비스 {@code Clock} 으로 찍는다.
     */
    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }

    /**
     * 소프트 삭제. 두 번째 호출은 첫 시각을 지킨다 — 부르는 쪽은 그 전에 이미 404 를 냈어야
     * 한다({@code findMineById} 가 지운 행을 안 돌려준다).
     */
    public void markDeleted(LocalDateTime nowUtc) {
        if (deletedAt == null) {
            deletedAt = nowUtc;
        }
    }

    /** 이 반려동물의 주인이 그 사용자인가. 소유권 판정의 유일한 자리다. */
    public boolean isOwnedBy(Long userId) {
        return userId != null && user != null && userId.equals(user.getId());
    }

    /** 부분 수정이 아니다 — 계약에 {@code PATCH} 가 있지만 #145 는 구현하지 않는다. */
    public void rename(String name) {
        this.name = name;
    }
}
