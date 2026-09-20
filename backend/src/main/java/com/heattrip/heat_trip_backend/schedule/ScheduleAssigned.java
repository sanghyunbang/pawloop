package com.heattrip.heat_trip_backend.schedule;

import java.time.LocalDate;
import java.time.LocalTime;

/**
 * 누가 <b>나를 담당으로</b> 일정을 만들거나 고쳤다 — 이슈 #735. {@code ScheduleService} 가 저장
 * 트랜잭션 안에서 발행한다.
 *
 * <h2>왜 사건인가</h2>
 * <p>{@code schedule} 이 {@code push} 를 부르면 화살표가 거꾸로 선다 — 푸시는 듣는 쪽이지 일정이
 * 아는 것이 아니다. {@code chat/ChatMessagePosted} · {@code moderation/ReportFiled} 와 같은 모양으로
 * 이 모듈은 "배정됐다" 고 말하기만 하고, 누가 듣는지 모른다. 듣는 쪽은
 * {@code @TransactionalEventListener(AFTER_COMMIT)} 로 받아야 한다 — 커밋 전에 받으면 롤백된
 * 배정의 알림이 나간다.
 *
 * <h2>언제 발행하나</h2>
 * <ul>
 *   <li>만들 때 담당이 <b>만든 사람과 다르면</b>.</li>
 *   <li>고칠 때 담당이 <b>바뀌었고</b> 새 담당이 고친 사람이 아니면. 제목만 고치거나 완료로
 *       체크하는 것은 배정이 아니다 — 앱은 PATCH 에 담당을 늘 같이 보내므로 "안 바뀜" 을 봐야 한다.</li>
 *   <li>담당이 나 자신이면 안 한다 — 내가 나에게 맡긴 것을 알릴 이유가 없다.</li>
 *   <li>크루 줄({@code createCrewLine})은 맡은 사람이 곧 만든 사람이라 여기 안 온다.</li>
 * </ul>
 *
 * <h2>값이 전부 평평하다</h2>
 * <p>듣는 쪽은 다른 스레드에서 커밋 뒤에 받는다 — 엔티티를 실으면 지연 로딩이 거기서 터진다.
 * 그래서 알림 한 줄에 필요한 것만 <b>값으로</b> 들고 나간다. 메모는 안 싣는다(알림 센터는 잠금
 * 화면에 그대로 보인다).
 *
 * @param scheduleId     일정 id. 앱이 그 날을 열 좌표다
 * @param assigneeUserId 담당이 된 사람 — 받을 사람
 * @param actorUserId    만들거나 고친 사람
 * @param actorName      그 사람의 표시 이름
 * @param title          일정 제목
 * @param dogName        아이 이름. 아이가 없으면 {@code null}
 * @param onDate         날짜
 * @param atTime         시각. 하루 종일이면 {@code null}
 */
public record ScheduleAssigned(
        long scheduleId,
        long assigneeUserId,
        long actorUserId,
        String actorName,
        String title,
        String dogName,
        LocalDate onDate,
        LocalTime atTime) {
}
