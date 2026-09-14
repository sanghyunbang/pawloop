package com.heattrip.heat_trip_backend.walk.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.stream.Stream;

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

        /**
         * 함께 나간 아이들 — 이슈 #343. <b>안 보내도 된다.</b>
         *
         * <p>안 보내면 {@link #dogId} 하나로 본다. 이미 나가 있는 앱이 이 필드를 모르고,
         * 그 앱의 산책이 400 이 되면 안 된다 — 하위 호환은 <b>서버가 지는 짐</b>이다.
         *
         * <p>{@link #dogId} 가 목록에 없으면 서버가 <b>맨 앞에 넣는다.</b> 대표 아이를
         * 빼고 보내는 것은 앱의 실수이지 "그 아이는 안 갔다" 는 뜻이 아니다 —
         * {@code walk.dog_id} 는 어차피 그 값으로 저장된다.
         *
         * <p>최대 열 마리다. 실제로 한 사람이 열 마리를 한 번에 데리고 나가는 일은 없고,
         * 상한이 없으면 한 요청이 이음매 행 수천 개를 만들 수 있다.
         */
        @Size(max = 10, message = "함께 나간 아이는 10마리까지입니다.")
        List<@NotNull(message = "아이 식별자가 비었습니다.") Long> dogIds,

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
        String placeName,

        /**
         * 산책 중 찍은 사진(#450) — {@code POST /media} 에 {@code WALK_IMAGE} 로 올린 것의 id.
         * 안 보내면 없는 것이다. 내가 올렸고 아직 어디에도 안 붙은 것만 붙는다 — 남의 것 · 이미 붙은
         * 것이 섞이면 400 이고 그때 산책도 안 생긴다(글과 같은 규칙, {@code MediaAttachment}).
         */
        @Size(max = MAX_MEDIA, message = "사진은 한 산책에 " + MAX_MEDIA + "장까지 붙일 수 있습니다.")
        List<Long> mediaIds) {

    /** 한 산책에 붙는 사진 상한 — 글({@code PostRequest.MAX_MEDIA})과 같다. */
    public static final int MAX_MEDIA = 10;

    /** {@code null} 이면 빈 목록 — 붙이기가 {@code null} 을 안 받게. */
    public List<Long> mediaIdsOrEmpty() {
        return mediaIds == null ? List.of() : mediaIds;
    }

    /**
     * 실제로 저장할 아이들 — 대표 아이가 맨 앞이고 중복이 없다 (#343).
     *
     * <p>앱이 {@code dogIds} 를 안 보냈으면 대표 아이 하나짜리 목록이다.
     */
    public List<Long> resolvedDogIds() {
        List<Long> given = dogIds == null ? List.of() : dogIds;
        return Stream.concat(Stream.of(dogId), given.stream())
                .filter(Objects::nonNull)
                .distinct()
                .toList();
    }

    /** 출처와 id 는 둘 다 있거나 둘 다 없어야 한다. */
    public boolean hasHalfPlaceRef() {
        boolean source = placeSource != null && !placeSource.isBlank();
        boolean contentId = placeContentId != null && !placeContentId.isBlank();
        return source != contentId;
    }
}
