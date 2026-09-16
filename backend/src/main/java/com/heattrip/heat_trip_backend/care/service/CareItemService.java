package com.heattrip.heat_trip_backend.care.service;

import com.heattrip.heat_trip_backend.care.CareTime;
import com.heattrip.heat_trip_backend.care.dto.CareItemRequest;
import com.heattrip.heat_trip_backend.care.dto.CareItemResponse;
import com.heattrip.heat_trip_backend.care.entity.CareIcon;
import com.heattrip.heat_trip_backend.care.entity.CareItem;
import com.heattrip.heat_trip_backend.care.repository.CareItemRepository;
import com.heattrip.heat_trip_backend.dog.DogOwnership;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.group.FamilyGroupCreated;
import com.heattrip.heat_trip_backend.group.FamilyMembership;
import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.web.server.ResponseStatusException;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * 그 집이 챙기는 일의 목록 — 이슈 #560.
 *
 * <h2>두 가지 일을 한다</h2>
 *
 * <ul>
 *   <li><b>목록이 생겨나는 자리</b>(조각 1) — 가족이 생기면 기본 일곱을 심는다. 인가를 안 한다,
 *       사람이 부르는 것이 아니라 사실을 듣는 것이라서.</li>
 *   <li><b>목록을 고치는 자리</b>(조각 2) — 만들고 고치고 접고 옮긴다. 다섯 다 인가로 시작한다.</li>
 * </ul>
 *
 * <p>둘을 한 클래스에 둔 이유는 <b>같은 표의 같은 규약</b>을 쓰기 때문이다 — 접힌 것도 목록에
 * 온다, 기본 일곱도 똑같이 고쳐진다, 순서는 그 집 안에서만 뜻이 있다. 나누면 그 규약이 두
 * 곳에 적힌다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class CareItemService {

    private final CareItemRepository items;

    /**
     * "그 가족의 행" 을 묻는 자리 — {@code group} 모듈의 공개 표면이다.
     *
     * <p>{@code FamilyGroupRepository} 를 직접 들지 않는 이유는 {@code FamilyMembership.groupEntity}
     * 의 javadoc 에 있다 — 모듈 내부를 부르면 경계 빚이 는다.
     */
    private final FamilyMembership family;

    /** "그 집 아이인가" — dog 모듈의 공개 표면(#563). {@code CareService} 가 같은 것을 든다. */
    private final DogOwnership dogs;

    /**
     * 그 집의 항목 전부 — 접힌 것까지, 순서대로.
     *
     * <p><b>인가를 여기서 하지 않는다.</b> 부르는 쪽이 이미 "그 가족의 식구인가" 를 지났다는
     * 전제다({@code FamilyMembership.requireMember}) — {@code DogOwnership.requireInFamilyEntity}
     * 가 같은 규약을 쓴다. 여기서 한 번 더 보면 같은 판정이 두 곳에 생기고, 그때부터 한쪽만
     * 고쳐지는 날을 기다리게 된다.
     */
    @Transactional(readOnly = true)
    public List<CareItem> listOf(long groupId) {
        return items.findOfGroup(groupId);
    }

    // ─────────────────────────── 목록 고치기 (#560 조각 2) ───────────────────────────

    /**
     * 그 집의 목록 — 접힌 것까지, 순서대로. 인가를 지나고 응답 모양으로 바꾼다.
     *
     * @throws ResponseStatusException 403 — 그 가족의 식구가 아니면
     */
    @Transactional(readOnly = true)
    public List<CareItemResponse> itemsOf(long groupId, long actorUserId) {
        family.requireMember(groupId, actorUserId);
        return items.findOfGroup(groupId).stream().map(CareItemResponse::of).toList();
    }

    /**
     * 항목 하나 만들기 — 맨 <b>뒤</b>에 놓인다.
     *
     * <p>앞에 넣지 않는 이유는, 방금 만든 것이 물 · 밥 앞에 끼면 <b>매일 보는 순서가 만들
     * 때마다 흔들리기</b> 때문이다. 자리를 옮기고 싶으면 끌어서 옮긴다.
     *
     * <p>{@code systemType} 을 안 받는다 — 직접 만든 항목은 언제나 비어 있다. 받으면 이미
     * 있는 기본 항목과 같은 종류를 만들어 {@code uq_careitem_system} 에 걸리거나, 걸리지
     * 않는 값이면 옛 기록이 두 칸에서 세어진다.
     *
     * @throws ResponseStatusException 403 — 식구가 아니면. 400 — 이름 · 아이콘 · 아이 · 목표가 규칙 밖이면
     */
    @Transactional
    public CareItemResponse create(long groupId, CareItemRequest request, long actorUserId) {
        family.requireMember(groupId, actorUserId);

        List<CareItem> existing = items.findOfGroup(groupId);
        int last = existing.stream().mapToInt(CareItem::getSortOrder).max().orElse(-1);

        return CareItemResponse.of(items.save(newItemOf(groupId)
                .dog(dogOrNull(groupId, request.dogId()))
                .name(validName(request.name()))
                .icon(CareIcon.of(request.icon()).wire())
                .dailyTarget(validTarget(request.dailyTarget()))
                .sortOrder(last + 1)
                .build()));
    }

    /**
     * 항목 하나 전량 교체 — 이름 · 아이콘 · 아이 · 목표 · 접힘.
     *
     * <p><b>기본 일곱도 똑같이 고쳐진다.</b> "기본은 못 건드림" 을 두지 않는 이유는, 그 순간
     * 투두리스트가 아니라 설정 화면이 되기 때문이다(이슈 본문). {@code systemType} 만 그대로
     * 남아 옛 기록을 계속 센다 — 이름을 {@code 밥} 에서 {@code 아침밥} 으로 바꿔도 어제 기록이
     * 새 이름으로 보이는 것이 그 덕이다.
     *
     * @throws ResponseStatusException 403 — 식구가 아니면. 404 — 그 집 항목이 아니면. 400 — 값이 규칙 밖이면
     */
    @Transactional
    public CareItemResponse replace(long groupId, long itemId, CareItemRequest request,
                                    long actorUserId) {
        family.requireMember(groupId, actorUserId);
        CareItem item = requireOfGroup(groupId, itemId);

        item.edit(
                validName(request.name()),
                CareIcon.of(request.icon()).wire(),
                validTarget(request.dailyTarget()),
                dogOrNull(groupId, request.dogId()),
                // 이미 접혀 있으면 그 시각을 지킨다 — 이름만 고쳤는데 "접은 날" 이 오늘로
                // 바뀌면, 언제부터 안 하고 있었는지가 사라진다.
                Boolean.TRUE.equals(request.archived())
                        ? (item.getArchivedAt() == null ? CareTime.nowUtc() : item.getArchivedAt())
                        : null);
        return CareItemResponse.of(items.save(item));
    }

    /**
     * 항목 접기 — <b>지우는 것이 아니다.</b>
     *
     * <p>행을 남기는 이유는 {@code care_log.care_item_id} 가 이 행을 가리키기 때문이다. 지우면
     * 지난 기록이 이름을 잃는다. 카드에서는 사라지고 고치기 화면에는 "다시 켜기" 로 남는다.
     *
     * <p><b>이미 접힌 것을 또 접어도 조용하다.</b> 같은 요청이 두 번 와도 결과가 같아야 화면이
     * 재시도를 걱정하지 않는다 — 접은 시각도 처음 것을 지킨다.
     *
     * @throws ResponseStatusException 403 — 식구가 아니면. 404 — 그 집 항목이 아니면
     */
    @Transactional
    public void archive(long groupId, long itemId, long actorUserId) {
        family.requireMember(groupId, actorUserId);
        CareItem item = requireOfGroup(groupId, itemId);
        if (item.isArchived()) {
            return;
        }
        item.edit(item.getName(), item.getIcon(), item.getDailyTarget(), item.getDog(),
                CareTime.nowUtc());
        items.save(item);
    }

    /**
     * 목록 순서 바꾸기 — <b>전부를</b> 한 번에 받는다.
     *
     * <p>왜 전부인지는 {@code CareItemOrderRequest} 의 javadoc 에 있다. 여기서는 그 규약을
     * 실제로 잰다 — 빠진 id · 모르는 id · 겹친 id 는 전부 400 이다.
     *
     * @throws ResponseStatusException 403 — 식구가 아니면. 400 — 그 집 항목 전부가 정확히 한 번씩 오지 않으면
     */
    @Transactional
    public void reorder(long groupId, List<Long> itemIds, long actorUserId) {
        family.requireMember(groupId, actorUserId);

        List<CareItem> current = items.findOfGroup(groupId);
        Set<Long> asked = new LinkedHashSet<>(itemIds == null ? List.of() : itemIds);

        if (itemIds == null || asked.size() != itemIds.size()) {
            throw badRequest("같은 항목이 두 번 왔습니다.");
        }
        if (asked.size() != current.size()
                || !asked.containsAll(current.stream().map(CareItem::getId).toList())) {
            // 조용히 뒤에 붙이지 않는다 — CareItemOrderRequest 의 javadoc.
            throw badRequest("목록의 항목 " + current.size() + "개를 모두 보내야 합니다.");
        }

        List<CareItem> reordered = new ArrayList<>(current.size());
        for (Long id : asked) {
            CareItem item = current.stream().filter(c -> c.getId().equals(id)).findFirst()
                    .orElseThrow(() -> badRequest("이 집의 항목이 아닙니다."));
            item.moveTo(reordered.size());
            reordered.add(item);
        }
        items.saveAll(reordered);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * 그 집 항목을 꺼낸다. 아니면 <b>404</b> — 없는 것과 남의 것이 같은 답이다(#209).
     *
     * <p>{@code findById} 뒤에 그룹을 대조하는 이유는, id 만으로 꺼내면 옆집 항목을 고칠 수
     * 있기 때문이다. 인가({@code requireMember})는 <b>요청</b>을 막고 이 대조는 <b>행</b>을
     * 막는다 — 한 사람이 여러 방에 속하는 것이 정상이라 인가만으로는 안 막힌다.
     */
    private CareItem requireOfGroup(long groupId, long itemId) {
        return items.findById(itemId)
                .filter(item -> item.getGroup().getId() == groupId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "그 항목을 찾을 수 없습니다."));
    }

    /**
     * 이 집의 새 항목을 짓기 시작한다 — {@code group} 을 물리는 자리가 여기 하나다.
     *
     * <p>부르는 쪽이 {@code FamilyGroup} 을 직접 들지 않게 하는 것이 요점이다. {@code care} 가
     * {@code group.entity} 를 부르는 것은 이미 진 빚이고({@code ModularityBaselineTest}), 그
     * 빚을 <b>쓰기 경로가 하나 늘 때마다 함께 늘리지 않으려고</b> 한 자리에 모았다.
     */
    private CareItem.CareItemBuilder newItemOf(long groupId) {
        return CareItem.builder()
                .group(family.groupEntity(groupId).orElseThrow(CareItemService::notThisFamily));
    }

    /** 아이를 안 골랐으면 {@code null}, 골랐으면 그 집 아이여야 한다(400). */
    private Dog dogOrNull(long groupId, Long dogId) {
        return dogId == null ? null : dogs.requireInFamilyEntity(groupId, dogId);
    }

    /**
     * 이름은 1~20자. 잘라서 저장하지 않고 거절하는 이유는 {@code CareService.trimmedToNull} 과
     * 같다 — 사용자가 적은 것과 화면에 뜨는 것이 다르면 아무도 그 차이를 설명해 주지 않는다.
     * 메시지에 입력값을 되싣지 않는다(#6).
     */
    private static String validName(String value) {
        String trimmed = value == null ? "" : value.strip();
        if (trimmed.isEmpty()) {
            throw badRequest("이름을 적어 주세요.");
        }
        if (trimmed.length() > CareItem.MAX_NAME_LENGTH) {
            throw badRequest("이름은 " + CareItem.MAX_NAME_LENGTH + "자 이하여야 합니다.");
        }
        return trimmed;
    }

    /**
     * 하루 목표는 1~20 이거나 없음.
     *
     * <p>0 을 막는 이유는 "하루 0번 하는 일" 이 목록에 있을 이유가 없어서다 — 그건 접기다.
     * 위를 막는 이유는 화면이 {@code 1/999} 를 그릴 자리가 없어서다.
     */
    private static Integer validTarget(Integer value) {
        if (value == null) {
            return null;
        }
        if (value < 1 || value > CareItem.MAX_DAILY_TARGET) {
            throw badRequest("하루 목표는 1에서 " + CareItem.MAX_DAILY_TARGET + " 사이여야 합니다.");
        }
        return value;
    }

    private static ResponseStatusException badRequest(String message) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, message);
    }

    private static ResponseStatusException notThisFamily() {
        return new ResponseStatusException(HttpStatus.FORBIDDEN, "이 가족 그룹의 멤버가 아닙니다.");
    }

    /**
     * 가족이 생기면 기본 일곱을 넣는다 — 이슈 #560.
     *
     * <h2>왜 커밋 뒤인가</h2>
     *
     * <p>커밋 전에 받으면 <b>롤백된 가족의 항목만 남는다.</b> {@link FamilyGroupCreated} 의
     * javadoc 이 그 규약이고, {@code push} 가 {@code chat} 을 같은 방식으로 듣는다.
     *
     * <p>{@code AFTER_COMMIT} 은 <b>비동기가 아니다</b> — 같은 스레드에서 돌고 그게 끝나야
     * {@code POST /api/groups} 가 응답한다. 그래서 막 만든 사람의 첫 화면에 이미 들어 있다.
     *
     * <h2>왜 새 트랜잭션인가</h2>
     *
     * <p>바깥 트랜잭션은 이미 커밋됐다. {@code REQUIRES_NEW} 가 없으면 이 저장이 트랜잭션
     * 없이 돌아 {@code TransactionRequiredException} 이 난다.
     *
     * <h2>이미 있으면 안 넣는다</h2>
     *
     * <p>{@code uq_careitem_system} 이 마지막에서 막지만({@code group_id} + {@code system_type}),
     * 여기서 먼저 보는 것은 <b>제약 위반을 정상 경로로 쓰지 않으려는 것</b>이다. 마이그레이션이
     * 이미 채운 그룹에 이 이벤트가 다시 오는 경우(재실행 · 재생성)가 그 자리다.
     */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void seedDefaults(FamilyGroupCreated event) {
        if (!items.findOfGroup(event.groupId()).isEmpty()) {
            return;
        }
        FamilyGroup group = family.groupEntity(event.groupId()).orElse(null);
        if (group == null) {
            // 커밋 뒤에 그룹이 사라졌다. 넣을 곳이 없으니 조용히 지나간다 —
            // 여기서 던지면 이미 성공한 요청이 뒤늦게 500 으로 뒤집힌다.
            log.warn("[케어 항목] 가족 {} 이 없어 기본 항목을 못 넣었다", event.groupId());
            return;
        }
        items.saveAll(CareItem.defaultsFor(group));
    }
}
