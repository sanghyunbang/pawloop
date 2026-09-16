package com.heattrip.heat_trip_backend.care.controller;

import com.heattrip.heat_trip_backend.care.dto.CareItemOrderRequest;
import com.heattrip.heat_trip_backend.care.dto.CareItemRequest;
import com.heattrip.heat_trip_backend.care.dto.CareItemResponse;
import com.heattrip.heat_trip_backend.care.service.CareItemService;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 그 집이 챙기는 일의 <b>목록</b> — 이슈 #560 조각 2. 계약은 {@code docs/04-api/openapi.yaml} 의
 * {@code /api/groups/{groupId}/care-items} 다.
 *
 * <h2>왜 {@code CareController} 에 안 붙이나</h2>
 *
 * <p>거기는 <b>기록</b>("오늘 누가 무엇을 했나")이고 여기는 <b>목록</b>("이 집은 무엇을
 * 챙기나")이다. 한 클래스에 두면 다섯이던 매핑이 열이 되고, 그러면 "이 컨트롤러가 무엇을
 * 하는 곳인가" 를 한 줄로 못 적는다. 계약 검사도 두 벌이라 어느 쪽이 깨졌는지 바로 보인다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — {@code SecurityConfig} 의 {@code anyRequest().authenticated()} 가 받는다.
 *       {@code publicMatchers} 에 줄을 더하지 않는다 — {@code CareController} 와 같은 판단.</li>
 *   <li><b>그룹 멤버십</b> — {@code CareItemService} 가 {@code FamilyMembership.requireMember}
 *       로 판정한다. 멤버가 아니면 403 이고, 그 판정의 원본은 {@code chat_room_member} 하나다.
 *       <b>{@code CareService} 의 {@code requireMemberGroup} 를 복사하지 않았다</b> — 같은
 *       판정이 두 곳에 생기면 한쪽만 고쳐지는 날이 온다.</li>
 *   <li><b>행 대조</b> — 인가를 지나도 {@code itemId} 가 그 집 것인지 다시 본다. 한 사람이
 *       여러 방에 속하는 것은 정상이라(초대코드) 인가만으로는 옆집 항목이 고쳐진다.</li>
 *   <li><b>rate limit</b> — <b>쓰기 넷은 {@code group-write} 버킷</b>이다. 읽기 하나는 넣지
 *       않았다 — {@code GET care-logs} 가 표 밖인 것과 같은 판단이고, 표에 없는 경로는 한도가
 *       0 이 아니라 <b>무한</b>이라는 것을 알고 미룬 것이다.</li>
 * </ul>
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/groups/{groupId}/care-items")
public class CareItemController {

    private final CareItemService items;

    /**
     * 그 집의 목록 — <b>접힌 것까지</b>, 순서대로.
     *
     * <p>접힌 것을 빼지 않는 이유는 고치기 화면이 "다시 켜기" 를 그려야 하기 때문이다. 카드는
     * {@code archivedAt} 이 비어 있는 것만 그린다 — 두 화면이 쿼리를 나눠 갖지 않는 이유는,
     * 나누면 "접힘" 의 정의가 두 곳에 생기기 때문이다.
     */
    @GetMapping
    public List<CareItemResponse> list(@CurrentUser User user, @PathVariable long groupId) {
        return items.itemsOf(groupId, user.getId());
    }

    /** 항목 하나 만들기 — 맨 뒤에 놓인다. 규칙은 {@code CareItemService.create} 의 javadoc. */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public CareItemResponse create(@CurrentUser User user,
                                   @PathVariable long groupId,
                                   @RequestBody CareItemRequest request) {
        return items.create(groupId, request, user.getId());
    }

    /**
     * 목록의 순서 — 전부를 한 번에.
     *
     * <p><b>이 매핑이 {@code /{itemId}} 보다 먼저 맞아야 한다.</b> 스프링은 리터럴 경로를
     * 경로 변수보다 앞에 두므로 {@code /order} 가 {@code itemId} 로 읽히지 않는다 — 그
     * 순서가 뒤집히면 이 요청이 400({@code "order" 를 long 으로 못 읽음})이 된다. 말로 믿지
     * 않으려고 {@code CareItemApiIntegrationTest} 가 실제로 부른다.
     */
    @PutMapping("/order")
    public ResponseEntity<Void> reorder(@CurrentUser User user,
                                        @PathVariable long groupId,
                                        @RequestBody CareItemOrderRequest request) {
        items.reorder(groupId, request == null ? null : request.itemIds(), user.getId());
        return ResponseEntity.noContent().build();
    }

    /**
     * 항목 하나 전량 교체 — {@code PATCH} 가 아닌 이유는 {@code CareItemRequest} 의 javadoc.
     */
    @PutMapping("/{itemId}")
    public CareItemResponse replace(@CurrentUser User user,
                                    @PathVariable long groupId,
                                    @PathVariable long itemId,
                                    @RequestBody CareItemRequest request) {
        return items.replace(groupId, itemId, request, user.getId());
    }

    /**
     * 항목 접기 — <b>지우는 것이 아니다.</b> 지우면 지난 기록이 이름을 잃는다.
     *
     * <p>{@code DELETE} 인데 행이 남는 것이 이상해 보일 수 있다. 그래도 {@code DELETE} 인
     * 이유는 <b>사용자에게는 지우는 동작</b>이고(카드에서 사라진다) 화면이 미는 제스처로
     * 부르기 때문이다. 되살리기는 {@code PUT} 에 {@code archived: false} 다.
     */
    @DeleteMapping("/{itemId}")
    public ResponseEntity<Void> archive(@CurrentUser User user,
                                        @PathVariable long groupId,
                                        @PathVariable long itemId) {
        items.archive(groupId, itemId, user.getId());
        return ResponseEntity.noContent().build();
    }
}
