package com.heattrip.heat_trip_backend.bookmark.repository;

import com.heattrip.heat_trip_backend.bookmark.entity.Collection;
import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;

public interface CollectionRepository extends JpaRepository<Collection, Long> {
    List<Collection> findByUserOrderByCreatedAtDesc(User user);
    Optional<Collection> findByUserAndName(User user, String name);
}
