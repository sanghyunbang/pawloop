package com.heattrip.heat_trip_backend.crew.controller;

import com.heattrip.heat_trip_backend.crew.dto.CrewPatch;
import com.heattrip.heat_trip_backend.crew.dto.CrewRequest;
import com.heattrip.heat_trip_backend.crew.dto.CrewResponse;
import com.heattrip.heat_trip_backend.crew.service.CrewService;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.Valid;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

/**
 * 크루 — 이슈 #417.
 *
 * <h2>목록 질문 둘을 {@code scope} 하나로 가른다</h2>
 * <p>{@code ?scope=mine} 은 내가 든 크루, {@code ?scope=neighborhood} 는 우리 동네 공개 크루다.
 * 경로를 둘로 파지 않은 이유는 <b>돌아오는 것이 같은 카드</b>이기 때문이다 — 화면도 같은
 * 위젯으로 그린다. 기본값은 {@code mine} 이다. 크루 화면을 여는 사람 대부분은 이미 든 모임을
 * 보러 온다.
 *
 * <h2>참여가 둘인 것은 증거가 다르기 때문이다</h2>
 * <ul>
 *   <li>{@code POST /api/crews/{id}/members/me} — <b>공개 크루</b>. 증거가 필요 없다.</li>
 *   <li>{@code POST /api/crews/join/{code}} — <b>초대 코드</b>. 크루 id 를 아직 모르는 사람이
 *       쓰므로 경로에 id 가 없다. 코드 발급은 이미 있는 채팅 초대
 *       ({@code POST /api/chat/rooms/{roomId}/invites})가 그대로 한다.</li>
 * </ul>
 *
 * <h2>나가기와 강퇴가 다른 경로다</h2>
 * <p>{@code .../members/me} 와 {@code .../members/{userId}} 로 나눈다. 하나로 묶고 id 를
 * 비교해 갈라도 되지만, 그러면 <b>"재입장 금지를 걸었나" 가 조건문 하나에 숨는다.</b>
 * 나가기는 안 걸고 강퇴는 건다.
 *
 * <p>인증 주체는 {@code @CurrentUser} 가 해석한다.
 */
@RestController
@RequestMapping("/api/crews")
public class CrewController {

    /** 내가 든 크루. {@code scope} 를 안 주면 이것이다. */
    static final String SCOPE_MINE = "mine";

    /** 우리 동네 공개 크루. */
    static final String SCOPE_NEIGHBORHOOD = "neighborhood";

    private final CrewService crews;

    public CrewController(CrewService crews) {
        this.crews = crews;
    }

    @GetMapping
    public List<CrewResponse> list(@CurrentUser User user,
                                   @RequestParam(required = false, defaultValue = SCOPE_MINE)
                                   String scope) {
        return switch (scope) {
            case SCOPE_MINE -> crews.mine(user.getId());
            case SCOPE_NEIGHBORHOOD -> crews.nearby(user);
            default -> throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "scope 는 mine · neighborhood 중 하나여야 합니다.");
        };
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public CrewResponse create(@CurrentUser User user,
                               @Valid @RequestBody CrewRequest request) {
        return crews.create(user, request);
    }

    @GetMapping("/{crewId}")
    public CrewResponse detail(@CurrentUser User user, @PathVariable long crewId) {
        return crews.detail(crewId, user);
    }

    /** 방장만. 아니면 403 — 완료 조건 4. */
    @PatchMapping("/{crewId}")
    public CrewResponse edit(@CurrentUser User user,
                             @PathVariable long crewId,
                             @Valid @RequestBody CrewPatch patch) {
        return crews.edit(crewId, user, patch);
    }

    /** 공개 크루에 바로 들어온다. 이미 든 사람에게도 200 이다. */
    @PostMapping("/{crewId}/members/me")
    public CrewResponse join(@CurrentUser User user, @PathVariable long crewId) {
        return crews.join(crewId, user);
    }

    /**
     * 초대 코드로 들어온다 — 완료 조건 2.
     *
     * <p>코드를 본문이 아니라 경로에 두는 것은 이미 있는 채팅 참여
     * ({@code POST /api/chat/invites/{code}/join})와 같은 모양이라서다. 코드는 비밀이 아니라
     * <b>공유하라고 만든 값</b>이고, 이 요청은 GET 이 아니라 POST 라 브라우저 이력에 안 남는다.
     */
    @PostMapping("/join/{code}")
    public CrewResponse joinByCode(@CurrentUser User user, @PathVariable String code) {
        return crews.joinByCode(code, user);
    }

    /** 크루를 나간다 — 방에서도 나간다. 나갈 곳이 하나뿐이다(완료 조건 6). */
    @DeleteMapping("/{crewId}/members/me")
    public ResponseEntity<Void> leave(@CurrentUser User user, @PathVariable long crewId) {
        crews.leave(crewId, user);
        return ResponseEntity.noContent().build();
    }

    /** 방장만. 아니면 403 — 완료 조건 4. 이미 나가 있어도 204 다. */
    @DeleteMapping("/{crewId}/members/{userId}")
    public ResponseEntity<Void> kick(@CurrentUser User user,
                                     @PathVariable long crewId,
                                     @PathVariable long userId) {
        crews.kick(crewId, user, userId);
        return ResponseEntity.noContent().build();
    }
}
