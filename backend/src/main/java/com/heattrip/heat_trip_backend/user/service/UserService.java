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

        User.Gender gender = switch (safeLower(request.getGender())) {
            case "male"   -> User.Gender.MALE;
            case "female" -> User.Gender.FEMALE;
            default       -> User.Gender.OTHER;
        };

        User.AgeGroup ageGroup = switch (safeLower(request.getAgeGroup())) {
            case "under14" -> User.AgeGroup.UNDER14;
            default        -> User.AgeGroup.OVER14; // 기본
        };

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
        if (req.getGender() != null && !req.getGender().isBlank()) {
            String g = req.getGender().trim().toUpperCase();
            switch (g) {
                case "FEMALE" -> u.setGender(User.Gender.FEMALE);
                case "MALE"   -> u.setGender(User.Gender.MALE);
                default       -> u.setGender(User.Gender.OTHER);
            }
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

    /** 사용자 삭제 (회원탈퇴) */
    @Transactional
    public void deleteMe(Long userId) {
        // 예외 메시지에 이메일을 넣지 않는다 — GlobalExceptionHandler 가 ex.getMessage() 를
        // HTTP 응답 본문에 그대로 싣는다. 예전에는 여기서 이메일이 응답으로 나가고 있었다. (이슈 #6)
        userRepository.delete(require(userId));
        // 필요 시: userRepository.flush();
    }

    /**
     * 사용자 로그아웃.
     *
     * <p><b>본문이 비어 있는 것은 사실을 반영한 것이다.</b> 폐기할 서버측 상태가 아직 없다 —
     * refresh 토큰도, 액세스 토큰 블록리스트({@code jti})도 없어서 발급된 토큰은 만료까지 유효하다.
     * 저장/폐기는 이슈 #9 범위다. 엔드포인트와 이 메서드는 그때 채울 이음새로 남긴다.
     */
    @Transactional
    public void logout(Long userId) {

    }

     // helpers
    private static String safeLower(String s) { return s == null ? null : s.toLowerCase(); }
    private static String nvl(String s, String d) { return (s == null || s.isBlank()) ? d : s; }
}
