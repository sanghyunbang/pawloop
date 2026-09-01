package com.heattrip.heat_trip_backend.walk.dto;

import jakarta.validation.constraints.Size;

/**
 * 산책 회고 글 교체 — 이슈 #187. {@code PUT /api/walks/{walkId}/memo} 의 본문.
 *
 * <h2>왜 {@code PATCH /api/walks/{walkId}} 가 아닌가</h2>
 * <p>PATCH 는 <b>"필드를 안 보냈다"</b> 와 <b>"null 로 지워라"</b> 를 구분해야 하는데,
 * 자바 레코드로 받으면 {@code {}} 와 {@code {"memo":null}} 이 똑같이 {@code null} 이다.
 * 구분하려면 {@code Optional} 을 감싼 래퍼나 커스텀 역직렬화가 필요하고, 그 복잡도는
 * 바꿀 필드가 하나뿐인 지금 값을 못 한다.
 *
 * <p>하위 리소스 PUT 이면 뜻이 하나다 — <b>"메모를 이 값으로 바꾼다"</b>.
 * {@code PUT /api/groups/{groupId}/walk-notes} 가 같은 모양이고 같은 이유로 그렇게 정해졌다.
 *
 * <h2>빈 문자열은 정상 요청이다</h2>
 * <p>"다 지웠다" 는 사용자의 정당한 의사다. 400 으로 막으면 한 번 쓴 글을 영영 못 지운다.
 * 엔티티({@link com.heattrip.heat_trip_backend.walk.entity.Walk#rewriteMemo})가 이것을
 * {@code null} 로 눕혀 "안 썼다" 의 모양을 하나로 유지한다.
 *
 * @param memo 새 회고 글. {@code null} 이나 빈 문자열이면 지운다.
 */
public record WalkMemoRequest(
        @Size(max = 500, message = "메모는 500자를 넘을 수 없습니다.")
        String memo) {}
