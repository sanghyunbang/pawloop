package com.heattrip.heat_trip_backend.crew.controller;

import com.heattrip.heat_trip_backend.crew.dto.CrewFavorRequest;
import com.heattrip.heat_trip_backend.crew.dto.CrewFavorResponse;
import com.heattrip.heat_trip_backend.crew.service.CrewFavorService;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.Valid;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 품앗이 — 이슈 #417.
 *
 * <h2>맡기와 무르기가 다른 경로다</h2>
 * <p>{@code POST .../take} 와 {@code DELETE .../take}. 하나로 묶고 본문으로 가를 수도
 * 있지만, 그러면 <b>"맡는 것인가 무르는 것인가" 가 값 하나에 숨는다.</b> 그 값을 잘못 준 날
 * 사용자는 맡으려다 무른다.
 *
 * <h2>무르기와 지우기도 다르다</h2>
 * <p>{@code DELETE .../take} 는 <b>맡은 사람</b>이 안 하기로 하는 것이고,
 * {@code DELETE .../favors/{id}} 는 <b>올린 사람</b>이 부탁을 거둬들이는 것이다. 권한도
 * 결과도 다르다 — 앞엣것은 부탁이 다시 열리고, 뒤엣것은 부탁이 사라진다.
 *
 * <p>인증 주체는 {@code @CurrentUser} 가 해석한다.
 */
@RestController
@RequestMapping("/api/crews/{crewId}/favors")
public class CrewFavorController {

    private final CrewFavorService favors;

    public CrewFavorController(CrewFavorService favors) {
        this.favors = favors;
    }

    /** 그 크루의 부탁 — <b>멤버만</b>. 지난 것은 빠진다. */
    @GetMapping
    public List<CrewFavorResponse> list(@CurrentUser User user, @PathVariable long crewId) {
        return favors.list(crewId, user);
    }

    /** 부탁을 올린다. 아이는 <b>내 아이</b>여야 한다. */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public CrewFavorResponse post(@CurrentUser User user,
                                  @PathVariable long crewId,
                                  @Valid @RequestBody CrewFavorRequest request) {
        return favors.post(crewId, user, request);
    }

    /** "제가 할게요". 이미 맡은 것이면 409, 내 부탁이면 400. */
    @PostMapping("/{favorId}/take")
    public CrewFavorResponse take(@CurrentUser User user,
                                  @PathVariable long crewId,
                                  @PathVariable long favorId) {
        return favors.take(crewId, favorId, user);
    }

    /** 맡은 사람이 무른다. 달력의 줄도 함께 사라진다. */
    @DeleteMapping("/{favorId}/take")
    public CrewFavorResponse release(@CurrentUser User user,
                                     @PathVariable long crewId,
                                     @PathVariable long favorId) {
        return favors.release(crewId, favorId, user);
    }

    /** 올린 사람이 거둬들인다. 이미 맡은 것이어도 지울 수 있다. */
    @DeleteMapping("/{favorId}")
    public ResponseEntity<Void> cancel(@CurrentUser User user,
                                       @PathVariable long crewId,
                                       @PathVariable long favorId) {
        favors.cancel(crewId, favorId, user);
        return ResponseEntity.noContent().build();
    }
}
