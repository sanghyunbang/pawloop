package com.heattrip.heat_trip_backend.user.repository;

import com.heattrip.heat_trip_backend.user.entity.User;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * users 테이블의 <b>제약</b>을 실제 DB 로 확인한다 — 이슈 #7 · 정책 #21("저장소는 @DataJpaTest").
 *
 * <p>왜 여기서만 확인되는가: {@code UNIQUE(provider, social_id)} 와 "email 은 NULL 이 여러 개여도 된다"는
 * 자바 코드가 아니라 DDL 의 성질이다. 목으로는 절대 잡히지 않는다.
 *
 * <p>{@code replace = NONE} 인 이유: {@code src/test/resources/application-test.properties} 가
 * H2 를 {@code MODE=MySQL} 로 띄운다. 운영은 MySQL 이므로 NULL 유일성 같은 미묘한 차이를
 * 최대한 같은 조건에서 본다. 기본 임베디드 DB 로 갈아치우면 그 모드가 사라진다.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class UserRepositoryTest {

    @Autowired
    private UserRepository userRepository;

    // ─────────────────── UNIQUE(provider, social_id) ───────────────────

    @Test
    @DisplayName("같은 (provider, social_id) 로 두 번 저장하면 DB 가 거부한다")
    void duplicateProviderAndSocialId_isRejectedByDatabase() {
        userRepository.saveAndFlush(social("kakao", "1234567890", null));

        assertThatThrownBy(() -> userRepository.saveAndFlush(social("kakao", "1234567890", null)))
                .as("이 제약이 없으면 '한 소셜 계정 = 한 행'이 문자열 조합 규칙에만 의존하게 된다")
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("provider 가 다르면 social_id 가 같아도 저장된다 — 공급자마다 ID 공간이 다르다")
    void sameSocialIdOnDifferentProviders_isAllowed() {
        userRepository.saveAndFlush(social("kakao", "1234567890", null));

        assertThatCode(() -> userRepository.saveAndFlush(social("google", "1234567890", null)))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("findByProviderAndSocialId 가 그 행을 찾는다 — 이메일이 없어도")
    void findByProviderAndSocialId_findsTheRow() {
        User saved = userRepository.saveAndFlush(social("kakao", "1234567890", null));

        Optional<User> found = userRepository.findByProviderAndSocialId("kakao", "1234567890");

        assertThat(found).isPresent();
        assertThat(found.get().getId()).isEqualTo(saved.getId());
        assertThat(found.get().getEmail()).isNull();
    }

    @Test
    @DisplayName("없는 소셜 계정은 empty 다")
    void findByProviderAndSocialId_returnsEmptyWhenAbsent() {
        assertThat(userRepository.findByProviderAndSocialId("kakao", "없는아이디")).isEmpty();
    }

    // ─────────────────── email nullable + unique ───────────────────

    @Test
    @DisplayName("email 이 null 인 사용자를 여럿 저장해도 unique 제약에 걸리지 않는다")
    void multipleUsersWithNullEmail_areAllowed() {
        // 카카오 account_email 은 선택 동의다. 동의하지 않은 사용자가 여럿이면 email 이 전부 null 이 된다.
        // MySQL 은 UNIQUE 인덱스에서 NULL 을 서로 다른 값으로 보지만 H2 도 그런지는 '실제로' 봐야 안다.
        userRepository.saveAndFlush(social("kakao", "aaa", null));
        userRepository.saveAndFlush(social("kakao", "bbb", null));

        assertThatCode(() -> userRepository.saveAndFlush(social("naver", "ccc", null)))
                .doesNotThrowAnyException();
        assertThat(userRepository.findAll()).hasSize(3);
    }

    @Test
    @DisplayName("email 의 unique 제약은 살아 있다 — 같은 이메일 두 건은 거부된다")
    void duplicateEmail_isStillRejected() {
        userRepository.saveAndFlush(social("kakao", "aaa", "bori@example.com"));

        assertThatThrownBy(() -> userRepository.saveAndFlush(social("google", "bbb", "bori@example.com")))
                .as("email 을 nullable 로 바꾸면서 unique 까지 잃으면 안 된다")
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    // ─────────────────── 이메일 가입자(provider = local) ───────────────────

    @Test
    @DisplayName("이메일 가입자(provider='local', social_id=null)는 여러 명이어도 저장된다")
    void multipleLocalUsers_areAllowed() {
        // ('local', NULL) 이 여러 건이다. UNIQUE(provider, social_id) 가 NULL 을 같은 값으로 취급하면
        // 두 번째 이메일 가입부터 실패한다. 그 상태가 아님을 확인한다.
        userRepository.saveAndFlush(local("a@example.com"));
        userRepository.saveAndFlush(local("b@example.com"));

        assertThatCode(() -> userRepository.saveAndFlush(local("c@example.com")))
                .doesNotThrowAnyException();
        assertThat(userRepository.findAll()).hasSize(3);
    }

    @Test
    @DisplayName("role 을 지정하지 않아도 ROLE_USER 로 저장된다")
    void role_defaultsToRoleUser() {
        User saved = userRepository.saveAndFlush(local("a@example.com"));

        assertThat(saved.getRole()).isEqualTo(User.ROLE_USER);
    }

    @Test
    @DisplayName("new User() 로 만든 행도 role 이 비지 않는다")
    void role_defaultsEvenWithoutBuilder() {
        User user = new User();
        user.setProvider(User.PROVIDER_LOCAL);
        user.setEmail("noargs@example.com");

        assertThat(userRepository.saveAndFlush(user).getRole()).isEqualTo(User.ROLE_USER);
    }

    // ─────────────────── fixtures ───────────────────

    private static User social(String provider, String socialId, String email) {
        return User.builder()
                .provider(provider)
                .socialId(socialId)
                .username(provider + "_" + socialId)
                .email(email)
                .nickname("보리아빠")
                .build();
    }

    private static User local(String email) {
        return User.builder()
                .provider(User.PROVIDER_LOCAL)
                .email(email)
                .password("encoded")
                .nickname("보리아빠")
                .build();
    }
}
