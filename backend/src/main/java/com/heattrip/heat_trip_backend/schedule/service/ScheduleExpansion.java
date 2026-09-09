package com.heattrip.heat_trip_backend.schedule.service;

import com.heattrip.heat_trip_backend.schedule.entity.Schedule;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/**
 * 반복 규칙을 기간 안의 날짜들로 펼친다 — 이슈 #421, 부모 #416.
 *
 * <h2>왜 클래스가 따로인가</h2>
 * <p>순수 함수라서다. 규칙 해석은 <b>윤년·말일·주 경계</b>가 걸리는 자리인데, 그것을
 * 서비스 안에 두면 DB 와 인가를 함께 세운 테스트로만 잴 수 있다. 여기 있으면 날짜만
 * 넣어 직접 잰다.
 *
 * <h2>펼친 하루에는 행이 없다</h2>
 * <p>규칙은 <b>한 줄</b>이고, 화면이 보는 것은 그 줄에서 만들어 낸 날짜들이다. 행을 미리
 * 만들어 두지 않는 이유는 {@code ScheduleRepeat} javadoc 에 있다.
 *
 * <p>그래서 펼친 하루를 <b>고치거나 완료하려면</b> 그때 비로소 행이 생긴다
 * ({@code ScheduleService.overrideOneDay}). 그 전까지 그 하루는 규칙의 그림자다.
 */
final class ScheduleExpansion {

    private ScheduleExpansion() {
    }

    /**
     * 이 규칙이 {@code [from, to]} 안에서 오는 날들.
     *
     * <p>규칙 넷이 여기 다 있다.
     *
     * <ol>
     *   <li>시작일 <b>전</b>에는 안 온다.</li>
     *   <li>종료일 <b>뒤</b>에는 안 온다. 종료일이 없으면 기간 끝까지다 — 무한이 안전한
     *       이유는 기간에 이미 상한이 있기 때문이다.</li>
     *   <li>{@code exceptions} 에 있는 날은 빠진다 — 건너뛴 날이든 옮긴 날이든 같다.</li>
     *   <li>되풀이가 아니면 <b>시작일 하루</b>뿐이다. 그 하루가 기간 밖이면 빈 목록이다.</li>
     * </ol>
     *
     * <p>날짜를 하루씩 올리며 {@code fallsOn} 을 묻는다. 92일 상한이 있어 최악이 92번이고,
     * 주기별로 다음 날짜를 계산하는 코드보다 <b>틀릴 자리가 적다</b> — 매월 31일이 없는
     * 달을 건너뛰는 것이 그 예다.
     */
    static List<LocalDate> datesOf(Schedule rule, LocalDate from, LocalDate to,
                                   Set<LocalDate> exceptions) {
        LocalDate start = rule.getOnDate();
        LocalDate first = from.isAfter(start) ? from : start;

        LocalDate last = to;
        LocalDate until = rule.getRepeatUntil();
        if (until != null && until.isBefore(last)) {
            last = until;
        }

        List<LocalDate> out = new ArrayList<>();
        for (LocalDate day = first; !day.isAfter(last); day = day.plusDays(1)) {
            if (rule.getRepeatKind().fallsOn(start, day) && !exceptions.contains(day)) {
                out.add(day);
            }
        }
        return out;
    }
}
