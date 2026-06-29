package com.heattrip.heat_trip_backend.bookmark.service;

import com.heattrip.heat_trip_backend.bookmark.entity.Collection;
import com.heattrip.heat_trip_backend.bookmark.entity.CollectionItem;
import com.heattrip.heat_trip_backend.bookmark.repository.CollectionItemRepository;
import com.heattrip.heat_trip_backend.bookmark.repository.CollectionRepository;
import com.heattrip.heat_trip_backend.user.entity.User;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service
@RequiredArgsConstructor
public class CollectionService {

    private final CollectionRepository collectionRepository;
    private final CollectionItemRepository itemRepository;

    /** 내 컬렉션 전체 */
    public List<Collection> findAll(User user) {
        return collectionRepository.findByUserOrderByCreatedAtDesc(user);
    }

    /** 단건 조회(권한 체크 포함) */
    public Collection getOwned(User user, Long collectionId) {
        Collection c = collectionRepository.findById(collectionId)
                .orElseThrow(() -> new IllegalArgumentException("Collection not found: " + collectionId));
        if (!c.getUser().getId().equals(user.getId())) {
            throw new IllegalArgumentException("권한이 없습니다.");
        }
        return c;
    }

    /** 생성 (이름 중복 방지) */
    @Transactional
    public Collection create(User user, String name) {
        if (name == null || name.isBlank()) throw new IllegalArgumentException("name is required");
        collectionRepository.findByUserAndName(user, name).ifPresent(x -> {
            throw new IllegalArgumentException("이미 존재하는 컬렉션 이름입니다.");
        });
        Collection c = Collection.builder().user(user).name(name.trim()).build();
        return collectionRepository.save(c);
    }

    /** 이름 변경 */
    @Transactional
    public Collection rename(User user, Long collectionId, String newName) {
        Collection c = getOwned(user, collectionId);
        if (newName == null || newName.isBlank()) throw new IllegalArgumentException("name is required");
        // 같은 사용자 내 중복 방지
        collectionRepository.findByUserAndName(user, newName.trim()).ifPresent(x -> {
            if (!x.getId().equals(collectionId))
                throw new IllegalArgumentException("이미 존재하는 컬렉션 이름입니다.");
        });
        c.setName(newName.trim());
        return collectionRepository.save(c);
    }

    /** 삭제 (아이템은 OnDelete CASCADE) */
    @Transactional
    public void delete(User user, Long collectionId) {
        Collection c = getOwned(user, collectionId);
        collectionRepository.delete(c);
    }

    /** 아이템 목록 */
    public List<CollectionItem> items(User user, Long collectionId) {
        Collection c = getOwned(user, collectionId);
        return itemRepository.findByUserAndCollectionOrderByCreatedAtDesc(user, c);
    }

    /** 아이템 추가 (중복 방지) */
    @Transactional
    public void addItem(User user, String collectionIdString, String contentId) {
        Long collectionId = Long.valueOf(collectionIdString);
        Collection c = getOwned(user, collectionId);
        itemRepository.findByUserAndCollectionAndContentId(user, c, contentId)
                .orElseGet(() -> itemRepository.save(
                        CollectionItem.builder().user(user).collection(c).contentId(contentId).build()
                ));
    }

    /** 아이템 제거 */
    @Transactional
    public void removeItem(User user, Long collectionId, String contentId) {
        Collection c = getOwned(user, collectionId);
        itemRepository.findByUserAndCollectionAndContentId(user, c, contentId)
                .ifPresent(itemRepository::delete);
    }

    /** 개수/최신아이템 contentId 헬퍼 */
    public record Stats(long count, String latestContentId) {}
    public Stats stats(User user, Collection c) {
        List<CollectionItem> items = itemRepository.findByUserAndCollectionOrderByCreatedAtDesc(user, c);
        long count = items.size();
        String latest = items.isEmpty() ? null : items.get(0).getContentId(); // 정렬이 필요하면 createdAt 추가
        return new Stats(count, latest);
    }
}
