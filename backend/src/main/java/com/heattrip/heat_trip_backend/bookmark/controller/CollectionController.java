package com.heattrip.heat_trip_backend.bookmark.controller;

import com.heattrip.heat_trip_backend.bookmark.dto.*;
import com.heattrip.heat_trip_backend.bookmark.entity.Collection;
import com.heattrip.heat_trip_backend.bookmark.entity.CollectionItem;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.bookmark.service.CollectionService;
import com.heattrip.heat_trip_backend.user.entity.User;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/collections")
public class CollectionController {

    private final CollectionService collectionService;

    // 인증 주체 해석은 CurrentUserArgumentResolver 한 곳이다. 예전에는 여기 private User me(authHeader) 가
    // 있었고, 토큰 subject 를 이메일로 보고 조회해서 모든 소셜 계정에서 400 이었다. (이슈 #5)

    /** 컬렉션 목록 (카운트/최신아이템 contentId 포함) */
    @GetMapping
    public ResponseEntity<List<CollectionResponse>> list(@CurrentUser User user) {
        List<Collection> rows = collectionService.findAll(user);
        List<CollectionResponse> out = new ArrayList<>();
        for (Collection c : rows) {
            var s = collectionService.stats(user, c);
            out.add(CollectionResponse.of(c, s.count(), s.latestContentId()));
        }
        return ResponseEntity.ok(out);
    }

    /** 생성 */
    @PostMapping
    public ResponseEntity<CollectionResponse> create(@CurrentUser User user,
                                                     @RequestBody CollectionRequest req) {
        if (req.getName() == null || req.getName().isBlank()) return ResponseEntity.badRequest().build();
        Collection c = collectionService.create(user, req.getName());
        var s = collectionService.stats(user, c);
        return ResponseEntity.ok(CollectionResponse.of(c, s.count(), s.latestContentId()));
    }

    /** 이름 변경 */
    @PutMapping("/{id}")
    public ResponseEntity<CollectionResponse> rename(@CurrentUser User user,
                                                     @PathVariable Long id,
                                                     @RequestBody CollectionRequest req) {
        if (req.getName() == null || req.getName().isBlank()) return ResponseEntity.badRequest().build();
        Collection c = collectionService.rename(user, id, req.getName());
        var s = collectionService.stats(user, c);
        return ResponseEntity.ok(CollectionResponse.of(c, s.count(), s.latestContentId()));
    }

    /** 삭제 */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@CurrentUser User user,
                                       @PathVariable Long id) {
        collectionService.delete(user, id);
        return ResponseEntity.noContent().build();
    }

    /** 아이템 목록 */
    @GetMapping("/{id}/items")
    public ResponseEntity<List<CollectionItemResponse>> items(@CurrentUser User user,
                                                              @PathVariable Long id) {
        List<CollectionItem> items = collectionService.items(user, id);
        return ResponseEntity.ok(items.stream().map(CollectionItemResponse::from).toList());
    }

    /** 아이템 추가 */
    @PostMapping("/{id}/items")
    public ResponseEntity<Void> addItem(@CurrentUser User user,
                                        @PathVariable Long id,
                                        @RequestBody CollectionItemRequest req) {
        if (req.getContentId() == null || req.getContentId().isBlank()) return ResponseEntity.badRequest().build();
        collectionService.addItem(user, String.valueOf(id), req.getContentId());
        return ResponseEntity.ok().build();
    }

    /** 아이템 제거 */
    @DeleteMapping("/{id}/items/{contentId}")
    public ResponseEntity<Void> removeItem(@CurrentUser User user,
                                           @PathVariable Long id,
                                           @PathVariable String contentId) {
        collectionService.removeItem(user, id, contentId);
        return ResponseEntity.noContent().build();
    }
}
