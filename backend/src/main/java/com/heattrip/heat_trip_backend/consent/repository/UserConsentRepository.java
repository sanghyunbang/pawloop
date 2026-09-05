package com.heattrip.heat_trip_backend.consent.repository;

import com.heattrip.heat_trip_backend.consent.entity.UserConsent;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

/** 동의 이력 — 이슈 #190. */
public interface UserConsentRepository extends JpaRepository<UserConsent, Long> {

    /**
     * 이 계정의 행 전부, 최신이 앞. 문서별 "지금 상태" 는 서비스가 여기서 첫 행을 고른다.
     *
     * <p>계정당 행이 문서 수 × 버전 수라 수십을 넘지 않는다 — 쿼리 안에서 문서별 최신을
     * 고르는 복잡한 JPQL 보다 다 읽고 고르는 쪽이 읽기 쉽고 틀리기 어렵다.
     */
    List<UserConsent> findByUserIdOrderByIdDesc(Long userId);
}
