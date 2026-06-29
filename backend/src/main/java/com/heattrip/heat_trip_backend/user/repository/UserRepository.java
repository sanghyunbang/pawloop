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
    Optional<User> findByUsername(String username);

    // nickname으로 사용자 조회
    // SQL 없이 자동으로 쿼리 메소드 생성: SELECT * FROM users WHERE nickname = ?
    Optional<User> findByNickname(String nickname);

    // email로 사용자 조회
    // SQL 없이 자동으로 쿼리 메소드 생성: SELECT * FROM users WHERE email = ?
    Optional<User> findByEmail(String email);


}
