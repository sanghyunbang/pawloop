package com.heattrip.heat_trip_backend.walk.course;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * 코스로 남기기 — 이슈 #339. 계약의 {@code CourseInput}.
 *
 * <p>선을 앱이 보내지 않는다. <b>서버가 그 산책의 선을 베껴 와 자른다</b> — 앱이 보낸 선을
 * 그대로 믿으면 "잘라 냈다" 는 약속을 앱 버전마다 다시 지켜야 하고, 옛 앱 하나가 안 자르면
 * 그 사람의 집 앞이 공개된다.
 *
 * @param walkId     어느 산책을 코스로 만들 것인가. 내 산책이 아니면 404
 * @param name       코스 이름
 * @param note       한 줄 소개
 * @param tags       반려견 관점 — {@code leash}·{@code poopbag}·{@code shade} 중에서
 * @param visibility {@code private}(기본) 또는 {@code public}
 */
public record CourseRequest(
        @NotNull(message = "어느 산책을 코스로 만들지 알려 주세요.")
        Long walkId,

        @NotBlank(message = "코스 이름이 필요합니다.")
        @Size(max = 60, message = "코스 이름은 60자를 넘을 수 없습니다.")
        String name,

        @Size(max = 200, message = "소개는 200자를 넘을 수 없습니다.")
        String note,

        List<@Pattern(regexp = "leash|poopbag|shade",
                message = "태그는 leash·poopbag·shade 중에서 고릅니다.") String> tags,

        @Pattern(regexp = "private|public", message = "공개 범위는 private 또는 public 입니다.")
        String visibility) {
}
