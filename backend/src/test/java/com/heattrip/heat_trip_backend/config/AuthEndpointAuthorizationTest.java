package com.heattrip.heat_trip_backend.config;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

/**
 * 인가 경계 회귀 방어 — 이슈 #23-D.
 *
 * SecurityConfig 의 permitAll 목록에 "/auth/**" 를 통째로 넣으면 회원 탈퇴(DELETE /auth/me)가
 * Spring Security 인가 계층을 거치지 않는다. 계약(docs/04-api/openapi.yaml)이 선언한 401 보장이
 * 실제로는 성립하지 않는 상태였다. 이 테스트는 그 상태로 되돌아가면 빨간불이 된다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class AuthEndpointAuthorizationTest extends AbstractMySqlIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JWTProvider jwtProvider;

    @Test
    @DisplayName("토큰 없는 회원 탈퇴(DELETE /auth/me)는 401 로 거부된다")
    void deleteMe_withoutToken_isUnauthorized() throws Exception {
        int status = mockMvc.perform(delete("/auth/me"))
                .andReturn().getResponse().getStatus();

        assertThat(status).isEqualTo(401);
    }

    @Test
    @DisplayName("토큰 없는 프로필 수정(PUT /auth/me)은 401 로 거부된다")
    void updateMe_withoutToken_isUnauthorized() throws Exception {
        int status = mockMvc.perform(put("/auth/me")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"보리아빠\"}"))
                .andReturn().getResponse().getStatus();

        assertThat(status).isEqualTo(401);
    }

    @Test
    @DisplayName("토큰 없는 내 정보 조회(GET /auth/me)는 401 로 거부된다")
    void me_withoutToken_isUnauthorized() throws Exception {
        int status = mockMvc.perform(get("/auth/me"))
                .andReturn().getResponse().getStatus();

        assertThat(status).isEqualTo(401);
    }

    @Test
    @DisplayName("토큰 없는 로그아웃(POST /auth/logout)은 401 로 거부된다")
    void logout_withoutToken_isUnauthorized() throws Exception {
        int status = mockMvc.perform(post("/auth/logout"))
                .andReturn().getResponse().getStatus();

        assertThat(status).isEqualTo(401);
    }

    @Test
    @DisplayName("회원가입(POST /auth/signup)은 토큰 없이도 인가 계층을 통과한다")
    void signup_withoutToken_isNotBlockedByAuthorization() throws Exception {
        int status = mockMvc.perform(post("/auth/signup")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andReturn().getResponse().getStatus();

        assertThat(status).isNotEqualTo(401);
        assertThat(status).isNotEqualTo(403);
    }

    @Test
    @DisplayName("로그인(POST /auth/login)은 토큰 없이도 인가 계층을 통과한다")
    void login_withoutToken_isNotBlockedByAuthorization() throws Exception {
        // 자격증명이 틀린 요청으로는 이걸 증명할 수 없다 — #10 이후 그건 **401** 이고,
        // 인가 실패도 같은 본문 없는 401 이라 둘을 구별할 수 없다. 대신 읽을 수 없는 본문을
        // 보내 400 을 받는다. 400 은 인가 계층 너머(DispatcherServlet 안)에서만 나온다.
        int status = mockMvc.perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{"))
                .andReturn().getResponse().getStatus();

        assertThat(status)
                .as("인가 계층이 막았다면 컨트롤러 계층의 400 은 나올 수 없다")
                .isEqualTo(400);
    }

}
