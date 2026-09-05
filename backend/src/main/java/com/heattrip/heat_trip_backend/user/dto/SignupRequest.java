package com.heattrip.heat_trip_backend.user.dto;

import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.constraints.Size;

import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class SignupRequest {
    private String email;
    private String password;
    /** 상한은 {@link User#MAX_NICKNAME_LENGTH} — 이슈 #229. 가입도 무방비였다. */
    @Size(max = User.MAX_NICKNAME_LENGTH,
            message = "닉네임은 " + User.MAX_NICKNAME_LENGTH + "자를 넘을 수 없습니다.")
    private String nickname;

    @Size(max = User.MAX_NAME_LENGTH, message = "이름은 " + User.MAX_NAME_LENGTH + "자를 넘을 수 없습니다.")
    private String name;
    private String gender;

    private String ageGroup;       // "over14" | "under14"

    // 약관 동의 필드는 없다. 동의는 로그인 뒤 PUT /api/consents 로 적는다(#190) — 가입 화면과
    // 동의 화면이 두 번 묻던 것을 한 번으로 줄였다. 옛 클라이언트가 agreeTos 같은 필드를
    // 보내도 무시된다(Jackson 이 모르는 필드를 버린다).
}
