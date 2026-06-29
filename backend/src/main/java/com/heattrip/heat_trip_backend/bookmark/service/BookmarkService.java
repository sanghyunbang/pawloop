// src/main/java/com/heattrip/heat_trip_backend/bookmark/service/BookmarkService.java
package com.heattrip.heat_trip_backend.bookmark.service;

import com.heattrip.heat_trip_backend.bookmark.entity.Bookmark;
import com.heattrip.heat_trip_backend.bookmark.repository.BookmarkRepository;
import com.heattrip.heat_trip_backend.bookmark.repository.PlaceImgRepository;
import com.heattrip.heat_trip_backend.bookmark.service.CollectionService;

import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.user.entity.User;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class BookmarkService {

    private final BookmarkRepository bookmarkRepository;
    private final CollectionService collectionService;
    private final PlaceImgRepository placeImgRepository;

    /** 내 북마크 전체 */
    public List<Bookmark> findAll(User user) {
        return bookmarkRepository.findByUser(user);
    }

    /** 북마크 추가 (중복 방지) + 선택적으로 컬렉션에도 추가 */
    @Transactional
    public void add(User user, String contentId, String collectionIdOrNull) {
        bookmarkRepository.findByUserAndContentId(user, contentId)
                .orElseGet(() -> bookmarkRepository.save(
                        Bookmark.builder().user(user).contentId(contentId).build()
                ));
        if (collectionIdOrNull != null && !collectionIdOrNull.isBlank()) {
            collectionService.addItem(user, collectionIdOrNull, contentId);
        }
    }

    /** 북마크 제거 (컬렉션 아이템은 유지) */
    @Transactional
    public void remove(User user, String contentId) {
        bookmarkRepository.deleteByUserAndContentId(user, contentId);
    }

    /* -------------------- 이미지/메타 조회 -------------------- */

    /** 문자열 contentId → Long 파싱 후 Place 조회 */
    public Optional<Place> findByContentId(String contentId) {
        try {
            long id = Long.parseLong(contentId);
            return placeImgRepository.findById(id);
        } catch (NumberFormatException e) {
            return Optional.empty();
        }
    }

    /** ★ 신규: 여러 contentId → {imageUrl, contentTypeId} 메타 맵(키: contentId) */
    public Map<String, Map<String, Object>> findMetaByContentIds(List<String> ids) {
        Map<String, Map<String, Object>> result = new HashMap<>();
        if (ids == null || ids.isEmpty()) return result;

        List<Long> longIds = ids.stream().map(s -> {
            try { return Long.parseLong(s); } catch (Exception e) { return null; }
        }).filter(Objects::nonNull).collect(Collectors.toList());

        if (longIds.isEmpty()) return result;

        List<Place> rows = placeImgRepository.findAllById(longIds);

        for (Place p : rows) {
            String key = String.valueOf(p.getContentid());
            String url = Optional.ofNullable(preferFirstimage(p)).orElse("");

            Integer contentTypeId = toInt(p.getContenttypeid());

            Map<String, Object> meta = new HashMap<>();
            meta.put("imageUrl", url);               // 빈 문자열 허용
            if (contentTypeId != null) {
                meta.put("contentTypeId", contentTypeId); // 숫자
            }
            result.put(key, meta);
        }
        return result;
    }

    private String preferFirstimage(Place p) {
        if (p.getFirstimage() != null && !p.getFirstimage().isBlank()) return p.getFirstimage();
        if (p.getFirstimage2() != null && !p.getFirstimage2().isBlank()) return p.getFirstimage2();
        return null;
    }

    // 👇 추가: 어떤 타입이 와도 int로 안전 변환
    private Integer toInt(Object v) {
        if (v == null) return null;
        if (v instanceof Number n) return n.intValue();
        try {
            String s = v.toString().trim();
            if (s.isEmpty()) return null;
            return Integer.valueOf(s);
        } catch (Exception ignore) {
            return null;
        }
    }
}
