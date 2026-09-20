package com.heattrip.heat_trip_backend.consent.repository;

import com.heattrip.heat_trip_backend.consent.entity.UserConsent;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
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
     * {@code createdBefore} 보다 먼저 만들어진 계정 중 {@code kinds} 의 문서에 <b>동의한 행이 있는 종류</b>가
     * {@code kindCount} 개에 못 미치는 것 — 이슈 #660 완료 조건 4. {@code ConsentService.idsCreatedBefore}
     * 가 필수 셋을 넣어 부른다.
     *
     * <p><b>"한 번이라도 동의했는가" 를 센다.</b> {@code agreed = true} 인 행의 종류를 세므로 나중에
     * 철회({@code agreed = false}) 행이 쌓여도 그 종류는 센 채로 남는다 — 철회한 사람은 여기 안 나온다.
     * "지금 상태" 는 {@code findByUserIdOrderByIdDesc} 로 서비스가 따로 고른다. 두 질문이 다른 이유는
     * {@code user.UnconsentedAccounts} 의 javadoc 에 있다.
     *
     * <p>{@code User} 를 이 저장소에서 부르는 것은 JPQL 의 엔티티 이름이다 — {@code consent} 는
     * {@code user :: entity} 를 열어 두고 있어 경계 안이다. 자바 쪽에서 계정 목록을 받아 걸러내지 않는
     * 이유: 유예가 지난 계정은 곧 가입자 거의 전부라, 그렇게 하면 밤마다 사용자 수만큼 쿼리가 나간다.
     * {@code created_at} 이 비어 있는 행은 {@code <} 비교가 거짓이라 <b>안 나온다</b> — 언제 만들어졌는지
     * 모르는 계정을 지우지 않는다.
     */
    @Query("""
            select u.id from User u
            where u.createdAt < :createdBefore
              and (select count(distinct c.kind) from UserConsent c
                   where c.userId = u.id and c.agreed = true and c.kind in :kinds) < :kindCount
            order by u.id
            """)
    List<Long> findUserIdsCreatedBeforeLackingAnyAgreed(@Param("createdBefore") LocalDateTime createdBefore,
                                                        @Param("kinds") Collection<String> kinds,
                                                        @Param("kindCount") long kindCount);
}
