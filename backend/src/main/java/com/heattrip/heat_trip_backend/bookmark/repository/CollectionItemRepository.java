package com.heattrip.heat_trip_backend.bookmark.repository;

import com.heattrip.heat_trip_backend.bookmark.entity.Collection;
import com.heattrip.heat_trip_backend.bookmark.entity.CollectionItem;
import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;

public interface CollectionItemRepository extends JpaRepository<CollectionItem, Long> {
    //  최신순 목록
    List<CollectionItem> findByUserAndCollectionOrderByCreatedAtDesc(User user, Collection collection);
    // 개수
    long countByUserAndCollection(User user, Collection collection);
    //  최신 1건
    Optional<CollectionItem> findTopByUserAndCollectionOrderByCreatedAtDesc(User user, Collection collection);
    // 단건 조회(중복 방지 확인용)
    Optional<CollectionItem> findByUserAndCollectionAndContentId(User user, Collection collection, String contentId);
}
