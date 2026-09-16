package com.heattrip.heat_trip_backend.care.service;

import com.heattrip.heat_trip_backend.care.entity.CareItem;
import com.heattrip.heat_trip_backend.care.repository.CareItemRepository;
import com.heattrip.heat_trip_backend.group.FamilyGroupCreated;
import com.heattrip.heat_trip_backend.group.FamilyMembership;
import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import java.util.List;

/**
 * 그 집이 챙기는 일의 목록 — 이슈 #560.
 *
 * <p>조각 1 은 <b>목록이 생겨나는 자리</b>만 만든다. 고치고 접고 옮기는 API 는 조각 2 다.
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
