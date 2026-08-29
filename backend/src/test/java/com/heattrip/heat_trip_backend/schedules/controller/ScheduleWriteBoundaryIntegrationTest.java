package com.heattrip.heat_trip_backend.schedules.controller;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.schedules.entity.Schedule;
import com.heattrip.heat_trip_backend.schedules.repository.ScheduleRepository;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/**
 * 일정 <b>쓰기</b> 경계 — "등록"이 남의 행을 덮어쓰지 않는다는 것과, 응답이 자격증명을 흘리지 않는다는 것.
 *
 * <p>둘 다 이슈 #5 가 만든 결함은 아니지만 #5 가 다시 쓴 메서드 안에 있고, #5 가 인증 주체 해석을
 * 고치면서 <b>도달 가능한 사용자층이 넓어졌다</b> — 그전에는 소셜 계정이 이 컨트롤러에서 400 으로
 * 튕겨 로컬 가입 계정만 악용할 수 있었지만 이제 모든 계정이 들어온다. 그래서 함께 잠근다.
 *
 * <p>왜 통합 테스트인가: 첫 번째 결함의 본질은 {@code JpaRepository.save} 가 id 유무에 따라
 * insert 와 merge 로 갈린다는 <b>영속성 계층의 사실</b>이다. 서비스를 목으로 세우면
 * {@code save(schedule)} 가 호출됐다는 것만 확인하고 초록불이 된다 — 정확히 놓쳤던 자리다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} 두 줄뿐인 것은 의도다.
 * {@code AuthMeIntegrationTest} 와 같아야 스프링 컨텍스트 캐시를 공유한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class ScheduleWriteBoundaryIntegrationTest {

    /** 실제 BCrypt 해시와 같은 모양의 가짜 값. 진짜 비밀번호가 아니다. */
    private static final String FAKE_BCRYPT_HASH =
            "$2a$10$AAAAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private ScheduleRepository scheduleRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @Test
    @DisplayName("남의 scheduleId 를 실어 일정을 등록해도 그 행은 덮어써지지 않고 새 행이 하나 더 생긴다")
    void 요청본문의_scheduleId로는_남의_일정을_덮어쓸_수_없다() throws Exception {
        User victim = seedUser("victim@example.com");
        User attacker = seedUser("attacker@example.com");
        Schedule victimSchedule = seedSchedule(victim, "피해자-원본");
        long before = scheduleRepository.count();

        // 공격자의 토큰으로, 피해자의 행 id 를 그대로 실어 "등록"한다.
        String body = """
                {"scheduleId": %d, "title": "탈취됨", "content": "덮어쓰기",
                 "dateFrom": "2026-09-01", "dateTo": "2026-09-02"}
                """.formatted(victimSchedule.getScheduleId());

        mockMvc.perform(post("/public/schedules")
                        .header("Authorization", "Bearer " + tokenFor(attacker))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andReturn();

        Schedule reloaded = scheduleRepository.findById(victimSchedule.getScheduleId()).orElseThrow();
        assertThat(reloaded.getTitle())
                .as("JpaRepository.save 는 id 가 실려 있으면 insert 가 아니라 merge 다 — "
                        + "요청 본문의 id 를 그대로 믿으면 '등록'이 남의 행 덮어쓰기가 된다")
                .isEqualTo("피해자-원본");
        assertThat(reloaded.getUser().getId())
                .as("소유자까지 공격자로 바뀌면 피해자는 자기 일정을 되찾을 수단이 없다")
                .isEqualTo(victim.getId());
        assertThat(scheduleRepository.count())
                .as("등록은 언제나 행을 하나 늘린다. 개수가 그대로면 덮어쓴 것이다")
                .isEqualTo(before + 1);
    }

    @Test
    @DisplayName("일정 등록 응답에 작성자의 비밀번호 해시가 실리지 않는다")
    void 일정등록_응답은_비밀번호해시를_담지_않는다() throws Exception {
        User me = seedUser("bori@example.com");

        MvcResult result = mockMvc.perform(post("/public/schedules")
                        .header("Authorization", "Bearer " + tokenFor(me))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"title": "보리 산책", "content": "한강",
                                 "dateFrom": "2026-09-01", "dateTo": "2026-09-01"}
                                """))
                .andReturn();

        String body = result.getResponse().getContentAsString(StandardCharsets.UTF_8);

        assertThat(result.getResponse().getStatus())
                .as("응답을 못 받으면 아래 단언이 조용히 통과한다")
                .isEqualTo(200);
        assertThat(body)
                .as("이 응답은 Schedule 엔티티를 통째로 직렬화하고 Schedule.user 는 User 엔티티다 — "
                        + "User.password 에 @JsonIgnore 가 없으면 로그인 비밀번호의 BCrypt 해시가 그대로 나간다")
                .doesNotContain("password")
                .doesNotContain(FAKE_BCRYPT_HASH)
                .doesNotContain("$2a$");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private User seedUser(String email) {
        return userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email(email)
                .password(FAKE_BCRYPT_HASH)
                .name("보리아빠")
                .nickname("보리아빠")
                .build());
    }

    private Schedule seedSchedule(User owner, String title) {
        return scheduleRepository.save(Schedule.builder()
                .user(owner)
                .title(title)
                .content("원본 내용")
                .dateFrom(LocalDate.of(2026, 8, 1))
                .dateTo(LocalDate.of(2026, 8, 2))
                .build());
    }

    private String tokenFor(User user) {
        return jwtProvider.createAccessToken(user.getId(), user.getRole());
    }
}
