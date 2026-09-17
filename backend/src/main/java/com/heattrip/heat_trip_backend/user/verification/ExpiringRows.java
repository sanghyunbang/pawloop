package com.heattrip.heat_trip_backend.user.verification;

import java.time.LocalDateTime;

/**
 * 시간이 지나면 쓸모가 없어지는 행을 가진 저장소 — 이슈 #635.
 *
 * <p>가입 대기와 비밀번호 재설정이 둘 다 그렇다. 안 지우면 이메일 주소와 <b>비밀번호
 * 해시</b>가 쓸 일이 없는데도 계속 쌓이고, 필요 이상으로 보관하지 않는다는 처리방침과도
 * 어긋난다.
 *
 * <p>인증 흐름은 만료된 행을 <b>덮어쓰기만</b> 한다 — 같은 주소로 다시 오는 사람의 것만
 * 정리되고, 다시 안 오는 사람의 것은 그대로다. 그래서 시간이 지우는 자리가 따로 필요하다.
 *
 * <p>{@link VerificationPurgeScheduler} 가 이 인터페이스를 구현한 빈을 <b>전부</b> 돈다.
 * 새 표를 만들면서 여기를 붙이는 것을 잊으면 그 표만 안 지워지는데, 그건 아무도 못 본다 —
 * 그래서 붙였는지를 검사가 센다.
 */
public interface ExpiringRows {

    /**
     * 만료된 행을 지운다.
     *
     * <p>각 저장소가 자기 엔티티의 JPQL 로 <b>다시 선언한다</b>. 여기서 {@code @Query} 를
     * 달 수 없는 것은 지울 엔티티 이름이 구현마다 다르기 때문이다.
     *
     * @return 지운 행 수
     */
    int deleteExpired(LocalDateTime now);

    /** 로그에 쓸 이름. 무엇이 몇 건 지워졌는지 구분이 안 되면 로그가 쓸모없다. */
    String rowName();
}
