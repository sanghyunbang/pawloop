package com.heattrip.heat_trip_backend.contract;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 인증 <b>구현 청사진</b> 문서가 shipped 사실과 어긋나지 않는지 본다 — 이슈 #9.
 *
 * <p>왜 계약(`docs/04-api/openapi.yaml`)과 따로 잠그는가: 그 문서는 "서버가 무엇을 약속하는가"
 * 이고 `docs/02-architecture/backend/auth.md` 는 "다음 사람이 무엇을 만들어야 하는가" 다.
 * 후자가 낡으면 계약은 멀쩡한데 <b>다음 사람이 틀린 설계를 지시받는다.</b> 실제로 그랬다 —
 * #9 이전의 이 문서는 로그아웃 폐기를 {@code long deleteByTokenHash(String)} 로 하라고 적고
 * 있었다. 그대로 만들면 폐기가 삭제가 되고, 폐기된 RT 와 없는 RT 를 구별할 수 없게 되어
 * <b>재사용 감지가 통째로 무력해진다</b>. 저장소 관례도 같다 — #5 는 자기 작업의 일부로 이
 * 파일을 갱신했다(커밋 898b41e).
 *
 * <p>문자열 단언을 쓰기 전에 각 문자열이 이 파일 안에서 유일한지(또는 의도한 형태로만
 * 존재하는지) 확인했다. 예: {@code deleteByTokenHash} 자체는 "만들지 마라"는 경고문에
 * 남아 있으므로, 금지 단언은 <b>옛 표의 행 전체</b>를 대상으로 한다.
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class AuthBlueprintDocSpecTest {

    private static String authBlueprint;

    @BeforeAll
    static void loadBlueprint() throws IOException {
        authBlueprint = Files.readString(locateAuthBlueprint(), StandardCharsets.UTF_8);
    }

    /** 테스트 작업 디렉터리(backend/)에서 위로 올라가며 청사진 문서를 찾는다. */
    private static Path locateAuthBlueprint() {
        Path cursor = Paths.get("").toAbsolutePath();
        while (cursor != null) {
            Path candidate = cursor.resolve("docs").resolve("02-architecture")
                    .resolve("backend").resolve("auth.md");
            if (Files.exists(candidate)) {
                return candidate;
            }
            cursor = cursor.getParent();
        }
        throw new IllegalStateException("docs/02-architecture/backend/auth.md 를 찾지 못했다. 작업 디렉터리: "
                + Paths.get("").toAbsolutePath());
    }

    @Test
    @DisplayName("청사진이 refresh 토큰 저장소를 아직 없는 것으로 서술하지 않는다")
    void blueprint_noLongerClaimsRefreshStorageIsMissing() {
        assertThat(authBlueprint)
                .as("#9 가 원장을 만들었다. '없다'고 적힌 문서를 읽은 다음 사람은 같은 것을 또 만든다")
                .doesNotContain("refresh token 저장용 테이블은 **미존재 → 신설 필요**")
                .doesNotContain("refresh token 저장소/엔티티 자체가 없음")
                .doesNotContain("발급/저장/검증/회전/폐기 로직이 전무")
                .doesNotContain("(refresh 발급 메서드 없음 → 추가 필요)")
                .doesNotContain("서버측에 폐기할 상태(refresh 저장소·`jti` 블록리스트)가 아직 없어");
    }

    @Test
    @DisplayName("청사진의 리포지토리 표가 폐기를 삭제로 지시하지 않고 shipped 메서드를 적는다")
    void blueprint_prescribesRevocationNotDeletionForLogout() {
        // 이 행을 그대로 따르면 재사용 감지가 무력해진다. 지운 것이 되살아나지 않게 잠근다.
        assertThat(authBlueprint)
                .as("폐기를 삭제로 바꾸면 폐기된 RT 와 없는 RT 를 구별할 수 없다 (완료 조건 4)")
                .doesNotContain("| `long deleteByTokenHash(String tokenHash)` | 로그아웃 폐기 |");
        assertThat(authBlueprint)
                .as("shipped 메서드가 적혀 있지 않으면 다음 사람이 다시 초안을 만든다")
                .contains("revokeIfLive", "revokeAllByUserId", "deleteByExpiresAtBefore");
    }

    @Test
    @DisplayName("청사진의 refresh_token 컬럼 정의가 실제 엔티티와 같다")
    void blueprint_recordsTheActualColumnDefinition() {
        // prod 는 ddl-auto=validate 라 길이가 어긋나면 부팅이 실패한다.
        assertThat(authBlueprint)
                .as("SHA-256 hex 는 정확히 64자다. 255 로 적힌 문서를 따르면 prod 가 뜨지 않는다")
                .doesNotContain("`token_hash VARCHAR(255)`")
                .contains("`token_hash VARCHAR(64) NOT NULL`");
        assertThat(authBlueprint)
                .as("FK 를 걸지 않은 것은 의도다 — 문서가 FK 를 지시하면 탈퇴 정리 경로가 바뀐다")
                .doesNotContain("| `user_id BIGINT` | FK→`users.id`, INDEX |");
    }

    @Test
    @DisplayName("청사진이 jti 의 소유자로 더 이상 이슈 #9 를 지목하지 않는다")
    void blueprint_doesNotStillPointJtiAtThisIssue() {
        // 계약의 그 문장은 #9 가 고쳤다. 청사진이 옛 문장을 인용한 채로 남으면 인용이 거짓이 된다.
        // 금지 문구가 하나뿐이면 표현만 바꿔서 같은 거짓이 되살아난다.
        // 실제로 그랬다 — 본문 끝은 "이관처는 #9 가 아니라 Redis Epic" 이라고 정정하는데
        // 굵은 머리말은 "#9 로 이관" 으로 남아 있어, 굵은 줄만 훑는 독자가 정확히
        // 이 수정이 없애려던 잘못된 소유자를 얻었다.
        assertThat(authBlueprint)
                .as("#9 는 jti 없이 닫혔다. 소유자는 M2 이후 Redis Epic 이다")
                .doesNotContain("도입은 이슈 #9")
                .doesNotContain("#9 로 이관");
        assertThat(authBlueprint)
                .contains("refresh-token-redis.md");
    }

    @Test
    @DisplayName("앱(#11·#12)에 넘겨야 할 딥링크 파싱과 single-flight 요구가 청사진에 적혀 있다")
    void blueprint_carriesTheHandoffToTheApp() {
        // 백엔드 레인에서는 app/** 을 열 수 없다. 여기 적혀 있지 않으면 전달 경로가 없다.
        assertThat(authBlueprint)
                .as("'token=' 뒤를 전부 잘라 쓰던 코드는 &refresh= 가 붙는 순간 조용히 깨진다")
                .contains("queryParameters['token']");
        assertThat(authBlueprint)
                .as("동시 갱신 1회로 전 기기가 끊기는 것은 앱에게 서버 버그로 보인다")
                .contains("single-flight");
    }
}
