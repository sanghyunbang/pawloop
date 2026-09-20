package com.heattrip.heat_trip_backend.consent.repository;

import com.heattrip.heat_trip_backend.consent.entity.UserConsent;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
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

    /**
     * {@code userIds} 중 {@code kinds} 의 문서 <b>전부에 동의한 행이 있는</b> 계정 — 이슈 #660 완료 조건 4.
     * {@code ConsentService.among} 이 필수 셋을 넣어 부르고, 받은 id 를 빼서 "하나라도 빠진 계정" 을 만든다.
     *
     * <p><b>"한 번이라도 동의했는가" 를 센다.</b> {@code agreed = true} 인 행의 종류를 세므로 나중에
     * 철회({@code agreed = false}) 행이 쌓여도 그 종류는 센 채로 남는다 — 철회한 사람은 "다 동의한 쪽" 에
     * 남는다. "지금 상태" 는 {@code findByUserIdOrderByIdDesc} 로 서비스가 따로 고른다. 두 질문이 다른
     * 이유는 {@code user.UnconsentedAccounts} 의 javadoc 에 있다.
     *
     * <p><b>이 표만 본다.</b> "유예가 지난 계정" 을 여기서 {@code User} 를 조인해 한 문장으로 묻는 편이
     * 짧지만, 그러면 이 모듈이 {@code users} 스키마에 묶인다 — {@code CrossModuleQueryJoinsTest} 가
     * 그런 쿼리를 세고 있고 기준선에는 원자성이 필요한 {@code walk → dog} 하나뿐이다. 그래서 id 를
     * 받는다({@code user} 가 한 장씩 넘긴다). {@code idx_user_consent_user(user_id, id)} 를 탄다.
     */
    @Query("""
            select c.userId from UserConsent c
            where c.userId in :userIds and c.agreed = true and c.kind in :kinds
            group by c.userId
            having count(distinct c.kind) = :kindCount
            """)
    List<Long> findUserIdsHavingAgreedToAllOf(@Param("userIds") Collection<Long> userIds,
                                              @Param("kinds") Collection<String> kinds,
                                              @Param("kindCount") long kindCount);
}
