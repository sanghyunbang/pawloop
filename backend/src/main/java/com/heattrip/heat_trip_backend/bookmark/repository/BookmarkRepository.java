package com.heattrip.heat_trip_backend.bookmark.repository;

import com.heattrip.heat_trip_backend.bookmark.entity.Bookmark;
import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;

public interface BookmarkRepository extends JpaRepository<Bookmark, Long> {
    /**
      * 내 북마크를 <b>최신순</b>으로. 이슈 #210({@code Bookmarks-medium-2}).
      *
      * <p>정렬 없이 {@code findByUser} 로 꺼내면 <b>DB 임의 순서</b>다. 앱은 그것을 그대로
      * 믿는다 — {@code bookmark_repository_impl.dart} 가 {@code createdAt} 이 없으면
      * "서버가 준 순서를 신뢰" 하는 분기로 떨어지고, 화면의 "최신순" 이 사실이 아니게 된다.
      *
      * <p>두 축인 이유는 {@code createdAt} 이 같은 값일 수 있어서다 — 같은 초에 둘을 담으면
      * 순서가 매 요청 달라진다. {@code id} 가 그 동률을 깬다({@code Walk}·{@code Post} 목록이
      * 같은 이유로 {@code (createdAt, id)} 다).
      */
     List<Bookmark> findByUserOrderByCreatedAtDescIdDesc(User user);
    Optional<Bookmark> findByUserAndContentId(User user, String contentId);
    void deleteByUserAndContentId(User user, String contentId);
}
