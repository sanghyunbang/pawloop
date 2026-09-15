package com.heattrip.heat_trip_backend.dog.controller;

import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.dog.dto.DogResponse;
import com.heattrip.heat_trip_backend.dog.service.DogService;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 우리 집 아이 목록 — 이슈 #563. 계약은 {@code GET /api/groups/{groupId}/dogs} 다.
 *
 * <h2>왜 따로 있나</h2>
 *
 * <p>{@code DogController} 는 {@code @RequestMapping("/api/dogs")} 라 이 경로를 담을 수 없다.
 * 그리고 담을 수 있었더라도 나눴을 것이다 — <b>두 경로가 답하는 질문이 다르다.</b>
 *
 * <ul>
 *   <li>{@code GET /api/dogs} — <b>내가 등록한 아이.</b> 고치고 지울 수 있는 것들이다.</li>
 *   <li>{@code GET /api/groups/&#123;groupId&#125;/dogs} — <b>우리 집 아이.</b> 돌보는
 *       것들이다. 남이 등록한 아이가 섞여 있고 그것은 <b>볼 수만</b> 있다.</li>
 * </ul>
 *
 * <p>이 앱의 목적이 업무 분담과 누락 방지라서(#76) 홈과 케어 카드가 보는 것은 <b>뒤엣것</b>이다.
 * 엄마가 등록했든 아빠가 등록했든 보리는 그 집 아이이고, 물을 주는 것은 둘 다 한다.
 *
 * <h2>인가</h2>
 *
 * <p>{@code FamilyMembership.requireMember} 가 판정한다 — 식구가 아니면 403 이고, 없는
 * 그룹도 같은 403 이다({@code CareController} 와 같은 규칙). 판정의 원본은
 * {@code chat_room_member} 하나다(ADR-0011).
 *
 * <p><b>rate limit 을 걸지 않는다.</b> {@code GET .../care-logs} 와 같은 읽기이고, 그 둘이
 * 표 밖인 것이 이미 기록된 판단이다({@code CareController} 의 인가 절) — 표에 없는 경로는
 * 한도가 0 이 아니라 무한이라는 것을 알고 미룬 것이다.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/groups/{groupId}/dogs")
public class FamilyDogController {

    private final DogService dogService;

    /**
     * 우리 집 아이 전부. 계약이 봉투 없이 <b>배열 그대로</b>를 선언했다 —
     * {@code GET /api/dogs} 와 같은 모양이라 앱이 파서를 하나만 둔다.
     *
     * <p>순서는 <b>등록한 사람별로 모아서</b> 등록순이다. 홈의 아이 스위처가 이 순서로
     * 그려지는데, 엄마 아이 · 아빠 아이 · 엄마 아이 로 섞이면 누구 아이인지 읽는 데 매번
     * 이름을 봐야 한다.
     */
    @GetMapping
    public List<DogResponse> ofFamily(@CurrentUser User user, @PathVariable long groupId) {
        return dogService.ofFamily(groupId, user.getId());
    }
}
