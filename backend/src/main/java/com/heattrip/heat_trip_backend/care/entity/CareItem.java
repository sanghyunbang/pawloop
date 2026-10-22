package com.heattrip.heat_trip_backend.care.entity;

import com.heattrip.heat_trip_backend.care.CareTime;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;

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

import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 그 집이 챙기는 일 하나 — 이슈 #560. "오늘의 케어" 카드의 <b>칸 하나</b>다.
 *
 * <h2>왜 표가 따로 필요한가</h2>
 *
 * <p>요지는 <b>"투두리스트처럼 커스터마이징"</b> 이었다. 정해진 일곱 중에 켜고 끄는
 * 것이 아니라 <b>직접 만들고 이름 붙이고 지우고 순서를 바꾸는 것</b>이다.
 *
 * <p>그런데 {@code care_log.type} 은 <b>일곱 개짜리 닫힌 목록</b>이다 — 앱 · 계약 · DB 가 같은
 * 문자열을 쓰고 {@code ck_carelog_type} 이 마지막에서 막는다. "양치" 를 만들면 <b>넣을 값이
 * 없다.</b> 종류를 늘리는 방식으로는 담을 수 없다 — 배포 없이는 한 글자도 못 늘린다.
 *
 * <h2>기존 기록을 한 행도 안 건드린다</h2>
 *
 * <p>{@link #systemType} 이 이 표의 핵심이다. 기본 일곱은 이 값을 들고, 직접 만든 것은
 * {@code null} 이다. 읽을 때 항목마다 오늘 몇 번인지를 이렇게 센다.
 *
 * <ul>
 *   <li>{@code systemType} 이 있으면 → {@code care_log.type = systemType} 으로</li>
 *   <li>없으면 → {@code care_log.care_item_id = id} 로</li>
 * </ul>
 *
 * <p>그래서 산책 트래킹 화면이 {@code type='walk'} 로 남기는 줄도, 배변 · 마킹도 그대로
 * 살아 있다. 옛 행에 {@code care_item_id} 를 채워 넣는 UPDATE 가 <b>필요 없다.</b>
 *
 * <h2>이름을 바꿔도 기록은 안 바뀐다</h2>
 *
 * <p>{@code care_log} 는 이름을 저장하지 않는다. {@code 밥} → {@code 아침밥} 으로 고치면
 * <b>옛 기록도 새 이름으로 보인다.</b> 같은 일이니 그게 맞다 — 이름은 그 일을 가리키는
 * 이름표이지 기록의 일부가 아니다.
 *
 * <h2>지우기는 "접기" 다</h2>
 *
 * <p>{@link #archivedAt} 을 찍는다. 카드에서 사라지고 기록은 남는다. <b>산책처럼 다른 화면이
 * 자동으로 쓰는 항목은 접어도 기록이 계속 쌓인다</b> — 카드에 안 보일 뿐이라, 나중에 다시
 * 켜면 그동안의 기록이 그대로 있다. 행을 지우면 {@code care_item_id} 를 든 옛 기록이 갈 곳을
 * 잃는다.
 *
 * <h2>기본 일곱도 그냥 항목이다</h2>
 *
 * <p>가족을 만들 때 일곱 행이 들어간다({@link #defaultsFor}). 그 뒤로는 기본이든 직접 만든
 * 것이든 <b>똑같이 고치고 접고 옮길 수 있다.</b> "기본은 못 건드림" 을 두지 않는 이유는, 그
 * 순간 투두리스트가 아니라 설정 화면이 되기 때문이다.
 *
 * <h2>목록은 집에 한 벌, 항목마다 아이</h2>
 *
 * <p>{@link #dog} 를 비우면 모든 아이에게 뜬다. 물 · 밥 · 산책이 그렇고,
 * {@code 심장사상충 약} 처럼 한 아이에게만 하는 일은 그 아이를 고른다.
 *
 * <p>목록을 아이마다 한 벌씩 두지 않는 이유는, 두 마리 집이 물 · 밥 · 산책을 <b>두 번
 * 적어야</b> 하기 때문이다.
 */
@Entity
@Table(
        name = "care_item",
        indexes = {
                // 카드가 이 인덱스 하나로 "그 집의 안 접힌 항목을 순서대로" 를 훑는다.
                @Index(name = "idx_careitem_group", columnList = "group_id, sort_order"),
                // 아이를 지우면 SET NULL 이 훑는 자리. 없으면 dog 삭제가 이 표 전체 스캔이다.
                @Index(name = "idx_careitem_dog", columnList = "dog_id")
        },
        uniqueConstraints = @jakarta.persistence.UniqueConstraint(
                name = "uq_careitem_system", columnNames = {"group_id", "system_type"}))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class CareItem {

    /** 이름 길이 상한. 칸 폭이 390dp 에서 73dp 라 그보다 길면 어차피 잘린다. */
    public static final int MAX_NAME_LENGTH = 20;

    /** 아이콘 키 길이 상한. 고르는 목록의 값이라 짧다. */
    public static final int MAX_ICON_LENGTH = 20;

    /**
     * 하루 목표 횟수의 상한. DB 제약이 아니라 <b>화면이 그릴 수 있는 폭</b>에서 나온 수다 —
     * 칸에 {@code 1/999} 를 놓을 자리가 없다(#561 이 칸 크기를 잠갔다).
     */
    public static final int MAX_DAILY_TARGET = 20;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 이 목록을 가진 집. <b>NOT NULL 이다</b> — 목록은 집의 것이고, 집 없이 존재할 이유가 없다.
     *
     * <p>{@code ON DELETE CASCADE} 다. {@code care_log.group_id} 가 SET NULL 인 것과 다르다 —
     * 거기는 <b>일어난 사실</b>이라 가족을 해산해도 "내가 밥을 줬다" 가 남아야 하지만, 여기는
     * <b>앞으로 할 일의 목록</b>이라 그 집이 없어지면 남길 것이 없다.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "group_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_careitem_group"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private FamilyGroup group;

    /**
     * 어느 아이에게 하는 일인가. <b>비우면 모든 아이</b>다(#563 뒤).
     *
     * <p>{@code ON DELETE SET NULL} 이다. 아이를 보내도 항목은 남는다 — 같은 이름의 일을 다른
     * 아이에게 계속 할 수 있고, 그때 사용자가 다시 고르면 된다. CASCADE 로 지우면 아이 한
     * 마리를 보낸 것이 <b>집의 할 일 목록을 지우는 일</b>이 된다.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "dog_id",
            foreignKey = @ForeignKey(name = "fk_careitem_dog"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private Dog dog;

    /** 사용자가 적는 이름. {@code 밥} · {@code 양치} · {@code 심장사상충 약}. */
    @Column(nullable = false, length = MAX_NAME_LENGTH)
    private String name;

    /**
     * 아이콘 키. <b>고르는 목록의 값</b>이고 이모지 자유 입력이 아니다.
     *
     * <p>이모지는 기기마다 다르게 그려지고, 흰 바탕 · 코랄 하나로 맞춰 둔 화면에 색이 섞인다.
     */
    @Column(nullable = false, length = MAX_ICON_LENGTH)
    private String icon;

    /**
     * 기본 일곱이면 그 종류, 직접 만든 것이면 {@code null}.
     *
     * <p><b>한 집에 같은 종류는 하나뿐이다</b>({@code uq_careitem_system}). MySQL 의 유니크는
     * {@code NULL} 을 서로 다른 값으로 보므로 <b>직접 만든 항목은 몇 개든 된다</b> — 막는
     * 것은 "물이 두 칸" 뿐이고, 그건 접었다 다시 켜는 것으로 될 일이다. 기본 항목을 두 번
     * 넣는 사고(이벤트 재수신 · 마이그레이션 재실행)도 이 제약이 마지막에서 막는다.
     *
     * <p><b>이 필드 하나가 옛 기록을 살린다.</b> 클래스 javadoc 의 "기존 기록을 한 행도 안
     * 건드린다" 절이 그 이야기다.
     */
    @Convert(converter = CareType.Codec.class)
    @Column(name = "system_type", length = 10)
    private CareType systemType;

    /**
     * 하루 몇 번(선택). 비우면 횟수만 세고, 적으면 화면이 {@code 1/2} 로 그린다.
     *
     * <p>목표를 <b>안 채워도 아무 말도 안 한다.</b> 이 카드는 누락을 보이게 하려는 것이지
     * 혼내려는 것이 아니다({@code WalkGoalRow} 가 "0일" 을 안 적는 것과 같은 판단).
     *
     * <h2>그리고 <b>주기 칸이 없는 것은 결정이다</b>(2026-09-16)</h2>
     *
     * <p>이 카드는 <b>매일 반복되는 돌봄</b>이다. 한 번 하고 끝나는 일(중성화)과 달마다 하는
     * 일(심장사상충)은 <b>일정 탭</b>이 맡는다 — {@code Schedule} 이 이미 반복 규칙을,
     * {@code ScheduleException} 이 하루짜리 예외를 들고 있고, 일정을 완료하면 케어 기록이
     * 남는 경로도 이미 있다({@code CareService.recordLinked}). 여기에 주기를 또 두면
     * "반복" 의 정의가 두 곳에 생긴다.
     *
     * <p>하루에 여러 번을 맡는 것이 이 칸이다.
     */
    @Column(name = "daily_target")
    private Integer dailyTarget;

    /** 카드에 놓이는 순서. 같은 집 안에서만 뜻이 있다. */
    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    /**
     * 접은 시각. <b>지우는 대신 이걸 찍는다</b> — 클래스 javadoc 의 "지우기는 접기다" 절.
     */
    @Column(name = "archived_at")
    private LocalDateTime archivedAt;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /**
     * 표에 담기는 값은 <b>UTC 로 눕힌다</b>({@code CareTime.nowUtc}) — {@code CareLog} 와 같다.
     *
     * <p>{@code LocalDateTime.now()} 는 JVM 기본 존을 읽는다. 개발 기계(KST)와 서버(UTC)가
     * 서로 다른 값을 넣게 되고, 그 차이는 <b>아홉 시간</b>이라 하루 경계를 넘긴다.
     */
    @PrePersist
    void stampCreatedAt() {
        if (createdAt == null) {
            createdAt = CareTime.nowUtc();
        }
    }

    /** 접혔나. 접힌 항목은 카드에 안 그려지고 기록은 그대로 쌓인다. */
    public boolean isArchived() {
        return archivedAt != null;
    }

    /**
     * 고칠 수 있는 것 <b>전부</b>를 한 번에 바꾼다 — 계약의 {@code PUT} 이 여기로 온다.
     *
     * <h2>왜 필드별 메서드가 아니라 하나인가</h2>
     *
     * <p>{@code rename} · {@code changeIcon} 처럼 쪼개면 <b>필드를 하나 더할 때 적어야 할
     * 자리가 늘고</b>, 그중 하나를 빠뜨린 날 화면에는 있는데 저장은 안 되는 값이 생긴다 —
     * {@code WalkSummary.withDistance} 가 정확히 그렇게 새 필드를 떨어뜨렸다. 여기 하나면
     * 필드를 더할 때 컴파일러가 이 자리를 가리킨다.
     *
     * <p><b>{@code systemType} · {@code sortOrder} 는 안 바뀐다.</b> 종류는 "이 항목이 옛
     * 기록을 어떻게 세는가" 라서 바뀌면 지난 기록이 통째로 다른 칸으로 옮겨 간다. 순서는
     * 목록 전체를 한 번에 정하는 것이라 {@link #moveTo} 가 따로 맡는다.
     *
     * @param archivedAt 접은 시각, 다시 켜면 {@code null}. 시각을 <b>받는</b> 이유는 엔티티가
     *                   시계를 들면 테스트가 그 시계를 못 바꾸기 때문이다
     */
    public void edit(String name, String icon, Integer dailyTarget, Dog dog,
                     LocalDateTime archivedAt) {
        this.name = name;
        this.icon = icon;
        this.dailyTarget = dailyTarget;
        this.dog = dog;
        this.archivedAt = archivedAt;
    }

    /** 카드에서의 자리. 목록 전체를 한 번에 정하는 {@code PUT /care-items/order} 만 부른다. */
    public void moveTo(int sortOrder) {
        this.sortOrder = sortOrder;
    }

    /**
     * 가족을 만들 때 넣는 기본 일곱.
     *
     * <p>순서 · 아이콘은 지금 카드가 그리는 것과 같다({@code kCareCardColumns}) — 처음 여는
     * 사람에게 <b>화면이 안 바뀐 것처럼</b> 보여야 한다. 그 뒤로는 사용자가 고친다.
     *
     * <p>아이를 안 고른다({@code dog} 가 {@code null}) — 물 · 밥 · 산책은 모든 아이에게 하는
     * 일이다. 한 아이에게만 하는 일은 사용자가 직접 만들면서 고른다.
     */
    public static List<CareItem> defaultsFor(FamilyGroup group) {
        CareType[] types = {
                CareType.WATER, CareType.MEAL, CareType.WALK, CareType.MED,
                CareType.VET, CareType.POOP, CareType.PEE,
        };
        String[] names = {"물", "밥", "산책", "투약", "병원", "배변", "마킹"};

        List<CareItem> items = new java.util.ArrayList<>(types.length);
        for (int i = 0; i < types.length; i++) {
            items.add(CareItem.builder()
                    .group(group)
                    .name(names[i])
                    .icon(types[i].wire())
                    .systemType(types[i])
                    .sortOrder(i)
                    .build());
        }
        return items;
    }
}
