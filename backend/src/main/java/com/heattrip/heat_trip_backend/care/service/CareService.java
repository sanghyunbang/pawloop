package com.heattrip.heat_trip_backend.care.service;

import com.heattrip.heat_trip_backend.care.dto.CareLogRequest;
import com.heattrip.heat_trip_backend.care.dto.CareLogResponse;
import com.heattrip.heat_trip_backend.care.dto.WalkNoteResponse;
import com.heattrip.heat_trip_backend.care.entity.CareItem;
import com.heattrip.heat_trip_backend.care.entity.CareLog;
import com.heattrip.heat_trip_backend.care.entity.CareType;
import com.heattrip.heat_trip_backend.dog.DogOwnership;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.care.entity.WalkNote;
import com.heattrip.heat_trip_backend.care.repository.CareLogRepository;
import com.heattrip.heat_trip_backend.care.repository.WalkNoteRepository;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;
import com.heattrip.heat_trip_backend.group.repository.FamilyGroupRepository;
import com.heattrip.heat_trip_backend.group.service.FamilyGroupService;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * 오늘의 케어 공유와 산책 주의사항 — 이슈 #76.
 *
 * <h2>인가가 이 클래스의 절반이다</h2>
 * <p>다섯 경로 모두 {@link #requireMemberGroup} 로 시작한다. 그 메서드가 답하는 질문은 하나다 —
 * <b>"요청자가 이 그룹의 방 멤버인가."</b> 아니면 403 이고, 그 뒤로는 아무 행도 읽지 않는다
 * (완료 조건 3 · 6).
 *
 * <p><b>{@code family_group} 을 보지 않는다.</b> 멤버십의 유일한 원본은
 * {@code chat_room_member} 다(ADR-0011 결정 1). 그 표를 직접 부를 수는 없다 —
 * {@code ChatBoundaryArchitectureTest §E} 가 chat 밖의 소스에서 {@code chat.repository} 를
 * 이름으로 부르는 것을 막는다. 그래서 {@link ChatRoomService} 의 공개 표면
 * ({@link ChatRoomService#findRoom} · {@link ChatRoomService#isLiveMember})만 쓴다.
 * {@code isLiveMember} 는 이 이슈가 그 표면에 더한 메서드이고, <b>왜 거기여야 하는지</b>는
 * 그 메서드의 javadoc 에 적었다.
 *
 * <h2>인가와 필터는 서로를 대신하지 않는다</h2>
 * <p>남의 기록을 막는 장치가 둘이고, 하나만 있으면 나머지 하나가 막던 것이 그대로 새어 나온다.
 * <ol>
 *   <li><b>인가</b> — 여기. 멤버가 아니면 요청 자체가 403 이다.</li>
 *   <li><b>필터</b> — {@code CareLogRepository.findDayOfGroup} 의
 *       {@code c.group.id = :groupId}. 통과한 요청이 어느 행을 보는지를 정한다.</li>
 * </ol>
 * <p>한 사람이 여러 방에 속하는 것은 정상이라(초대코드로 들어오면 그렇게 된다) 인가만
 * 있으면 <b>가족 A 의 멤버가 가족 B 의 기록을 함께 본다.</b> 둘을 각각 되돌려 서로 다른
 * 테스트가 죽는 것을 확인했다 — 자세한 것은 리포지토리 javadoc.
 *
 * <h2>"오늘" 은 서버 시계의 로컬 날짜다</h2>
 * <p>{@code occurred_at} 을 쓸 때도 하루 경계를 자를 때도 같은 {@link Clock} 을 쓴다. 존을
 * 여기 박지 않는 이유는 <b>둘이 갈리는 것이 더 나쁘기 때문</b>이다 — 저장은 서버 존인데
 * 경계만 KST 로 자르면 서버를 UTC 로 옮기는 순간 "오늘" 이 9시간 어긋난다. 지금 운영·개발
 * 모두 KST 라 지금의 "오늘" 은 KST 다. 서버 존을 옮기는 날의 답은 {@code ClockConfig} 의
 * 빈에 존을 박는 것이고, 그러면 여기는 한 글자도 안 고쳐도 된다.
 */
@Service
@RequiredArgsConstructor
public class CareService {

    /** {@code care_log.memo} · {@code walk_note.body} 의 컬럼 길이. 둘은 같다. */
    private static final int MAX_TEXT_LENGTH = 500;

    private final CareLogRepository careLogs;

    /**
     * 그 집의 항목 목록 — 응답의 {@code careItemId} 를 푸는 데 쓴다(#560).
     *
     * <p>같은 모듈이라 서비스를 직접 든다. {@code CareItemRepository} 를 또 들지 않는 이유는
     * "접힌 것도 준다 · 순서대로 준다" 같은 규약이 그 서비스에 이미 적혀 있어서다 — 저장소를
     * 두 곳에서 부르면 그 규약이 두 벌이 된다.
     */
    private final CareItemService careItems;

    /** "그 집 아이인가" — dog 모듈의 공개 표면(#563). 판정이 두 곳에 생기지 않게 한 자리에서만 묻는다. */
    private final DogOwnership dogs;
    private final WalkNoteRepository walkNotes;
    private final FamilyGroupRepository familyGroups;
    private final ChatRoomService chatRooms;
    private final Clock clock;

    // ─────────────────────────── 케어 기록 ───────────────────────────

    /**
     * 그 그룹의 하루치 케어 — 기본은 오늘.
     *
     * <p>{@code type} 필터를 <b>쿼리가 아니라 여기서</b> 건다. 하루치는 많아야 수십 행이라
     * 인덱스를 하나 더 태울 값이 없고, 조건이 늘면 {@code group_id} 필터가 조건문 사이에
     * 묻혀 "지우면 무엇이 깨지는가" 가 안 보이게 된다. 지금은 그 한 줄이 쿼리에서 눈에 띈다.
     *
     * @throws ResponseStatusException 403 — 그 그룹의 방 멤버가 아니면
     */
    @Transactional(readOnly = true)
    public List<CareLogResponse> logsOf(long groupId, LocalDate date, CareType type,
                                        Long dogId, long actorUserId) {
        requireMemberGroup(groupId, actorUserId);

        LocalDate day = date == null ? LocalDate.now(clock) : date;
        List<CareLog> found = careLogs.findDayOfGroup(
                groupId, day.atStartOfDay(), day.plusDays(1).atStartOfDay());

        // 항목 목록을 한 번만 읽는다 — 행마다 읽으면 하루치 수십 행이 수십 왕복이 된다.
        List<CareItem> items = careItems.listOf(groupId);

        return found.stream()
                .filter(log -> type == null || log.getType() == type)
                .filter(log -> matchesDog(log, dogId))
                .map(log -> CareLogResponse.of(log, itemIdOf(log, items)))
                .toList();
    }

    /**
     * 이 기록이 <b>어느 칸에 세어지는가</b> — 규칙이 사는 자리는 여기 하나다. 이슈 #560.
     *
     * <ol>
     *   <li>행이 항목을 들고 있으면 그것 — 직접 만든 항목의 기록이다.</li>
     *   <li>아니면 그 집에서 같은 {@code systemType} 을 든 항목 — 기본 일곱의 기록이고,
     *       <b>이 컬럼이 생기기 전의 행과 산책 트래킹이 남기는 행</b>이 여기로 온다.</li>
     *   <li>짝이 없으면 {@code null}. 지어내지 않는다.</li>
     * </ol>
     *
     * <p><b>앱이 이 갈래를 다시 적지 않게 하려고</b> 응답에 실어 보낸다. 앱이 세면 규칙이 두
     * 곳에 생기고, 그때부터 한쪽만 고쳐지는 날을 기다리게 된다 — 이 저장소가 같은 자리에서
     * 여러 번 겪은 일이다.
     */
    private static Long itemIdOf(CareLog log, List<CareItem> items) {
        if (log.careItemId() != null) {
            return log.careItemId();
        }
        if (log.getType() == null) {
            return null;
        }
        return items.stream()
                .filter(item -> item.getSystemType() == log.getType())
                .map(CareItem::getId)
                .findFirst()
                .orElse(null);
    }

    /**
     * 아이 필터 — <b>그 아이의 기록과 아이 없는 옛 기록</b>을 함께 통과시킨다. 이슈 #563.
     *
     * <h2>옛 기록을 왜 함께 주나</h2>
     *
     * <p>2026-09-15 전의 행은 {@code dog_id} 가 전부 {@code null} 이다 — 쓰기 경로가 그 값을
     * 안 받았기 때문이다. 아이로 거르면서 그 행들을 빼면 <b>어제 준 밥이 화면에서 사라진다.</b>
     *
     * <p>사라지면 화면은 "아직" 이라고 말하고, 그걸 본 사람이 한 번 더 준다. 이 표가 있는
     * 이유가 정확히 그 이중 급여를 막는 것이다(#76) — <b>못 본 채로 두는 쪽이 더 나쁘다.</b>
     *
     * <p>대신 아이가 둘인 집에서는 그 옛 행이 두 아이 카드에 모두 뜬다. 어느 아이 것인지
     * 모르는 값이라 어느 쪽으로 눕혀도 지어내는 것이 된다 — 둘 다 보여 주고 사람이 판단한다.
     * 새로 쌓이는 행에는 아이가 붙으므로 이 겹침은 <b>오늘 하루짜리</b>다.
     */
    private static boolean matchesDog(CareLog log, Long dogId) {
        return dogId == null || log.dogId() == null || dogId.equals(log.dogId());
    }

    /**
     * 케어 한 건을 남긴다. <b>같은 종류가 오늘 이미 있어도 막지 않는다</b> — 완료 조건 2.
     *
     * <h2>막지 않는 이유</h2>
     * <p>두 번째 기록이 <b>실수인지 사실인지 서버는 모른다.</b> 아침에 한 번 저녁에 한 번
     * 주는 집에서 두 번째 밥은 정상이고, 물은 하루에 여러 번 간다. 막으면 "실제로 한 일" 이
     * 기록에서 사라지고, 그러면 이 표가 답해야 하는 질문("오늘 누가 무엇을 했나")에
     * 거짓으로 답하게 된다.
     *
     * <h2>그럼 경고는 누가 만드는가 — 앱이다</h2>
     * <p>확인 문구("오늘 14:20 아빠가 밥을 줬습니다. 그래도 기록할까요?")는 <b>쓰기 전에</b>
     * 떠야 하므로 결국 읽기에서 나온다. 그리고 그 읽기는 앱이 이미 하고 있다 — 홈 카드가
     * "누가 언제 했는지" 를 그리려고 {@code GET .../care-logs} 를 부르기 때문이다. 그 목록에
     * 답이 이미 들어 있는데 응답에 "오늘 이미 있음" 필드를 더하면, <b>같은 사실의 출처가
     * 둘</b>이 되고 둘이 어긋나는 날이 온다. 그래서 서버는 사실만 주고 문구는 앱이 만든다
     * ({@code app/lib/v2/widgets/today_care_card.dart}, 위젯 테스트가 문구를 잠근다).
     *
     * <p>남는 창을 정직하게 적는다: 두 사람이 <b>정확히 동시에</b> 찍으면 둘 다 "아직 없음" 을
     * 본 상태라 확인 문구 없이 두 행이 남는다. 그건 막을 것이 아니다 — 실제로 둘 다 준
     * 상황과 구별할 수 없고, 이 이슈의 목적은 기록을 막는 것이 아니라 <b>보이게 하는 것</b>이다.
     *
     * @throws ResponseStatusException 403 — 그 그룹의 방 멤버가 아니면
     */
    @Transactional
    public CareLogResponse record(long groupId, CareLogRequest request, User actor) {
        FamilyGroup group = requireMemberGroup(groupId, actor.getId());

        if (request == null || (request.type() == null) == (request.careItemId() == null)) {
            // 둘 다 없으면 어느 칸의 기록도 아니고, 둘 다 있으면 어느 쪽을 믿을지 정해야 한다.
            // 그 규칙을 적는 순간 둘 중 하나가 조용히 버려지는 자리가 생긴다.
            throw new IllegalArgumentException("케어 종류나 항목 중 하나만 보내 주세요.");
        }
        String memo = trimmedToNull(request.memo(), "메모");

        // 항목을 보냈으면 그 집 것이어야 한다. 기본 일곱을 가리키면 그 종류를 함께 적는다 —
        // 그래야 옛 기록과 같은 축으로 세어지고 산책 화면의 type='walk' 조회도 그대로 돈다.
        CareItem item = request.careItemId() == null
                ? null
                : requireItemOfGroup(groupId, request.careItemId());
        CareType type = item == null ? request.type() : item.getSystemType();

        // 어느 아이인가 (#563). **선택이다** — 아이를 한 마리도 등록 안 한 집도 기록하고,
        // 이미 나가 있는 앱은 이 필드를 모른다. 보냈으면 그 집 아이여야 한다: 누구 것인지는
        // 안 따진다 — 엄마가 등록한 보리에게 아빠가 물을 주는 것이 이 기능의 목적이다.
        Dog dog = request.dogId() == null
                ? null
                : dogs.requireInFamilyEntity(groupId, request.dogId());

        CareLog saved = careLogs.saveAndFlush(CareLog.builder()
                .dog(dog)
                .group(group)
                .careItem(item)
                .type(type)
                .doneBy(actor)
                .occurredAt(LocalDateTime.now(clock))
                .memo(memo)
                .build());

        return CareLogResponse.of(saved, itemIdOf(saved, careItems.listOf(groupId)));
    }

    /**
     * 그 집 항목을 꺼낸다. 아니면 <b>404</b> — 없는 것과 옆집 것이 같은 답이다(#209).
     *
     * <p>{@code CareItemService.requireOfGroup} 과 같은 판정인데 그쪽이 {@code private} 이다.
     * 여는 대신 여기 두 줄을 적은 이유는, 여는 순간 "인가 없이 항목을 꺼내는 공개 메서드" 가
     * 생기고 그것을 부르는 다음 자리가 인가를 빠뜨리기 때문이다.
     */
    private CareItem requireItemOfGroup(long groupId, long itemId) {
        return careItems.listOf(groupId).stream()
                .filter(item -> item.getId() == itemId)
                .findFirst()
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "그 항목을 찾을 수 없습니다."));
    }

    /**
     * 다른 기능이 한 일을 케어 기록으로 남긴다 — 이슈 #420. 표면은 {@code care.CareLogging} 이다.
     *
     * <p>{@link #record} 와 다른 점은 <b>본문(요청 DTO)을 안 받는다</b>는 것뿐이다. 종류는
     * 부르는 쪽이 정하고 메모는 없다 — 일정의 제목을 메모로 베껴 넣지 않는다. 베끼면 같은
     * 문장이 두 표에 살게 되고, 한쪽을 고쳐도 다른 쪽이 남는다.
     *
     * <p>수행자·시각은 {@link #record} 와 같은 규칙이다 — 토큰의 사용자와 서버 시계다.
     */
    @Transactional
    public CareLogResponse recordLinked(long groupId, CareType type, User actor) {
        FamilyGroup group = requireMemberGroup(groupId, actor.getId());

        // saveAndFlush 가 아니라 save 다. flush 는 **영속성 컨텍스트 전체**를 밀어내는데,
        // 부르는 쪽(일정 완료)은 그 시점에 이미 자기 엔티티를 더럽혀 뒀다. 여기서 밀면 그
        // 엔티티가 한 번 더 써지고 @Version 이 한 요청에 두 번 오른다 — 한 번 고쳤는데
        // 버전이 2 오르면 다음 편집이 이유 없이 409 를 받는다(실측으로 확인했다).
        //
        // id 는 그래도 채워진다 — IDENTITY 라 Hibernate 가 그 한 행만 즉시 INSERT 한다.
        CareLog saved = careLogs.save(CareLog.builder()
                .group(group)
                .type(type)
                .doneBy(actor)
                .occurredAt(LocalDateTime.now(clock))
                .build());

        return CareLogResponse.of(saved, itemIdOf(saved, careItems.listOf(groupId)));
    }

    /**
     * 다른 기능이 남긴 기록을 거둔다 — 이슈 #420. 표면은 {@code care.CareLogging} 이다.
     *
     * <p><b>{@link #deleteLog} 와 달리 "본인 기록만" 을 안 본다.</b> 사람이 케어 칸에서
     * 지우는 것이 아니라 <b>그 일이 일어나지 않았다고 되돌리는 것</b>이기 때문이다 — 아빠가
     * 완료로 바꿔 생긴 줄을 엄마가 되돌릴 수 있어야 한다. 되돌릴 권한은 그 일정에 대한
     * 권한이고 부르는 쪽이 확인한다. 여기서는 <b>그룹 멤버인지</b>만 본다.
     *
     * <p><b>없으면 조용히 지나간다.</b> 사람이 케어 칸에서 먼저 지웠을 수 있고, 그때 되돌리기가
     * 실패하면 사용자는 이유를 알 수 없다.
     */
    @Transactional
    public void withdrawLinkedLog(long groupId, long careLogId, long actorUserId) {
        requireMemberGroup(groupId, actorUserId);

        careLogs.findById(careLogId)
                .filter(found -> found.groupId() != null && found.groupId() == groupId)
                .ifPresent(careLogs::delete);
    }

    /**
     * 케어 기록 하나를 지운다 — #209 {@code Groups-medium-1}. 잘못 찍은 "밥 줌" 을 되돌리는 문이다.
     * 서버가 같은 종류의 두 번째 기록을 거절하지 않으므로({@link #record}) 되돌릴 문이 있어야 한다.
     *
     * <p><b>본인 기록만이다.</b> 남의 기록을 지울 수 있으면 이 표가 막으려던 산책 누락이 바로
     * 그 자리에서 생긴다 — 엄마가 실제로 다녀온 산책을 아빠가 "실수겠지" 하고 지운다.
     * 채팅 메시지 삭제(보낸 사람만, #197)와 같은 답이다. 탈퇴한 사람의 기록({@code done_by} 가
     * {@code NULL})은 누구도 못 지운다 — 본인 판정이 불가능하고, 그 사실은 남는 쪽이 안전하다.
     *
     * <p><b>다른 그룹의 기록 id 는 404 다.</b> 403 을 주면 "그 id 는 존재한다" 를 알려 주는
     * 셈이라 id 를 훑어 남의 가족이 하루에 몇 건을 찍는지 셀 수 있다. 없는 id 와 같은 답이다
     * ({@code DogService} 가 남의 반려동물에 같은 규칙을 쓴다).
     *
     * <p><b>물리 삭제다.</b> 이 표는 "지우지 않는 사건 기록" 이지만 잘못 찍은 것은 사건이
     * 아니다. 지운 뒤 같은 id 로 다시 부르면 404 다 — 채팅 메시지와 달리 행을 남기지 않는다.
     * 메모 수정은 두지 않는다 — 잘못 적었으면 지우고 다시 찍는 쪽이 "누가 언제" 를 거짓 없이 남긴다.
     *
     * @throws ResponseStatusException 403 — 그 그룹의 방 멤버가 아니거나 내 기록이 아니면 ·
     *                                 404 — 그 그룹에 그 id 의 기록이 없으면
     */
    @Transactional
    public void deleteLog(long groupId, long careLogId, long actorUserId) {
        requireMemberGroup(groupId, actorUserId);

        CareLog log = careLogs.findById(careLogId)
                .filter(found -> found.groupId() != null && found.groupId() == groupId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "케어 기록을 찾을 수 없습니다."));
        if (log.getDoneBy() == null || log.getDoneBy().getId() != actorUserId) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "내가 남긴 기록만 지울 수 있습니다.");
        }
        careLogs.delete(log);
    }

    // ─────────────────────────── 산책 주의사항 ───────────────────────────

    /**
     * 그 그룹의 주의사항 한 장. 아직 아무도 안 썼으면 <b>빈 본문</b>이다(404 가 아니다) —
     * 이유는 {@link WalkNoteResponse} 의 javadoc.
     *
     * @throws ResponseStatusException 403 — 그 그룹의 방 멤버가 아니면
     */
    @Transactional(readOnly = true)
    public WalkNoteResponse walkNoteOf(long groupId, long actorUserId) {
        requireMemberGroup(groupId, actorUserId);

        return walkNotes.findByGroupId(groupId)
                .map(WalkNoteResponse::of)
                .orElseGet(() -> WalkNoteResponse.empty(groupId));
    }

    /**
     * 주의사항을 통째로 바꾼다. 있으면 고치고 없으면 만든다.
     *
     * <p>"고친다" 는 것은 <b>본문·고친 사람·고친 시각 셋을 함께</b> 바꾸는 것이다
     * ({@code WalkNote.rewrite}). 셋을 따로 두면 본문만 바뀌고 이름이 남의 것으로 남는
     * 상태가 생긴다.
     *
     * <p>확인-후-쓰기라 정확히 동시에 오는 두 요청이 둘 다 "없다" 를 볼 수 있다. 그때
     * 두 번째를 거절하는 것은 {@code UNIQUE (group_id)} 다 — 그 제약이 없으면 그룹당 메모가
     * 둘이 되고, 조회는 그중 하나만 보여 준다(📌 #86 원칙 5).
     *
     * @throws ResponseStatusException 403 — 그 그룹의 방 멤버가 아니면
     */
    @Transactional
    public WalkNoteResponse replaceWalkNote(long groupId, String requestedBody, User actor) {
        FamilyGroup group = requireMemberGroup(groupId, actor.getId());

        String body = requestedBody == null ? "" : requestedBody.strip();
        if (body.length() > MAX_TEXT_LENGTH) {
            throw new IllegalArgumentException(
                    "산책 주의사항은 " + MAX_TEXT_LENGTH + "자 이하여야 합니다.");
        }
        LocalDateTime now = LocalDateTime.now(clock);

        WalkNote note = walkNotes.findByGroupId(groupId).orElse(null);
        if (note == null) {
            note = WalkNote.builder()
                    .group(group)
                    .body(body)
                    .updatedBy(actor)
                    .updatedAt(now)
                    .build();
        } else {
            note.rewrite(body, actor, now);
        }

        return WalkNoteResponse.of(walkNotes.saveAndFlush(note));
    }

    // ─────────────────────────── 인가 ───────────────────────────

    /**
     * 이 사람이 이 그룹의 <b>방 멤버</b>인지 확인하고, 맞으면 그룹 행을 돌려준다.
     *
     * <h2>멤버십은 {@code chat_room_member} 하나에게만 묻는다</h2>
     * <p>{@code family_group} 에는 사용자 컬럼이 아예 없다(ADR-0011 결정 1). 그룹 id 로
     * 방을 찾고({@code origin_kind='FAMILY'} · {@code origin_ref=<groupId>}), 그 방의 살아
     * 있는 멤버인지 묻는다. 강퇴된 사람({@code removed_at} 이 찍힌 행)은 <b>멤버가 아니다</b> —
     * 그 판정도 chat 안에 있다.
     *
     * <h2>없는 그룹도 403 이다 — 404 가 아니다</h2>
     * <p>404 로 답하면 그룹 id 를 1부터 훑어 "있는 가족 / 없는 가족" 을 가려낼 수 있다.
     * 가족의 존재 여부는 그 가족에게만 의미가 있는 정보다.
     * {@code ChatRoomService.requireOwner} 가 방에 대해 같은 판단을 했고, 이 저장소에서
     * "권한 없음" 과 "없음" 을 같은 코드로 답하는 규칙은 그때 정해졌다.
     *
     * <p>그래서 세 경우가 모두 같은 403 이다 — 방이 없는 그룹 · 멤버가 아닌 사람 ·
     * 아예 없는 그룹 id. <b>메시지도 하나</b>다: 셋을 다른 문구로 답하면 그 문구 차이가
     * 곧 위의 열거 수단이 된다(#6).
     *
     * <p><b>이 메서드를 지우면 무엇이 깨지는가</b> — {@code CareSharingIntegrationTest} 의
     * {@code anOutsider_isForbiddenAndSeesNoRowOfSomeoneElsesFamily} 다(완료 조건 6).
     * 필터({@code group_id = :groupId})는 그대로 있으므로 남의 그룹 기록이 <b>200 으로</b>
     * 통째로 나간다 — 필터가 인가를 대신하지 못한다는 것이 이 조합에서 보인다.
     */
    private FamilyGroup requireMemberGroup(long groupId, long actorUserId) {
        ChatRoomView room = chatRooms
                .findRoom(FamilyGroupService.ORIGIN_KIND, String.valueOf(groupId))
                .orElseThrow(CareService::notThisFamily);

        if (!chatRooms.isLiveMember(room.id(), actorUserId)) {
            throw notThisFamily();
        }
        return familyGroups.findById(groupId).orElseThrow(CareService::notThisFamily);
    }

    /** 세 가지 거절이 같은 답을 쓴다 — 이유는 {@link #requireMemberGroup} 의 javadoc. */
    private static ResponseStatusException notThisFamily() {
        return new ResponseStatusException(HttpStatus.FORBIDDEN, "이 가족 그룹의 멤버가 아닙니다.");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * 공백만 있는 값은 {@code null} 로 —  "" 와 {@code null} 이 화면에서 같은 뜻인데 저장에
     * 두 모양이 있으면 조회 조건이 그때부터 둘이 된다.
     *
     * <p>길이를 잘라서 저장하지 않고 거절하는 이유는 {@code FamilyGroupService.validName} 과
     * 같다 — 사용자가 적은 것과 화면에 뜨는 것이 다르면 아무도 그 차이를 설명해 주지 않는다.
     * 메시지에 입력값을 되싣지 않는다(#6).
     */
    private static String trimmedToNull(String value, String what) {
        if (value == null) {
            return null;
        }
        String trimmed = value.strip();
        if (trimmed.isEmpty()) {
            return null;
        }
        if (trimmed.length() > MAX_TEXT_LENGTH) {
            throw new IllegalArgumentException(
                    what + "는 " + MAX_TEXT_LENGTH + "자 이하여야 합니다.");
        }
        return trimmed;
    }
}
