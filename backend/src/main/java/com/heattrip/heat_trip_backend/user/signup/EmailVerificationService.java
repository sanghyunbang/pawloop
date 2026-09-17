package com.heattrip.heat_trip_backend.user.signup;

import com.heattrip.heat_trip_backend.user.UserTime;
import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.dto.SignupRequest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.mail.MailProperties;
import com.heattrip.heat_trip_backend.user.mail.Mailer;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
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
 * 이메일 가입의 인증 — 이슈 #635.
 *
 * <h2>인증 전에는 사용자를 안 만든다</h2>
 * <p>가입 요청은 {@link PendingSignup} 한 행으로 남고, 코드가 맞을 때 비로소 {@code users}
 * 행이 생긴다. {@code users} 에 "미인증" 상태를 두지 않은 이유는 {@code V2__pending_signup.sql}
 * 의 머리말에 적었다 — 요지는 <b>남이 내 주소로 시도만 해 놓고 그 주소를 막아 두는 일</b>이
 * 없어야 한다는 것이다.
 *
 * <h2>이미 가입된 주소인지 말하지 않는다</h2>
 * <p>{@link #start} 는 그 이메일로 이미 계정이 있어도 <b>같은 202 를 돌려준다.</b> 409 를 주면
 * 이 경로가 "이 사람이 가입했나" 를 묻는 조회 수단이 된다 — 로그인이 401 에서 이메일과
 * 비밀번호를 구분하지 않는 것과 같은 이유다(#6).
 *
 * <p>대신 <b>그 사람에게 메일을 보낸다</b> — "누군가 이 주소로 가입을 시도했고, 이미 계정이
 * 있으니 로그인하라" 는 안내다. 그러면 진짜 주인은 상황을 알고, 남은 아무것도 못 알아낸다.
 *
 * <h2>코드도 해시로 둔다</h2>
 * <p>표를 읽을 수 있는 사람이 남의 메일함 없이 가입을 마칠 수 있으면 인증이 아니다.
 */
@Service
public class EmailVerificationService {

    private static final Logger log = LoggerFactory.getLogger(EmailVerificationService.class);

    private final PendingSignupRepository pending;
    private final UserRepository users;
    private final UserService userService;
    private final PasswordEncoder passwordEncoder;
    private final Mailer mailer;
    private final MailProperties mailProperties;

    /** 틀린 시도를 따로 커밋한다 — 그 javadoc 에 이유가 있다. */
    private final VerificationAttempts attempts;

    public EmailVerificationService(PendingSignupRepository pending,
                                    UserRepository users,
                                    UserService userService,
                                    PasswordEncoder passwordEncoder,
                                    Mailer mailer,
                                    MailProperties mailProperties,
                                    VerificationAttempts attempts) {
        this.pending = pending;
        this.users = users;
        this.userService = userService;
        this.passwordEncoder = passwordEncoder;
        this.mailer = mailer;
        this.mailProperties = mailProperties;
        this.attempts = attempts;
    }

    /**
     * 가입을 시작한다. 코드를 메일로 보낸다.
     *
     * <p>이미 가입된 주소면 대기 행을 안 만들고 <b>안내 메일만</b> 보낸다. 밖에서 보는 답은
     * 두 경우가 같다.
     *
     * @return 메일이 실제로 나갔는가. 앱은 이 값으로 "메일이 안 갔어요 · 다시 보내기" 를
     *         말할 수 있다 — 발송 자격이 없는 환경에서 조용히 성공한 척하지 않는다
     */
    @Transactional
    public boolean start(SignupRequest request) {
        String email = normalize(request.getEmail());

        if (users.findByEmail(email).isPresent()) {
            // **보낸 결과를 그대로 돌려준다.** 여기만 true 를 박아 두면, 메일이 안 나가는 환경에서
            // mailSent 가 이미 가입된 주소에만 true 가 된다 — 그것만으로 가입 여부를 묻는 조회
            // 수단이 된다. 위의 202 를 같게 만든 이유가 응답 본문에서 무너진다.
            return mailer.send(email, "Pawloop 가입 안내", alreadyMemberBody());
        }

        String code = VerificationCodes.newCode();
        LocalDateTime now = UserTime.nowUtc();

        // 이메일 하나에 대기 행 하나. 다시 요청하면 옛 행을 덮어쓴다 — 코드를 여럿 살려 두면
        // "몇 번째 메일의 코드인지" 를 사용자도 우리도 모른다.
        PendingSignup row = pending.findByEmail(email).orElseGet(
                () -> PendingSignup.builder().email(email).build());
        row.setPasswordHash(passwordEncoder.encode(request.getPassword()));
        row.setNickname(request.getNickname());
        row.setCodeHash(passwordEncoder.encode(code));
        row.setExpiresAt(now.plusMinutes(mailProperties.getCodeTtlMinutes()));
        row.setAttempts(0);
        if (row.getCreatedAt() == null) {
            row.setCreatedAt(now);
        }
        pending.save(row);

        return mailer.send(email, "Pawloop 인증 코드", codeBody(code));
    }

    /**
     * 코드를 확인하고 계정을 만든다. 성공하면 <b>바로 로그인된 상태</b>로 토큰을 준다.
     *
     * <p>가입만 시키고 로그인 화면으로 되돌리면 방금 정한 비밀번호를 다시 치게 된다.
     *
     * @throws ResponseStatusException 410 — 대기 행이 없거나 만료됐다(코드를 다시 받아야 한다)
     * @throws ResponseStatusException 401 — 코드가 틀렸다
     */
    @Transactional
    public AuthTokensResponse verify(String rawEmail, String rawCode) {
        String email = normalize(rawEmail);
        PendingSignup row = pending.findByEmail(email)
                .orElseThrow(() -> gone("인증을 다시 시작해 주세요."));

        LocalDateTime now = UserTime.nowUtc();

        // **지우기도 세기도 따로 커밋한다.** 아래에서 던지면 이 트랜잭션은 통째로 롤백되고,
        // 같은 안에서 한 변경은 없던 일이 된다 — 시도 횟수가 영원히 0 이었다(#635 에서 잡혔다).
        if (row.isExpired(now)) {
            attempts.discard(pending, row.getId());
            throw gone("코드가 만료됐어요. 다시 받아 주세요.");
        }

        if (row.getAttempts() >= mailProperties.getMaxAttempts()) {
            // 죽은 코드를 살려 두면 무차별 시도가 계속된다.
            attempts.discard(pending, row.getId());
            throw gone("여러 번 틀렸어요. 코드를 다시 받아 주세요.");
        }

        if (rawCode == null || !passwordEncoder.matches(rawCode.strip(), row.getCodeHash())) {
            attempts.recordFailure(pending, row.getId());
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "코드가 맞지 않아요.");
        }

        User user = userService.createVerified(email, row.getPasswordHash(), row.getNickname());
        // 대기 행은 여기서 사라진다. 남겨 두면 비밀번호 해시가 쓸 일 없이 계속 산다.
        pending.delete(row);

        log.info("이메일 가입 완료 — userId {}", user.getId());
        return userService.issueTokensFor(user, true);
    }

    /**
     * 코드를 다시 보낸다.
     *
     * <p>대기 행이 없으면 <b>아무 일도 안 하고 성공을 돌려준다.</b> "그런 대기 없음" 을 말하면
     * 이 경로도 가입 여부 조회 수단이 된다.
     */
    @Transactional
    public boolean resend(String rawEmail) {
        String email = normalize(rawEmail);
        PendingSignup row = pending.findByEmail(email).orElse(null);
        if (row == null) {
            return true;
        }
        String code = VerificationCodes.newCode();
        row.setCodeHash(passwordEncoder.encode(code));
        row.setExpiresAt(UserTime.nowUtc().plusMinutes(mailProperties.getCodeTtlMinutes()));
        row.setAttempts(0);
        pending.save(row);
        return mailer.send(email, "Pawloop 인증 코드", codeBody(code));
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
                Pawloop 인증 코드입니다.

                    %s

                앱에 이 여섯 자리를 넣어 주세요. %d분 뒤에 만료됩니다.

                본인이 요청하지 않았다면 이 메일을 무시하셔도 됩니다 — 아직 계정이 만들어지지 않았습니다.
                """.formatted(code, mailProperties.getCodeTtlMinutes());
    }

    private String alreadyMemberBody() {
        return """
                이 주소로 Pawloop 가입이 요청됐습니다.

                그런데 이 주소에는 **이미 계정이 있습니다.** 새로 만들지 않았습니다.

                본인이라면 앱에서 로그인해 주세요. 비밀번호가 기억나지 않으면
                로그인 화면의 "비밀번호를 잊으셨나요?" 를 눌러 주세요.

                본인이 요청하지 않았다면 이 메일을 무시하셔도 됩니다 — 아무것도 바뀌지 않았습니다.
                """;
    }
}
