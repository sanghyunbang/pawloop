package com.heattrip.heat_trip_backend.user.repository;

import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.Optional;

// JPA Repository 인터페이스 : 자동으로 DB 접근
public interface UserRepository extends JpaRepository<User, Long> {

    // JpaRepostory<엔티티, ID 타입>를 상속받아 기본적인 CRUD 메서드를 제공
    // User: 관리 대상 엔티티 클래스
    // Long: 엔티티의 기본 키(pk) 타입

    // username으로 사용자 조회
    // SQL 없이 자동으로 쿼리 메소드 생성: SELECT * FROM users WHERE username = ?
    //
    // ⚠️ 소셜 로그인 식별에 이걸 쓰지 마라. 아래 findByProviderAndSocialId 가 정본이다. (이슈 #7)
    // 백필 SQL 이 아직 돌지 않은 레거시 행("{provider}_{socialId}")을 한 번 찾아
    // 새 컬럼으로 옮겨 심을 때만 쓴다.
    Optional<User> findByUsername(String username);

    /**
     * 소셜 계정 식별의 정본. (provider, social_id) 는 DB 에서 UNIQUE 다.
     *
     * <p>이메일로 찾지 않는 이유: 카카오는 이메일을 주지 않을 수 있고(선택 동의),
     * 같은 사람이 나중에 이메일 동의를 켜면 값이 null → 실제 주소로 바뀐다.
     * 시간에 따라 변하는 값은 식별 키가 될 수 없다.
     */
    Optional<User> findByProviderAndSocialId(String provider, String socialId);

    // nickname으로 사용자 조회
    // SQL 없이 자동으로 쿼리 메소드 생성: SELECT * FROM users WHERE nickname = ?
    Optional<User> findByNickname(String nickname);

    // email로 사용자 조회
    // SQL 없이 자동으로 쿼리 메소드 생성: SELECT * FROM users WHERE email = ?
    Optional<User> findByEmail(String email);

    /**
     * 이 id 들 중 <b>아직 살아 있는 것</b>. 엔티티를 안 읽고 id 만 가져온다. (이슈 #82)
     *
     * <p>탈퇴한 사용자의 닉네임이 커뮤니티 카드·댓글에 계속 뜨는 것을 막으려면 "이 id 가
     * 아직 있는가" 를 물어야 한다. 그런데 필요한 것은 <b>존재 여부뿐</b>이라 엔티티를 통째로
     * 읽을 이유가 없다 — 카드 100건이면 사용자도 최대 100명이고, 그만큼의 행을 영속성
     * 컨텍스트에 올리는 것은 순수한 낭비다.
     *
     * <p>한 번에 묻는 것이 핵심이다. id 마다 따로 물으면 N+1 이고, 그건 이 서비스가 이미
     * 리액션·댓글 수에서 피해 둔 모양이다.
     */
    @Query("select u.id from User u where u.id in :ids")
    List<Long> findExistingIds(@Param("ids") Collection<Long> ids);

    /**
     * {@code createdBefore} 보다 먼저 만들어진 계정의 id 를 {@code afterId} <b>다음부터</b> id 순으로 한 장 —
     * 이슈 #660 완료 조건 4. {@code UnconsentedAccountSweeper} 가 유예 지난 계정을 한 장씩 훑는 자리다.
     *
     * <p><b>키셋 페이징이다.</b> 오프셋으로 넘기면 앞 장의 계정을 지운 만큼 다음 장이 앞으로 밀려 건너뛴다.
     * "마지막으로 본 id 뒤" 로 넘기면 지워도 안 밀린다. 엔티티를 안 읽고 id 만 가져오는 이유는
     * {@link #findExistingIds} 와 같다 — 필요한 것이 id 뿐이다.
     *
     * <p>{@code created_at} 이 비어 있는 행은 {@code <} 비교가 거짓이라 <b>안 나온다</b> — 언제 만들어졌는지
     * 모르는 계정은 거두지 않는다.
     *
     * @param page 장 크기만 쓴다({@code PageRequest.of(0, n)}). 정렬은 쿼리가 정한다
     */
    @Query("select u.id from User u where u.createdAt < :createdBefore and u.id > :afterId order by u.id")
    List<Long> findIdsCreatedBefore(@Param("createdBefore") LocalDateTime createdBefore,
                                    @Param("afterId") long afterId,
                                    Pageable page);


}
