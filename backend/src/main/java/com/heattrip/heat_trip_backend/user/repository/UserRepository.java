package com.heattrip.heat_trip_backend.user.repository;

import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

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


}
