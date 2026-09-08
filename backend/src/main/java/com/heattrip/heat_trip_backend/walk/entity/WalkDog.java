package com.heattrip.heat_trip_backend.walk.entity;

import com.heattrip.heat_trip_backend.dog.entity.Dog;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ForeignKey;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.util.Objects;

/**
 * 한 번의 산책에 함께 나간 아이 하나 — 이슈 #343, 문서는 {@code docs/03-database/schema.md}.
 *
 * <h2>왜 이 표가 필요했나</h2>
 * <p>{@code walk} 는 아이 <b>하나</b>에 묶여 있었다. 두 마리를 함께 데리고 나가면 한 마리
 * 것으로 저장되거나 같은 산책을 두 번 적어야 했다. 프로필은 "우리 아이들" 을 여러 마리
 * 받는데 산책만 한 마리였다.
 *
 * <h2>{@code @ManyToMany} 가 아니라 표를 하나 만든 이유</h2>
 * <p>이 저장소에는 {@code @ManyToMany} 가 하나도 없다. 그리고 여기서는 <b>양쪽 FK 가 모두
 * {@code ON DELETE CASCADE}</b> 여야 하는데, {@code @ManyToMany} 의 {@code @JoinTable} 에
 * Hibernate 의 {@code @OnDelete} 를 붙이면 <b>소유자 쪽 한 짝에만</b> 붙는다. 그러면
 * {@code mysql/init/01_schema.sql}(엔티티에서 재생성한다)이 만드는 새 DB 와 마이그레이션이
 * 고친 기존 DB 가 서로 다른 규칙을 갖게 된다 — 이 저장소가 계속 막아 온 종류의 어긋남이다.
 *
 * <h2>지우기는 둘 다 CASCADE</h2>
 * <p>이 표에는 <b>사실이 없다.</b> "이 산책에 이 아이가 있었다" 라는 이음매뿐이라, 산책이나
 * 아이가 사라지면 남을 이유가 없다. {@code care_log} 가 {@code SET NULL} 인 것과 다른
 * 이유가 여기 있다 — 거기는 "누가 밥을 줬다" 라는 <b>사실</b>이라 사람이 사라져도 남는다.
 *
 * <p>아이는 소프트 삭제다(#156, {@code dog.deleted_at}). 행이 실제로 지워지는 것은 계정
 * 탈퇴 같은 경로뿐이라 CASCADE 가 도는 일은 드물다.
 *
 * <h2>PK 는 {@code (dog_id, walk_id)} 순서다</h2>
 * <p>Hibernate 가 정하는 순서이고({@code mysql/init/01_schema.sql} 이 그것에서 재생성된다),
 * 마침 <b>바라던 순서</b>다 — 이 표에 가장 자주 오는 질문이 "이 아이의 산책" 이라
 * {@code dog_id} 가 앞이어야 인덱스를 탄다. 반대 방향("이 산책의 아이들")은 MySQL 이
 * {@code fk_walkdog_walk} 에 자동으로 만드는 인덱스가 받는다.
 *
 * <p>그래서 {@code (dog_id, walk_id)} 짜리 보조 인덱스를 따로 두지 않는다 — PK 와 완전히
 * 겹친다. 33_walk_dog.sql 도 같은 모양으로 만든다.
 *
 * <h2>대표 아이도 여기 한 줄 들어간다</h2>
 * <p>{@code walk.dog_id} 는 남는다(멱등키 {@code uq_walk_client} 의 앞자리이고 소유권이 그
 * 연관을 탄다). 그 대표 아이도 이 표에 <b>한 줄 들어간다</b> — 안 넣으면 "아이별 통계" 가
 * 두 곳을 합쳐 봐야 하고, 그 합치기를 잊는 화면이 언젠가 생긴다.
 */
@Entity
@Table(name = "walk_dog")
@IdClass(WalkDog.Key.class)
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
public class WalkDog {

    @Id
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "walk_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_walkdog_walk"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Walk walk;

    @Id
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "dog_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_walkdog_dog"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Dog dog;

    static WalkDog of(Walk walk, Dog dog) {
        return new WalkDog(walk, dog);
    }

    /**
     * 복합 키 {@code (walk_id, dog_id)}. 필드 이름은 {@link WalkDog} 의 연관 이름과 같아야
     * 하고, 타입은 그 연관이 가리키는 엔티티의 <b>id 타입</b>이다.
     */
    @NoArgsConstructor
    @AllArgsConstructor
    @Getter
    public static class Key implements Serializable {
        private Long walk;
        private Long dog;

        @Override
        public boolean equals(Object o) {
            if (this == o) {
                return true;
            }
            if (!(o instanceof Key other)) {
                return false;
            }
            return Objects.equals(walk, other.walk) && Objects.equals(dog, other.dog);
        }

        @Override
        public int hashCode() {
            return Objects.hash(walk, dog);
        }
    }
}
