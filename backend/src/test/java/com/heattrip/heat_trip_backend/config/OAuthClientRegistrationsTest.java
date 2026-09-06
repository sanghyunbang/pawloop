package com.heattrip.heat_trip_backend.config;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.TreeSet;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 등록된 소셜 공급자 집합을 ADR-0010 에 고정한다. (이슈 #15)
 *
 * <h2>왜 이 테스트가 필요한가</h2>
 * ADR-0010 이 "네이버 보류" 를 정했고 계약({@code openapi.yaml})의 {@code parameters.Provider}
 * 와 {@code User.provider} enum 에서 {@code naver} 를 뺐다. 그런데 그것만으로는 <b>계약이
 * 지킬 수 없는 약속을 하는 상태</b>가 된다 — 클라이언트 등록이 살아 있으면
 * {@code /oauth2/authorization/naver} 가 그대로 열려 있고, 그 경로로 만들어진 계정의
 * {@code GET /auth/me} 응답이 계약 enum 을 위반한다.
 *
 * <p>앱이 여는 것은 우리 호환 래퍼({@code GET /auth/oauth/{provider}}, 여기서 400 을 준다)가
 * 아니라 Spring 의 진입점이다 — {@code social_login_service.dart} 가
 * {@code /oauth2/authorization/{provider}} 를 직접 연다. 즉 래퍼의
 * {@code SUPPORTED_PROVIDERS} 를 좁히는 것만으로는 그 구멍이 닫히지 않는다.
 * <b>등록 자체가 없어야 닫힌다.</b>
 *
 * <h2>왜 컨텍스트를 띄우지 않는가</h2>
 * 프로퍼티 파일을 직접 읽는다. {@code @SpringBootTest} 로 {@code ClientRegistrationRepository}
 * 를 보는 편이 "실제로 적용된 설정" 에 더 가깝지만, 프로파일마다 컨텍스트가 하나씩 더
 * 뜬다(#46 에서 컨텍스트 개수를 세어 관리하기로 했다). 여기서 막아야 하는 회귀는
 * "누가 등록 줄을 다시 붙인다" 이고, 그것은 파일에서 그대로 보인다.
 */
class OAuthClientRegistrationsTest {

    /** ADR-0010 이 정한 집합. 늘리려면 ADR 을 먼저 고쳐라. */
    private static final Set<String> ALLOWED = Set.of("kakao", "google", "apple");

    /** {@code spring.security.oauth2.client.registration.<이름>.<속성>} 의 접두사. */
    private static final String REGISTRATION_PREFIX =
            "spring.security.oauth2.client.registration.";

    private static final List<String> PROFILES = List.of(
            "application-dev.properties", "application-prod.properties");

    @Test
    @DisplayName("등록된 소셜 공급자는 ADR-0010 의 kakao·google 과 ADR-0022 의 apple 뿐이다 — naver 를 되살리면 여기가 빨간불이다")
    void registeredProviders_matchAdr0010() throws IOException {
        for (String profile : PROFILES) {
            Path file = TestProjectPaths.backendDir().resolve("src/main/resources").resolve(profile);

            // 완료 조건 10 과 같은 규칙 — 파일이 없으면 skip 이 아니라 fail 이다.
            // 경로가 바뀌었을 때 조용히 통과하면 이 테스트는 있으나 마나다.
            assertThat(file)
                    .as("설정 파일 %s 를 찾지 못했다. 경로가 바뀌었다면 이 테스트도 함께 고쳐라.", profile)
                    .exists();

            Set<String> registered = new TreeSet<>();
            for (String line : Files.readAllLines(file)) {
                String trimmed = line.strip();
                if (trimmed.startsWith("#") || !trimmed.startsWith(REGISTRATION_PREFIX)) {
                    continue;   // 주석 안의 설명은 등록이 아니다
                }
                String rest = trimmed.substring(REGISTRATION_PREFIX.length());
                int dot = rest.indexOf('.');
                if (dot > 0) {
                    registered.add(rest.substring(0, dot).toLowerCase(Locale.ROOT));
                }
            }

            assertThat(registered)
                    .as("%s 의 소셜 클라이언트 등록. naver 를 되살리려면 ADR-0010 을 먼저 고쳐야 한다 "
                            + "— 등록이 있으면 /oauth2/authorization/naver 가 열려 계약(openapi.yaml)의 "
                            + "provider enum 이 거짓이 된다.", profile)
                    .containsExactlyInAnyOrderElementsOf(ALLOWED);
        }
    }
}
