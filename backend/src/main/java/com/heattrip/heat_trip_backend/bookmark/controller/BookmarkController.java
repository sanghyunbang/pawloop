// src/main/java/com/heattrip/heat_trip_backend/bookmark/controller/BookmarkController.java
package com.heattrip.heat_trip_backend.bookmark.controller;

import com.heattrip.heat_trip_backend.bookmark.dto.BookmarkRequest;
import com.heattrip.heat_trip_backend.bookmark.dto.BookmarkResponse;
import com.heattrip.heat_trip_backend.bookmark.entity.Bookmark;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.bookmark.service.BookmarkService;
import com.heattrip.heat_trip_backend.user.entity.User;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/bookmarks")
public class BookmarkController {

    private final BookmarkService bookmarkService;

    // 인증 주체 해석은 CurrentUserArgumentResolver 한 곳이다. 예전에는 여기 private User me(authHeader) 가
    // 있었고, 토큰 subject 를 이메일로 보고 조회해서 모든 소셜 계정에서 400 이었다. (이슈 #5)

    /** 내 북마크 목록 */
    @GetMapping
    public ResponseEntity<List<BookmarkResponse>> list(@CurrentUser User user) {
        List<Bookmark> rows = bookmarkService.findAll(user);
        return ResponseEntity.ok(rows.stream().map(BookmarkResponse::from).toList());
    }

    /** 북마크 추가 (collectionId는 선택) */
    @PostMapping
    public ResponseEntity<Void> add(@CurrentUser User user,
                                    @RequestBody BookmarkRequest req) {
        if (req.getContentId() == null || req.getContentId().isBlank()) {
            return ResponseEntity.badRequest().build();
        }
        bookmarkService.add(user, req.getContentId(), req.getCollectionId());
        return ResponseEntity.ok().build();
    }

    /** 북마크 제거 */
    @DeleteMapping("/{contentId}")
    public ResponseEntity<Void> remove(@CurrentUser User user,
                                       @PathVariable String contentId) {
        bookmarkService.remove(user, contentId);
        return ResponseEntity.noContent().build();
    }

    /* -------- 이미지/메타: 단건/배치 -------- */

    /** 단건: /bookmarks/img/{contentId} → { contentId, firstimage, imageUrl, contentTypeId } */
    @GetMapping("/img/{contentId}")
    public ResponseEntity<Map<String, Object>> getOne(@PathVariable String contentId) {
        return ResponseEntity.of(
                bookmarkService.findByContentId(contentId)
                        .map(p -> {
                            String first = p.getFirstimage();
                            String second = p.getFirstimage2();
                            String imageUrl = (first != null && !first.isBlank())
                                    ? first
                                    : (second == null ? "" : second);

                            Map<String, Object> body = new HashMap<>();
                            body.put("contentId", String.valueOf(p.getContentid()));
                            body.put("firstimage", first == null ? "" : first);
                            body.put("imageUrl", imageUrl);
                            // ★ contentTypeId 포함(숫자)
                            if (p.getContenttypeid() != null) {
                                body.put("contentTypeId", p.getContenttypeid());
                            }
                            return body;
                        })
        ); // Optional → 200/404 자동 처리
    }

    /** 배치: POST /bookmarks/images:batchResolve { contentIds: [...] } */
    @PostMapping("/images:batchResolve")
    public ResponseEntity<List<Map<String, Object>>> batch(@RequestBody Map<String, Object> req) {
        @SuppressWarnings("unchecked")
        List<Object> raw = (List<Object>) req.getOrDefault("contentIds", List.of());
        List<String> ids = raw.stream().map(String::valueOf).toList();

        // ★ 이미지 + contentTypeId를 함께 조회
        Map<String, Map<String, Object>> metaMap = bookmarkService.findMetaByContentIds(ids);

        // 요청 순서를 유지해 응답 (contentTypeId 필수)
        List<Map<String, Object>> body = new ArrayList<>();
        for (String id : ids) {
            Map<String, Object> meta = metaMap.get(id);
            if (meta == null) continue;

            Object ct = meta.get("contentTypeId");
            if (!(ct instanceof Number)) {
                // contentTypeId는 필수이므로 누락 시 스킵
                continue;
            }
            String imageUrl = Optional.ofNullable((String) meta.get("imageUrl")).orElse("");

            Map<String, Object> item = new HashMap<>();
            item.put("contentId", id);
            item.put("imageUrl", imageUrl);
            item.put("contentTypeId", ((Number) ct).intValue());
            body.add(item);
        }
        return ResponseEntity.ok(body);
    }
}
