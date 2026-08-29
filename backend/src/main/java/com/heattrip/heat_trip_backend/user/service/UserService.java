package com.heattrip.heat_trip_backend.user.service;

import java.time.LocalDateTime;

import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.principal.UnauthenticatedException;
import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.dto.SignupRequest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import lombok.RequiredArgsConstructor;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class UserService {
    
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder; // 이건 뭐지?
    private final JWTProvider jwtProvider;

    /**
     * refresh 토큰을 만지는 유일한 통로. 이 서비스는 리포지토리를 직접 보지 않는다. (이슈 #9)
     */
    private final RefreshTokenService refreshTokenService;

   @Transactional
    public void signup(SignupRequest request) {
        if (userRepository.findByEmail(request.getEmail()).isPresent()) {
            throw new IllegalArgumentException("이미 가입된 이메일입니다.");
        }

        // ✅ 필수 동의 체크 (나이와 무관)
        if (Boolean.FALSE.equals(request.getAgreeTos()) || Boolean.FALSE.equals(request.getAgreePrivacy())
            || request.getAgreeTos() == null || request.getAgreePrivacy() == null) {
            throw new IllegalArgumentException("필수 동의(이용약관/개인정보)에 동의해 주세요.");
        }

        // 안 보내면 null 로 저장한다 — 계약(openapi.yaml 의 User.gender)이 null 을 허용한다.
        // 예전에는 switch 의 default 가 OTHER 라, 미지정을 '기타'로 조용히 바꿔 저장했다.
        // 그리고 safeLower(null) 이 null 을 그대로 돌려줘 switch 가 NPE 를 냈다 — 이메일
        // 가입이 500 이었다. (이슈 #42)
        User.Gender gender = parseGender(request.getGender());
        User.AgeGroup ageGroup = parseAgeGroup(request.getAgeGroup());

        LocalDateTime now = LocalDateTime.now();
        String tosVer = nvl(request.getTosVersion(), "v1.0");
        String prvVer = nvl(request.getPrivacyVersion(), "v1.0");
        String mktVer = nvl(request.getMarketingVersion(), "v1.0");

        User user = User.builder()
                // 이메일/비밀번호 가입은 provider = "local". 소셜 가입자와 같은 표에 살면서도
                // 계약(openapi.yaml)의 User.provider 로 구분된다. social_id 는 null 이다. (이슈 #7)
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email(request.getEmail())
                .password(passwordEncoder.encode(request.getPassword()))
                .nickname(request.getNickname())
                .name(request.getName())
                .gender(gender)
                .ageGroup(ageGroup)

                .agreeTos(true)
                .agreePrivacy(true)
                .agreeMarketing(Boolean.TRUE.equals(request.getAgreeMarketing()))

                .tosVersion(tosVer)
                .privacyVersion(prvVer)
                .marketingVersion(Boolean.TRUE.equals(request.getAgreeMarketing()) ? mktVer : null)

                .tosAgreedAt(now)
                .privacyAgreedAt(now)
                .marketingAgreedAt(Boolean.TRUE.equals(request.getAgreeMarketing()) ? now : null)

                .createdAt(now)
                .build();

        userRepository.save(user);
    }

    public String login(LoginRequest request) throws IllegalAccessException {
        User user = userRepository.findByEmail(request.getEmail())
                    .orElseThrow(() -> new IllegalAccessException("가입되지 않은 이메일입니다."));

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new IllegalAccessException("비밀번호가 일치하지 않습니다");
        }

        // refresh 토큰을 함께 발급·저장한다. (이슈 #9)
        //
        // 왜 반환하지 않는가: 이 메서드의 반환값은 그대로 HTTP 응답 본문이 되는 **JWT 평문
        // 문자열**이다. 여기에 RT 를 실으려면 응답을 AuthTokens JSON 으로 바꿔야 하는데,
        // 그 형태 변경은 #10 의 범위이고 지금 바꾸면 평문을 파싱하는 앱을 예고 없이 깨뜨린다.
        // 그래도 지금 발급·저장까지 해 두는 이유는, #10 이 켜기 전까지 이 경로가 한 번도
        // 실행되지 않은 코드로 남는 것을 막기 위해서다. 전달되지 않은 행은 만료 정리가 걷어간다.
        //
        // 대가를 정직하게 적는다: 그 행은 발급 순간부터 14일 동안 <b>아무도 쓸 수 없는 상태</b>로
        // 원장에 남고, 이메일 로그인 1회마다 하나씩 쌓인다. 지금은 만료 정리(벌크 DELETE)가
        // 걷어가므로 견딜 만하지만, 이건 임시 상태다 —
        // **#10 이 로그인 응답을 AuthTokens JSON 으로 바꿀 때 이 반환값을 실어야 끝난다.**
        // 그때까지 이 줄을 지우지 마라: 지우면 소셜 경로에만 있는 발급이 로그인 경로에서
        // 회귀해도 아무도 모른다(UserServiceTest 가 이 호출을 잠근다).
        refreshTokenService.issueFor(user.getId());

        // subject 는 users.id 다. 예전에는 여기에 email 을, 소셜 경로에는 "kakao_1234567890" 을 넣어
        // 같은 토큰 형식이 두 가지 규약을 갖고 있었다. (이슈 #5)
        // 권한은 DB 의 role 컬럼을 쓴다. 예전에는 여기서 "ROLE_USER" 를 하드코딩했다. (이슈 #7)
        return jwtProvider.createAccessToken(user.getId(), roleOf(user));
    }

    /** role 컬럼이 없던 시절에 만들어진 행은 값이 비어 있을 수 있다. */
    private static String roleOf(User user) {
        String role = user.getRole();
        return (role == null || role.isBlank()) ? User.ROLE_USER : role;
    }

    /**
     * 인증 주체를 users.id 로 다시 로드한다.
     *
     * <p>엔티티를 파라미터로 받지 않는 이유: 리졸버가 트랜잭션 밖에서 로드한 detached 엔티티를
     * 서비스로 들여보내면 영속성 컨텍스트 경계가 컨트롤러로 샌다. PK 조회 1회는 싸다.
     *
     * <p>여기서 {@code IllegalArgumentException}(→ 400) 이 아니라
     * {@link UnauthenticatedException}(→ 401) 인 이유: 이 시점에 사용자가 없다는 것은
     * "요청이 잘못됐다"가 아니라 "이 토큰의 주체가 더는 존재하지 않는다"이다. (이슈 #5)
     */
    private User require(Long userId) {
        return userRepository.findById(userId)
                .orElseThrow(UnauthenticatedException::new);
    }

    /** 사용자 정보 수정 */
    public User updateProfile(Long userId, UpdateProfileRequest req) {
        User u = require(userId);

        if (req.getName() != null && !req.getName().isBlank()) {
            u.setName(req.getName().trim());
        }
        if (req.getNickname() != null && !req.getNickname().isBlank()) {
            u.setNickname(req.getNickname().trim());
        }
        // PATCH 라 null 은 '바꾸지 않는다'는 뜻이다. 값이 왔으면 signup 과 같은 규칙으로
        // 해석한다 — 예전에는 오타("mail" 등)를 조용히 OTHER 로 바꿔 저장했다. (이슈 #42)
        if (req.getGender() != null && !req.getGender().isBlank()) {
            u.setGender(parseGender(req.getGender()));
        }
        if (req.getAge() != null) {
            u.setAge(req.getAge());
        }
        if (req.getTravelType() != null) {
            u.setTravelType(req.getTravelType());
        }
        if (req.getImageUrl() != null) {
            u.setImageUrl(req.getImageUrl());
        }

        // ✅ 선택: 마케팅 동의 토글 처리
        if (req.getAgreeMarketing() != null) {
            boolean newVal = req.getAgreeMarketing();
            if (u.getAgreeMarketing() == null || u.getAgreeMarketing() != newVal) {
                u.setAgreeMarketing(newVal);
                u.setMarketingVersion(newVal ? nvl(u.getMarketingVersion(), "v1.0") : null);
                u.setMarketingAgreedAt(newVal ? LocalDateTime.now() : null);
            }
        }

        // @PreUpdate가 updatedAt 갱신
        return userRepository.save(u);
    }

    // 토큰 헤더에서 이메일을 뽑던 헬퍼와 public findByEmail(String) 은 #5 에서 삭제됐다.
    // (완료 조건 5 는 그 헬퍼 이름이 backend/src/main 에서 grep 0건이기를 요구한다 —
    //  주석에도 쓰지 않는 이유가 그것이다. AuthSubjectContractSpecTest 가 주석까지 포함해 확인한다.)
    //
    // 남겨 두면 되돌리는 사람이 jwtProvider.getUserIdFromToken + findByEmail 로 옛 모양을
    // 이어 붙일 수 있다 — 소비처 8곳이 실제로 그 모양이었다. 지우면 어디를 되돌려도
    // 컴파일이 죽는다. 인증 주체 해석은 CurrentUserArgumentResolver 한 곳뿐이다.
    //
    // 지워도 되는 것을 확인했다: signup·login 은 이미 userRepository.findByEmail 을 직접 쓰고,
    // CustomOAuth2UserService 도 userRepository 를 직접 쓴다. 남는 호출자가 0 이었다.

    /**
     * 사용자 삭제 (회원탈퇴).
     *
     * <p><b>refresh 토큰을 사용자보다 먼저 지운다.</b> 순서가 계약이다 — users 로의 FK 를
     * 걸지 않기로 했으므로(RefreshToken 엔티티 javadoc 참조) 원장 정리를 DB 가 대신해 주지
     * 않는다. 여기서 빠뜨리면 탈퇴한 사용자의 RT 행이 남아 완료 조건 7 이 깨진다.
     * 순서 자체는 UserServiceTest 의 InOrder 단언이 잠근다. (이슈 #9)
     */
    @Transactional
    public void deleteMe(Long userId) {
        // 예외 메시지에 이메일을 넣지 않는다 — GlobalExceptionHandler 가 ex.getMessage() 를
        // HTTP 응답 본문에 그대로 싣는다. 예전에는 여기서 이메일이 응답으로 나가고 있었다. (이슈 #6)
        User me = require(userId);
        refreshTokenService.deleteAllByUserId(userId);
        userRepository.delete(me);
        // 필요 시: userRepository.flush();
    }

    /**
     * 사용자 로그아웃 — <b>전 기기</b>. 그 사용자의 살아 있는 refresh 토큰을 전부 폐기한다.
     *
     * <p>기기 하나만 끊지 않는 이유는 계약이 그렇게 선언했기 때문이다
     * (docs/04-api/openapi.yaml 의 {@code POST /auth/logout}: "특정 기기 하나만 끊는 요청 본문은
     * 정의하지 않습니다"). 이슈 본문의 "전달받은 RT 를 폐기" 는 그 계약보다 앞서 쓰인 초안이고,
     * 따르면 계약에 없는 요청 본문을 추가하게 된다(그건 #10 의 영역이다). 정책 #4 는 계약이
     * 코드보다 우선이라고 정했다.
     *
     * <p>멱등이다 — 이미 전부 폐기된 상태여도 영향 행 수가 0 일 뿐 204 다.
     *
     * <p><b>알려진 한계:</b> 이미 발급된 액세스 토큰은 만료(≤1시간)까지 유효하다. 토큰 단위
     * 무효화에는 {@code jti} 클레임과 블록리스트 저장소가 필요한데, MySQL 블록리스트는 모든
     * 인증 요청마다 DB 조회를 1회 더하면서 고작 1시간짜리 창을 줄인다 — 비용이 이득을 넘는다.
     * Redis 로 뒷받침되는 그 작업은 M2 이후 별도 Epic 이다. (이슈 #9)
     */
    @Transactional
    public void logout(Long userId) {
        refreshTokenService.revokeAllByUserId(userId);
    }

     // helpers

    /**
     * 성별 문자열을 해석한다. 대소문자는 가리지 않는다.
     *
     * <p>세 갈래다.
     * <ul>
     *   <li><b>안 보냈거나 빈 문자열</b> → {@code null}(미지정). 계약의 {@code User.gender} 가
     *       {@code null} 을 허용하므로 이게 사실에 맞는 저장이다.</li>
     *   <li><b>MALE·FEMALE·OTHER</b> → 그 값</li>
     *   <li><b>그 밖의 값</b> → {@link IllegalArgumentException}(→ 400).
     *       조용히 OTHER 로 바꾸면 클라이언트의 오타가 데이터로 굳는다.</li>
     * </ul>
     */
    private static User.Gender parseGender(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        return switch (raw.trim().toUpperCase()) {
            case "MALE"   -> User.Gender.MALE;
            case "FEMALE" -> User.Gender.FEMALE;
            case "OTHER"  -> User.Gender.OTHER;
            default -> throw new IllegalArgumentException(
                    "gender 는 MALE·FEMALE·OTHER 중 하나이거나 비어 있어야 합니다.");
        };
    }

    /**
     * 연령 구간을 해석한다. 안 보내면 {@code OVER14} 다 — 계약이 그렇게 선언한다.
     *
     * <p>{@code UNDER14} 는 마케팅 동의 처리가 달라지는 값이라, 모르는 문자열을 조용히
     * {@code OVER14} 로 떨어뜨리면 안 된다. 그건 미성년자를 성인으로 취급하는 것이다.
     */
    private static User.AgeGroup parseAgeGroup(String raw) {
        if (raw == null || raw.isBlank()) {
            return User.AgeGroup.OVER14;
        }
        return switch (raw.trim().toUpperCase()) {
            case "UNDER14" -> User.AgeGroup.UNDER14;
            case "OVER14"  -> User.AgeGroup.OVER14;
            default -> throw new IllegalArgumentException(
                    "ageGroup 은 over14 또는 under14 여야 합니다.");
        };
    }

    private static String nvl(String s, String d) { return (s == null || s.isBlank()) ? d : s; }
}
