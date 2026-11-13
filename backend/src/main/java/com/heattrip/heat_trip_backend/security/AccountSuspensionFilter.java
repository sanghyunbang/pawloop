package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.moderation.SuspensionStatus;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.Optional;

/**
 * 정지된 사람은 계정 삭제와 로그아웃만 한다 — 이슈 #718 셋째 조각.
 *
 * <h2>범위가 동의 관문과 반대다</h2>
 * <p>{@link ConsentRequiredFilter} 는 {@code /api/**} 에서 인증이 필요한 것만 본다. 동의는 "아직 안 한 것" 이라
 * 게스트에게 열린 것까지 막을 이유가 없어서다. 정지는 다르다 — 운영 정책을 어겨 내보낸 사람이다. 그래서
 * <b>누구인지 아는 요청은 전부</b> 막고 둘만 연다.
 * <ul>
 *   <li>{@code DELETE /auth/me} — 탈퇴. 정지된 사람이 자기 개인정보를 지우지도 못한 채 갇히면 안 된다.</li>
 *   <li>{@code POST /auth/logout} — 로그아웃. 이 기기에서 나갈 수는 있어야 한다.</li>
 * </ul>
 * <p>그래서 {@code /media/**}(사진 올리기)와 {@code PUT /auth/me}(닉네임 바꾸기)도 막히고, 게스트에게 열린 읽기도
 * 토큰을 실어 보내면 막힌다. 토큰을 빼고 보내는 것까지는 막을 수 없지만 그때는 게스트와 같다. 앱은 이 응답을 받는
 * 순간 정지 안내 화면으로 간다.
 *
 * <h2>왜 토큰이 아니라 여기서 막나</h2>
 * <p>정지할 때 refresh 토큰은 전부 폐기한다({@code user.UserSessions}). 그래도 이미 나간 액세스 토큰은 만료 때까지
 * 살아 있다. 정지가 <b>바로</b> 먹으려면 요청마다 정지를 봐야 한다 — 인덱스 한 줄을 읽는 값이다. 캐시를 두지 않는
 * 이유도 같다. 캐시가 있으면 그 시간만큼 정지가 늦는다.
 *
 * <h2>순서</h2>
 * <p>JWT 인증 필터 <b>뒤</b>(누구인지 알아야 한다 — 앞에 두면 아무도 안 막으면서 초록불이다), 동의 관문 <b>앞</b>
 * (정지된 사람에게 "약관에 동의하세요" 를 보여 주지 않는다). {@code SecurityConfig} 가 그 순서로 붙인다.
 * {@code /internal/**} 는 보지 않는다 — 운영자 통로는 사람이 아니라 들어온 문으로 판정한다.
 */
@Component
public class AccountSuspensionFilter extends OncePerRequestFilter {

    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private static final DateTimeFormatter UNTIL =
            DateTimeFormatter.ofPattern("yyyy년 M월 d일 HH:mm", Locale.KOREAN);

    private final SuspensionStatus suspensions;
    private final AuthenticatedUserIds userIds;

    /** 거절 본문 — {@link ConsentRequiredFilter} 와 같은 이유로 빈이 아니라 직접 만든다. */
    private final ErrorBodyWriter errors;

    public AccountSuspensionFilter(SuspensionStatus suspensions, AuthenticatedUserIds userIds,
                                   ObjectMapper objectMapper) {
        this.suspensions = suspensions;
        this.userIds = userIds;
        this.errors = new ErrorBodyWriter(objectMapper);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        if (isOpen(request.getMethod(), request.getRequestURI())) {
            chain.doFilter(request, response);
            return;
        }

        Long userId = userIds.ofCurrentRequest();
        if (userId == null) {
            // 누구인지 모르는 요청 — 막을 사람이 없다. 인증이 필요한 경로라면 시큐리티 설정이 401 을 낸다.
            chain.doFilter(request, response);
            return;
        }

        Optional<SuspensionStatus.Suspension> suspension = suspensions.currentSuspensionOf(userId);
        if (suspension.isEmpty()) {
            chain.doFilter(request, response);
            return;
        }

        // 401 이 아니다 — 토큰은 멀쩡하다. 401 이면 앱이 다시 로그인시키고, 같은 답이 돌아오는 고리가 된다.
        errors.forbidden(response, AccountStateCode.ACCOUNT_SUSPENDED.name(), messageFor(suspension.get()));
    }

    /** 정지돼 있어도 지나가는 요청 — 위 javadoc 의 둘과 운영자 통로. */
    static boolean isOpen(String method, String uri) {
        if (uri == null || uri.startsWith("/internal/")) {
            return true;
        }
        return ("DELETE".equals(method) && "/auth/me".equals(uri))
                || ("POST".equals(method) && "/auth/logout".equals(uri));
    }

    /** 사람이 읽는 문구. 풀리는 시각은 한국 시각으로 적는다 — 이 앱의 사용자는 한국에 있다. */
    static String messageFor(SuspensionStatus.Suspension suspension) {
        String base = "운영 정책 위반으로 이용이 정지된 계정입니다. 계정 삭제와 로그아웃만 할 수 있습니다.";
        if (suspension.endsAt() == null) {
            return base;
        }
        return base + " 정지는 " + UNTIL.format(suspension.endsAt().atZone(KST)) + "(한국 시각)에 풀립니다.";
    }
}
