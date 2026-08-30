package com.heattrip.heat_trip_backend.care.service;

import com.heattrip.heat_trip_backend.care.dto.CareLogRequest;
import com.heattrip.heat_trip_backend.care.dto.CareLogResponse;
import com.heattrip.heat_trip_backend.care.dto.WalkNoteResponse;
import com.heattrip.heat_trip_backend.care.entity.CareLog;
import com.heattrip.heat_trip_backend.care.entity.CareType;
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
 * <p>네 경로 모두 {@link #requireMemberGroup} 로 시작한다. 그 메서드가 답하는 질문은 하나다 —
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
    public List<CareLogResponse> logsOf(long groupId, LocalDate date, CareType type, long actorUserId) {
        requireMemberGroup(groupId, actorUserId);

        LocalDate day = date == null ? LocalDate.now(clock) : date;
        List<CareLog> found = careLogs.findDayOfGroup(
                groupId, day.atStartOfDay(), day.plusDays(1).atStartOfDay());

        return found.stream()
                .filter(log -> type == null || log.getType() == type)
                .map(CareLogResponse::of)
                .toList();
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

        if (request == null || request.type() == null) {
            throw new IllegalArgumentException("케어 종류는 필수입니다.");
        }
        String memo = trimmedToNull(request.memo(), "메모");

        CareLog saved = careLogs.saveAndFlush(CareLog.builder()
                // dogId 는 요청에서 읽지 않는다 — dog 표가 없어 검증할 수 없다(CareLog javadoc).
                .group(group)
                .type(request.type())
                .doneBy(actor)
                .occurredAt(LocalDateTime.now(clock))
                .memo(memo)
                .build());

        return CareLogResponse.of(saved);
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
