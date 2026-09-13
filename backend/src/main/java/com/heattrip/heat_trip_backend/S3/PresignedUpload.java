package com.heattrip.heat_trip_backend.S3;

import java.net.URL;

/**
 * 서명 PUT 한 장 — 앱이 S3 에 <b>직접</b> 올릴 때 쓴다 (#429).
 *
 * <p>{@code key} 는 저장소가 정한다. 부르는 쪽이 키를 짓게 두면 키 규칙이 두 곳에 산다.
 * {@code url} 은 만료가 있는 서명 URL 이고, 만료 뒤의 PUT 은 S3 가 403 으로 거절한다.
 *
 * <p>이 값이 있다고 파일이 있는 것이 아니다 — 서명은 네트워크를 안 탄다. 올라왔는지는
 * {@link FileStorage#stat} 이 답한다.
 */
public record PresignedUpload(String key, URL url) {
}
