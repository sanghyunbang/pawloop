package com.heattrip.heat_trip_backend.bookmark.controller;

import com.heattrip.heat_trip_backend.bookmark.dto.*;
import com.heattrip.heat_trip_backend.bookmark.entity.Collection;
import com.heattrip.heat_trip_backend.bookmark.entity.CollectionItem;
import com.heattrip.heat_trip_backend.bookmark.service.CollectionService;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/collections")
public class CollectionController {

    private final CollectionService collectionService;
    private final UserService userService;

    private User me(String authHeader) {
        String email = userService.emailFromAuth(authHeader);
        return userService.findByEmail(email);
    }

    /** 컬렉션 목록 (카운트/최신아이템 contentId 포함) */
    @GetMapping
    public ResponseEntity<List<CollectionResponse>> list(@RequestHeader("Authorization") String authHeader) {
        User user = me(authHeader);
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
    public ResponseEntity<CollectionResponse> create(@RequestHeader("Authorization") String authHeader,
                                                     @RequestBody CollectionRequest req) {
        if (req.getName() == null || req.getName().isBlank()) return ResponseEntity.badRequest().build();
        User user = me(authHeader);
        Collection c = collectionService.create(user, req.getName());
        var s = collectionService.stats(user, c);
        return ResponseEntity.ok(CollectionResponse.of(c, s.count(), s.latestContentId()));
    }

    /** 이름 변경 */
    @PutMapping("/{id}")
    public ResponseEntity<CollectionResponse> rename(@RequestHeader("Authorization") String authHeader,
                                                     @PathVariable Long id,
                                                     @RequestBody CollectionRequest req) {
        if (req.getName() == null || req.getName().isBlank()) return ResponseEntity.badRequest().build();
        User user = me(authHeader);
        Collection c = collectionService.rename(user, id, req.getName());
        var s = collectionService.stats(user, c);
        return ResponseEntity.ok(CollectionResponse.of(c, s.count(), s.latestContentId()));
    }

    /** 삭제 */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@RequestHeader("Authorization") String authHeader,
                                       @PathVariable Long id) {
        User user = me(authHeader);
        collectionService.delete(user, id);
        return ResponseEntity.noContent().build();
    }

    /** 아이템 목록 */
    @GetMapping("/{id}/items")
    public ResponseEntity<List<CollectionItemResponse>> items(@RequestHeader("Authorization") String authHeader,
                                                              @PathVariable Long id) {
        User user = me(authHeader);
        List<CollectionItem> items = collectionService.items(user, id);
        return ResponseEntity.ok(items.stream().map(CollectionItemResponse::from).toList());
    }

    /** 아이템 추가 */
    @PostMapping("/{id}/items")
    public ResponseEntity<Void> addItem(@RequestHeader("Authorization") String authHeader,
                                        @PathVariable Long id,
                                        @RequestBody CollectionItemRequest req) {
        if (req.getContentId() == null || req.getContentId().isBlank()) return ResponseEntity.badRequest().build();
        User user = me(authHeader);
        collectionService.addItem(user, String.valueOf(id), req.getContentId());
        return ResponseEntity.ok().build();
    }

    /** 아이템 제거 */
    @DeleteMapping("/{id}/items/{contentId}")
    public ResponseEntity<Void> removeItem(@RequestHeader("Authorization") String authHeader,
                                           @PathVariable Long id,
                                           @PathVariable String contentId) {
        User user = me(authHeader);
        collectionService.removeItem(user, id, contentId);
        return ResponseEntity.noContent().build();
    }
}
