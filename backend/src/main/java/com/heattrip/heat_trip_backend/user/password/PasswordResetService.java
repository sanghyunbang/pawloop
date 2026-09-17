package com.heattrip.heat_trip_backend.user.password;

import com.heattrip.heat_trip_backend.user.UserTime;
import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.mail.MailProperties;
import com.heattrip.heat_trip_backend.user.mail.Mailer;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;
import com.heattrip.heat_trip_backend.user.service.UserService;
import com.heattrip.heat_trip_backend.user.verification.VerificationAttempts;
import com.heattrip.heat_trip_backend.user.verification.VerificationCodes;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.Locale;

/**
 * 비밀번호 재설정 — 이슈 #635 조각 ③.
 *
 * <h2>가입 여부를 말하지 않는다</h2>
 * <p>{@link #request} 는 <b>그런 주소가 없어도 같은 202</b> 를 준다. 재설정 요청은 계정
 * 존재를 묻기에 가장 편한 문이다 — 로그인은 비밀번호가 있어야 하지만 여기는 주소만
 * 넣으면 되기 때문이다.
 *
 * <p>그래서 이 경로는 <b>응답 본문이 없다.</b> 가입 인증({@code /auth/signup})이
 * {@code mailSent} 를 돌려주는 것과 다른데, 거기는 두 갈래가 모두 메일을 보내므로 그 값이
 * 아무것도 가리지 않는다. 여기서는 없는 주소에 메일을 안 보내므로, 참이든 거짓이든
 * <b>그 값 자체가 답이 된다.</b>
 *
 * <h2>바꾸고 나면 다른 기기를 끊는다</h2>
 * <p>재설정을 하는 흔한 이유가 "누가 내 계정에 들어온 것 같다" 이다. 비밀번호만 바꾸고
 * 살아 있는 refresh 토큰을 두면 <b>그 사람은 그대로 들어와 있다.</b> 그래서 전부 폐기하고,
 * 지금 이 사람에게만 새 토큰 한 벌을 준다.
 */
@Service
public class PasswordResetService {

    private static final Logger log = LoggerFactory.getLogger(PasswordResetService.class);

    private final PasswordResetRepository resets;
    private final UserRepository users;
    private final UserService userService;
    private final RefreshTokenService refreshTokens;
    private final PasswordEncoder passwordEncoder;
    private final Mailer mailer;
    private final MailProperties mailProperties;
    private final VerificationAttempts attempts;

    public PasswordResetService(PasswordResetRepository resets,
                                UserRepository users,
                                UserService userService,
                                RefreshTokenService refreshTokens,
                                PasswordEncoder passwordEncoder,
                                Mailer mailer,
                                MailProperties mailProperties,
                                VerificationAttempts attempts) {
        this.resets = resets;
        this.users = users;
        this.userService = userService;
        this.refreshTokens = refreshTokens;
        this.passwordEncoder = passwordEncoder;
        this.mailer = mailer;
        this.mailProperties = mailProperties;
        this.attempts = attempts;
    }

    /**
     * 재설정을 시작한다. 그 주소의 주인에게 코드를 보낸다.
     *
     * <p>없는 주소면 <b>아무 일도 안 한다</b> — 행도 안 만들고 메일도 안 보낸다. 밖에서 보는
     * 답은 두 경우가 같다.
     *
     * <p>소셜로만 가입한 사람({@code password} 가 없는 계정)에게도 <b>메일은 보낸다.</b>
     * 안 보내면 그 침묵이 "이 사람은 소셜 가입자다" 를 알려 준다. 대신 그 메일은 코드가 아니라
     * "카카오·구글·Apple 로 로그인하세요" 라고 말한다.
     */
    @Transactional
    public void request(String rawEmail) {
        String email = normalize(rawEmail);
        User user = users.findByEmail(email).orElse(null);
        if (user == null) {
            // 여기서 로그에 주소를 남기지 않는다. 남기면 그 로그가 곧 가입 여부 명부다.
            log.debug("없는 주소로 재설정 요청이 왔다 — 아무것도 안 한다");
            return;
        }

        if (user.getPassword() == null || user.getPassword().isBlank()) {
            mailer.send(email, "Pawloop 비밀번호 재설정", socialOnlyBody());
            return;
        }

        String code = VerificationCodes.newCode();
        LocalDateTime now = UserTime.nowUtc();

        PasswordReset row = resets.findByUserId(user.getId())
                .orElseGet(() -> PasswordReset.builder().userId(user.getId()).build());
        row.setCodeHash(passwordEncoder.encode(code));
        row.setExpiresAt(now.plusMinutes(mailProperties.getCodeTtlMinutes()));
        row.setAttempts(0);
        if (row.getCreatedAt() == null) {
            row.setCreatedAt(now);
        }
        resets.save(row);

        mailer.send(email, "Pawloop 비밀번호 재설정", codeBody(code));
    }

