package com.heattrip.heat_trip_backend.dog.controller;

import com.heattrip.heat_trip_backend.dog.dto.DogPatchRequest;
import com.heattrip.heat_trip_backend.dog.dto.DogAvatarRequest;
import com.heattrip.heat_trip_backend.dog.dto.DogRequest;
import com.heattrip.heat_trip_backend.dog.dto.DogResponse;
import com.heattrip.heat_trip_backend.dog.service.DogService;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.Valid;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 반려동물 프로필 — 이슈 #145. 계약은 {@code docs/04-api/openapi.yaml} 의 {@code /api/dogs} 다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — 셋 다 {@code SecurityConfig} 의 {@code anyRequest().authenticated()}
 *       가 받는다. {@code publicMatchers} 에 줄을 더하지 않는 것이 판단이다 —
 *       {@code CareController}·{@code GroupController} 와 같다.</li>
 *   <li><b>소유권</b> — {@code DogService} 가 쿼리 안에서 판정한다. 남의 반려동물과 없는
 *       반려동물은 <b>바이트까지 같은 404</b> 다(서비스 javadoc 참조).</li>
 *   <li><b>rate limit</b> — <b>{@code POST /api/dogs} 는 {@code group-write} 버킷</b>이다
 *       ({@code ApiRateLimitFilter.resolveRule}). 요청 한 건이 행을 만들기 때문이고,
 *       {@code POST /api/groups} 와 성격이 같아 버킷을 새로 만들지 않았다.
 *       <b>읽기 둘은 표에 넣지 않았다</b> — 표에 없는 경로는 한도가 0 이 아니라
 *       <b>무한</b>이다. 미룬 것이지 안전한 것이 아니고, 숫자를 정하려면 앱이 이 목록을 언제
 *       얼마나 부르는지부터 정해져야 한다. 총량은 {@code DogService.MAX_PETS} 가 막는다.</li>
 * </ul>
 *
 * <h2>구현하지 않은 계약 경로가 둘 있다</h2>
 * <p>{@code PATCH /api/dogs/{dogId}} 와 {@code DELETE /api/dogs/{dogId}} 는 계약에 선언돼
 * 있지만 <b>#145 에서 만들지 않는다.</b> <b>미룬 것이지 안 필요한 것이 아니다.</b>
 *
 * <ul>
 *   <li>{@code PATCH} — 계약이 생성용 {@code DogInput} 을 그대로 재사용하는데 그 스키마는
 *       {@code required: [name, size]} 라 <b>계약대로면 부분 수정이 불가능</b>하다.
 *       {@code DogPatch} 를 나누는 것은 <b>#24</b> 가 소유한다.</li>
 *   <li>{@code DELETE} — 만드는 날 <b>반드시 소프트 삭제</b>여야 한다.
 *       {@code walk.fk_walk_dog} 가 CASCADE 라 물리 삭제하면 산책 이력이 조용히 함께
 *       사라진다({@code Dog} javadoc).</li>
 * </ul>
 *
 * <p>인증 주체는 {@code @CurrentUser} 가 해석한다 — 컨트롤러가 Authorization 헤더를 다시
 * 읽지 않는다(#5). 주인을 본문으로 받지 않는 이유도 같은 자리다.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/dogs")
public class DogController {

    private final DogService dogService;

    /** 내 반려동물 목록. 계약이 봉투 없이 <b>배열 그대로</b>를 선언했다. */
    @GetMapping
    public List<DogResponse> list(@CurrentUser User user) {
        return dogService.mine(user.getId());
    }

    /**
     * 등록.
     *
     * <p>몸집·종이 계약 밖의 값이면 400 이다 — {@code DogSize.of}·{@code PetSpecies.of} 가
     * {@link IllegalArgumentException} 을 던지고 {@code GlobalExceptionHandler} 가 옮긴다.
     */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public DogResponse register(@CurrentUser User user, @Valid @RequestBody DogRequest request) {
        return dogService.register(user, request);
    }

    /** 상세. 남의 것과 없는 것이 같은 404 다. */
    @GetMapping("/{dogId}")
    public DogResponse detail(@CurrentUser User user, @PathVariable long dogId) {
        return dogService.one(user.getId(), dogId);
    }

    /** 부분 수정 (#516). 보낸 것만 바꾼다 — 남의 것과 없는 것은 같은 404 다. */
    @PatchMapping("/{dogId}")
    public DogResponse patch(@CurrentUser User user, @PathVariable long dogId,
                             @Valid @RequestBody DogPatchRequest request) {
        return dogService.patch(user.getId(), dogId, request);
    }

    /**
     * 소프트 삭제, 204. 남의 것·없는 것·이미 지운 것은 같은 404 — {@code DogService.delete}.
     * 한도 표에서는 등록과 같은 {@code group-write} 다.
     */
    @DeleteMapping("/{dogId}")
    public ResponseEntity<Void> delete(@CurrentUser User user, @PathVariable long dogId) {
        dogService.delete(user.getId(), dogId);
        return ResponseEntity.noContent().build();
    }

    // ─────────────────────────── 프로필 사진 (#448) ───────────────────────────

    /** 갈아 끼우기라 {@code PUT} 이다 — 같은 id 를 두 번 보내도 결과가 같다. 남의 것·없는 것은 404. */
    @PutMapping("/{dogId}/avatar")
    public DogResponse updateAvatar(@CurrentUser User user, @PathVariable long dogId,
                                    @Valid @RequestBody DogAvatarRequest request) {
        return dogService.updateAvatar(user.getId(), dogId, request.mediaId());
    }

    /** 사진 떼기 — 없는데 떼도 200 이다. 바뀐 아이를 돌려줘 앱이 그대로 그린다. */
    @DeleteMapping("/{dogId}/avatar")
    public DogResponse removeAvatar(@CurrentUser User user, @PathVariable long dogId) {
        return dogService.removeAvatar(user.getId(), dogId);
    }
}
