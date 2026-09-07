package com.heattrip.heat_trip_backend.user.dto;

import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import lombok.*;

import java.util.List;

/**
 * 프로필 부분 수정. <b>{@code null} 은 "안 바꿈"</b> 이다.
 *
 * <h2>상한이 여기 있는 이유 — 이슈 #229</h2>
 * <p>2026-09-03 이전에는 이 클래스에 애노테이션이 하나도 없었고, 컨트롤러에
 * {@code @Valid} 조차 없어서 <b>붙여도 안 걸리는</b> 상태였다. 앱의 편집 화면이 20 으로
 * 막지만 그건 한 화면의 클라이언트 상한이지 방어선이 아니다 — 소셜 로그인은 앱을 아예
 * 안 지난다.
 *
 * <p>닉네임은 {@code post.handle}·{@code chat_message.sender_name} 이 스냅샷하고 가족·케어가
 * 표시하는 값이라, 여기가 열려 있으면 그 전부가 열려 있다. #170 에서 실제로 터졌다.
 */
@Getter @Setter
@NoArgsConstructor @AllArgsConstructor
public class UpdateProfileRequest {
    @Size(max = User.MAX_NAME_LENGTH, message = "이름은 " + User.MAX_NAME_LENGTH + "자를 넘을 수 없습니다.")
    private String name;        // null 이면 미수정

    @Size(max = User.MAX_NICKNAME_LENGTH,
            message = "닉네임은 " + User.MAX_NICKNAME_LENGTH + "자를 넘을 수 없습니다.")
    private String nickname;    // null 이면 미수정
    private String gender;      // FEMALE/MALE/OTHER (null/이상값이면 미수정 or OTHER로)
    private Integer age;        // null 이면 미수정
    private String travelType;  // null 이면 미수정
    private String imageUrl;    // null 이면 미수정 (S3 URL)

    /**
     * 내가 고른 동네의 행정동 코드 열 자리 — 이슈 #342.
     *
     * <p>{@code null} 은 이 클래스의 규칙대로 <b>안 바꿈</b>이고, <b>빈 문자열이면 지운다</b> —
     * "동네 안 쓸래" 를 표현할 방법이 있어야 한다.
     *
     * <p>모양만 여기서 막고, <b>있는 시군구인지는 서버가 표로 확인한다</b>
     * ({@code NeighborhoodCatalog}). 이름을 본문으로 받지 않는 이유도 같다 — 받으면
     * 아무나 자기 동네를 "청와대" 라고 적어 글 카드에 띄울 수 있다.
     */
    @Pattern(regexp = "|[0-9]{10}", message = "동네 코드는 열 자리 숫자입니다.")
    private String neighborhoodCode;

    // 마케팅 동의 변경은 여기 없다 — PUT /api/consents 에 MARKETING 행을 적는다(#190).
}
