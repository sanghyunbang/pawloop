package com.heattrip.heat_trip_backend.group.controller;

import com.heattrip.heat_trip_backend.OAuth.principal.CurrentUser;
import com.heattrip.heat_trip_backend.group.dto.CreateGroupRequest;
import com.heattrip.heat_trip_backend.group.dto.GroupResponse;
import com.heattrip.heat_trip_backend.group.service.FamilyGroupService;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.NoSuchElementException;

/**
 * 가족 그룹 — 이슈 #75. 계약은 {@code docs/04-api/openapi.yaml} 의 {@code /api/groups} 다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <p>두 경로 모두 인증이 필요하고, {@code SecurityConfig} 의 {@code anyRequest().authenticated()}
 * 가 그것을 받는다 — {@code publicMatchers} 에 {@code /api/groups} 는 없다. 새 줄을 더하지
 * 않은 것이 판단이다: 여기에 경로를 하나 더 적으면 "인증 필요" 를 두 곳에서 관리하게 된다.
 * 토큰 없이 부르면 401 이라는 것을 통합 테스트가 잠근다.
 *
 * <p><b>rate limit 은 등록하지 않았다.</b> {@code ApiRateLimitFilter.resolveRule} 의 표에 없는
 * 경로는 무제한이며, 그 판단과 조건은 그 메서드의 주석에 적었다(이슈 #75 의 NOTE 가 참여
 * 경로 버킷을 M2.6 으로 미뤘다).
 *
 * <p>인증 주체는 {@code @CurrentUser} 가 해석한다 — 컨트롤러가 Authorization 헤더를 다시
 * 읽지 않는다(#5).
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/groups")
public class GroupController {

    private final FamilyGroupService familyGroups;

    /**
     * 가족 그룹 생성. 방과 {@code OWNER} 멤버십이 같은 트랜잭션에서 함께 생긴다.
     *
     * <p><b>초대코드를 여기서 발급하지 않는다.</b> 계약은 예전에 "그룹을 만들고 초대코드를
     * 발급합니다" 였는데, ADR-0011 이 초대코드를 방으로 옮기면서 그 문장은 옛 모양이 됐다.
     * 발급은 {@code POST /api/chat/rooms/{roomId}/invites} 이고, 응답의 {@code roomId} 가
     * 그 경로로 가는 열쇠다.
     */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public GroupResponse create(@CurrentUser User user, @RequestBody CreateGroupRequest request) {
        return familyGroups.create(user.getId(), request.name());
    }

    /**
     * 내 가족 그룹과 멤버 목록. 속한 그룹이 없으면 404 — 계약이 그렇게 선언한다.
     *
     * <p>메시지에 사용자 id 를 싣지 않는다. 이 문구는 그대로 응답 본문이 된다(#6).
     */
    @GetMapping("/me")
    public GroupResponse me(@CurrentUser User user) {
        return familyGroups.findMyGroup(user.getId())
                .orElseThrow(() -> new NoSuchElementException("속한 가족 그룹이 없습니다."));
    }
}
