package com.heattrip.heat_trip_backend.dog.dto;

import jakarta.validation.constraints.NotNull;

/**
 * 프로필 사진 붙이기의 본문 — 계약의 {@code DogAvatarInput} (#448).
 *
 * <p>파일이 아니라 <b>미디어 id</b> 다. 앱은 먼저 {@code POST /media}(PROFILE_IMAGE) 로 올리고 그 id 를
 * 여기 보낸다 — 커뮤니티 글의 사진(#429)과 같은 두 단계라, 업로드 검증(형식·크기)이 한 곳에 산다.
 */
public record DogAvatarRequest(
        @NotNull(message = "mediaId 가 필요합니다.")
        Long mediaId) {
}
