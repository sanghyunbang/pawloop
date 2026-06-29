package com.heattrip.heat_trip_backend.bookmark.repository;

import com.heattrip.heat_trip_backend.bookmark.entity.Bookmark;
import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;

public interface BookmarkRepository extends JpaRepository<Bookmark, Long> {
    List<Bookmark> findByUser(User user);
    Optional<Bookmark> findByUserAndContentId(User user, String contentId);
    void deleteByUserAndContentId(User user, String contentId);
}
