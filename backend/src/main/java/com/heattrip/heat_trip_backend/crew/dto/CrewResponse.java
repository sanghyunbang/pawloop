package com.heattrip.heat_trip_backend.crew.dto;

import com.heattrip.heat_trip_backend.crew.CrewTime;
import com.heattrip.heat_trip_backend.crew.entity.Crew;
import com.heattrip.heat_trip_backend.crew.entity.CrewVisibility;

import java.time.Instant;
import java.util.List;

/**
 * 계약의 {@code Crew} — 이슈 #417.
 *
 * @param roomId    이 크루의 대화방. 크루의 알맹이가 방이라 <b>늘 함께 준다</b> — 화면이
 *                  방으로 가려고 한 번 더 묻게 만들지 않는다
 * @param memberCount 지금 든 사람 수. 강퇴된 사람은 안 센다
 * @param mine      내가 든 크루인가. 목록에서 "참여" 와 "들어가기" 를 가르는 값이다
 * @param owner     내가 방장인가. 고치기·강퇴 버튼을 그릴지 정한다
 * @param members   멤버 목록. <b>목록 조회에서는 비어 있다</b> — 카드 하나에 사람 스무 명을
 *                  실어 나를 이유가 없다. 상세에서만 채운다
 */
public record CrewResponse(
        Long id,
        Long roomId,
        String name,
        String intro,
        String neighborhoodCode,
        CrewVisibility visibility,
        Integer capacity,
        int memberCount,
        boolean mine,
        boolean owner,
        List<Member> members,
        Instant createdAt) {

    /** 사람 한 명 — id 와 이름과 역할. */
    public record Member(Long userId, String nickname, String role) {
    }

    public static CrewResponse of(Crew crew, long roomId, int memberCount,
                                  boolean mine, boolean owner, List<Member> members) {
        return new CrewResponse(
                crew.getId(),
                roomId,
                crew.getName(),
                crew.getIntro(),
                crew.getNeighborhoodCode(),
                crew.getVisibility(),
                crew.getCapacity(),
                memberCount,
                mine,
                owner,
                members,
                CrewTime.toInstant(crew.getCreatedAt()));
    }
}
