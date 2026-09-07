/**
 * 산책 안전 지수의 재료 — 기상청 초단기실황과 에어코리아 미세먼지를 <b>서버가 대신</b> 부른다 (#336).
 *
 * <p>앱은 5km 격자 번호(nx, ny)만 보낸다. 위경도는 오지 않고, 요청은 인증 없이 오며(누구의
 * 격자인지 모른다), 응답은 격자별로 10분 캐시된다 — 저장하는 것이 없다. 키를 앱에 두지 않는
 * 이유는 #40 과 같다: 바이너리에 남고, 폐기하려면 앱을 새로 배포해야 한다.
 *
 * <p>판정(좋아요·짧게·피하세요·추워요)은 <b>앱이</b> 한다 — 아이의 품종·나이·크기가 앱에 있고,
 * 서버는 관측값만 준다. 규칙은 {@code app/lib/v2/data/walk_safety.dart}.
 */
@ApplicationModule(displayName = "WalkSafety", allowedDependencies = {})
package com.heattrip.heat_trip_backend.walksafety;

import org.springframework.modulith.ApplicationModule;