    /**
     * 코드를 확인하고 비밀번호를 바꾼다. 성공하면 <b>바로 로그인된 상태</b>로 토큰을 준다.
     *
     * @throws ResponseStatusException 410 — 진행 중인 재설정이 없거나 만료됐다(다시 받아야 한다)
     * @throws ResponseStatusException 401 — 코드가 틀렸다
     */
    @Transactional
    public AuthTokensResponse reset(String rawEmail, String rawCode, String newPassword) {
        String email = normalize(rawEmail);

        // **없는 주소도 410 이다.** 여기서 404 를 주면 이 경로가 가입 여부 조회 수단이 된다.
        // 코드를 모르는 사람에게는 "그런 주소 없음" 과 "코드 만료" 가 구별되지 않아야 한다.
        User user = users.findByEmail(email).orElse(null);
        PasswordReset row = user == null ? null : resets.findByUserId(user.getId()).orElse(null);
        if (row == null) {
            throw gone("재설정을 다시 시작해 주세요.");
        }

        LocalDateTime now = UserTime.nowUtc();

        // 지우기도 세기도 따로 커밋한다 — 아래에서 던지면 이 트랜잭션이 통째로 롤백되고,
        // 같은 안에서 한 변경은 없던 일이 된다(VerificationAttempts 의 javadoc).
        if (row.isExpired(now)) {
            attempts.discard(resets, row.getId());
            throw gone("코드가 만료됐어요. 다시 받아 주세요.");
        }

        if (row.getAttempts() >= mailProperties.getMaxAttempts()) {
            attempts.discard(resets, row.getId());
            throw gone("여러 번 틀렸어요. 코드를 다시 받아 주세요.");
        }

        if (rawCode == null || !passwordEncoder.matches(rawCode.strip(), row.getCodeHash())) {
            attempts.recordFailure(resets, row.getId());
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "코드가 맞지 않아요.");
        }

        user.setPassword(passwordEncoder.encode(newPassword));
        users.save(user);
        resets.delete(row);

        // **다른 기기를 먼저 끊는다.** 재설정을 하는 흔한 이유가 "누가 들어온 것 같다" 인데,
        // 살아 있는 refresh 토큰을 두면 그 사람은 그대로 들어와 있다.
        refreshTokens.revokeAllByUserId(user.getId());

        log.info("비밀번호를 재설정했다 — userId {}", user.getId());
        return userService.issueTokensFor(user, false);
    }

    /** 대문자·공백 때문에 같은 주소가 둘로 갈리지 않게. */
    private static String normalize(String email) {
        return email == null ? "" : email.strip().toLowerCase(Locale.ROOT);
    }

    private static ResponseStatusException gone(String message) {
        return new ResponseStatusException(HttpStatus.GONE, message);
    }

    private String codeBody(String code) {
        return """
                Pawloop 비밀번호 재설정 코드입니다.

                    %s

                앱에 이 여섯 자리를 넣고 새 비밀번호를 정해 주세요. %d분 뒤에 만료됩니다.

                본인이 요청하지 않았다면 이 메일을 무시하셔도 됩니다 — 비밀번호는 아직 그대로입니다.
                """.formatted(code, mailProperties.getCodeTtlMinutes());
    }

    private String socialOnlyBody() {
        return """
                Pawloop 비밀번호 재설정이 요청됐습니다.

                그런데 이 계정에는 **비밀번호가 없습니다.** 카카오·구글·Apple 로 가입하셨습니다.

                앱의 로그인 화면에서 쓰시던 버튼을 눌러 주세요.

                본인이 요청하지 않았다면 이 메일을 무시하셔도 됩니다 — 아무것도 바뀌지 않았습니다.
                """;
    }
}
