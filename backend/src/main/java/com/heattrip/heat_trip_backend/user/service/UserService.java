package com.heattrip.heat_trip_backend.user.service;

import java.time.LocalDateTime;

import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
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

        // userId에 email을 넣음(회원 가입된 회원의 경우)
        return jwtProvider.createAccessToken(user.getEmail(), "ROLE_USER");

    }

    /** email로 사용자 조회 */
    public User findByEmail(String email) {
    return userRepository.findByEmail(email)
            .orElseThrow(() -> new IllegalArgumentException("사용자를 찾을 수 없습니다."));
    }

    /** 사용자 정보 수정 */
    public User updateProfile(String email, UpdateProfileRequest req) {
        User u = findByEmail(email);

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

    // 이미 프론트가 잘 불러오고 있다 해도, 백엔드에서 토큰만으로 식별하는 패턴이 더 안전하고 표준적 → 보안↑
    // 클라이언트가 바디/쿼리로 보내는 이메일을 믿지 않고, 서버가 JWT에서 주체(email)를 확인해 당사자 계정만 읽고/수정하려는 목적
    public String emailFromAuth(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            throw new IllegalArgumentException("Invalid Authorization header");
        }
        String token = authHeader.substring(7);

        return jwtProvider.getUserIdFromToken(token);
    }

    /** 사용자 삭제 (회원탈퇴) */
    @Transactional
    public void deleteMe(String email) {
        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + email));
        userRepository.delete(user);
        // 필요 시: userRepository.flush();
    }

     // helpers
    private static String safeLower(String s) { return s == null ? null : s.toLowerCase(); }
    private static String nvl(String s, String d) { return (s == null || s.isBlank()) ? d : s; }
}
