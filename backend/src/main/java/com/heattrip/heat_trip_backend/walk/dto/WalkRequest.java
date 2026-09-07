package com.heattrip.heat_trip_backend.walk.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;

/**
 * 계약의 {@code WalkInput} — 이슈 #145.
 *
 * <h2>이 값들은 전부 앱이 스스로 신고한 것이다</h2>
 * <p>서버는 범위를 검사하지만, <b>범위 검사는 "말이 되는 값인가" 만 말하지 "진짜 걸었는가"
 * 는 말해 주지 않는다.</b> 순위표나 보상에 쓰려면 그때 별도의 근거가 필요하다 — 지금은
 * 사용자가 자기 기록을 보는 용도뿐이라 자기 신고로 충분하다.
 *
 * <p>거리를 서버가 경로에서 다시 재는 것({@code ST_Length})은 가능하지만 하지 않는다.
 * GPS 표본이 성기면 실제보다 짧게 나오고, 두 값이 다를 때 무엇을 믿을지 정하지 않았다.
 *
 * @param clientWalkId 앱이 만드는 멱등키(UUID v4 권장). <b>재전송에도 같은 값</b>이어야 한다
 * @param startedAt    시작 시각. <b>오프셋이 있어야 한다</b>({@code ...Z}) — 없으면 400 이다.
 *                     Dart 는 {@code DateTime.toUtc().toIso8601String()} 이 그 모양이다
 * @param path         {@code [[경도, 위도], ...]}. 생략·빈 배열·점 하나면 경로 없이 저장한다
 */
public record WalkRequest(
        @NotNull(message = "어느 반려동물의 산책인지 알려 주세요.")
        Long dogId,

        @NotBlank(message = "산책 식별자가 필요합니다.")
        @Size(min = 8, max = 64, message = "산책 식별자는 8자 이상 64자 이하여야 합니다.")
        String clientWalkId,

        @NotNull(message = "시작 시각이 필요합니다.")
        Instant startedAt,

        Instant endedAt,

        @NotNull(message = "거리가 필요합니다.")
        Integer distanceM,

        @NotNull(message = "소요 시간이 필요합니다.")
        Integer durationS,

        List<List<Double>> path,

        /**
         * 점별 시각 — 시작 시각 기준 델타 초. 이슈 #155.
         *
         * <p><b>{@code path} 와 길이가 같아야 한다.</b> 다르면 400 이다 — 짝이 안 맞는
         * 배열은 어느 점이 언제인지 말해 주지 못하므로 저장할 가치가 없다.
         *
         * <p>{@code path} 가 없으면 이것도 없어야 한다. 경로 없는 시각은 뜻이 없다.
         *
         * <p>일시정지 동안은 초가 안 흐른다 — 앱의 {@code _seconds} 와 같은 규칙이다.
         * 그래서 델타가 건너뛰면 그 사이가 멈춘 구간이라는 것을 화면이 추론할 수 있다.
         */
        List<Integer> pathT,

        @Size(max = 500, message = "메모는 500자를 넘을 수 없습니다.")
        String memo,

        @Size(max = 30, message = "날씨는 30자를 넘을 수 없습니다.")
        String weather,

        /**
         * 어디를 걸었나 — 카탈로그 장소의 출처. {@code kto}·{@code vet}·{@code shop}·
         * {@code trail} 넷 중 하나이거나 없다 (#338).
         *
         * <p>{@link #placeContentId} 와 <b>짝이다.</b> 하나만 보내면 400 이다 — 반쪽짜리
         * 참조는 화면이 그 장소로 갈 수 없어 이름만 있는 것과 같으면서, 있는 척한다.
         */
        @Pattern(regexp = "kto|vet|shop|trail", message = "장소 출처는 kto·vet·shop·trail 중 하나여야 합니다.")
        String placeSource,

        @Size(max = 64, message = "장소 식별자는 64자를 넘을 수 없습니다.")
        String placeContentId,

        /** 화면에 나갈 이름. 카탈로그에 없는 곳은 이것만 보낸다. */
        @Size(max = 120, message = "장소 이름은 120자를 넘을 수 없습니다.")
        String placeName) {

    /** 출처와 id 는 둘 다 있거나 둘 다 없어야 한다. */
    public boolean hasHalfPlaceRef() {
        boolean source = placeSource != null && !placeSource.isBlank();
        boolean contentId = placeContentId != null && !placeContentId.isBlank();
        return source != contentId;
    }
}
