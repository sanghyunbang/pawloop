package com.heattrip.heat_trip_backend.docs;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

/**
 * 저장소 루트의 {@code docs/} 를 읽는 테스트가 쓰는 경로 해석기 — 이슈 #15.
 *
 * <h2>왜 backend 안에 사는가</h2>
 * <p>문서는 저장소 전체의 자산이고 {@code backend} 는 루트에 {@code settings.gradle} 이 없는
 * <b>독립 Gradle 프로젝트</b>다. 계층상으로는 어긋난 위치다. 그래도 여기 두는 이유는 지금
 * 이 저장소에서 테스트를 돌릴 수 있는 러너가 {@code backend/gradlew} 와 {@code flutter test}
 * 둘뿐이기 때문이다. CI 를 도입(#22)할 때 재배치를 검토한다.
 *
 * <h2>없으면 skip 이 아니라 fail 이다 (완료 조건 10)</h2>
 * <p>문서 파일을 못 찾았을 때 조용히 통과하면, 경로가 깨진 순간부터 이 테스트들은
 * 아무것도 지키지 않으면서 초록불만 낸다. 그건 없느니만 못하다. 그래서
 * {@link #requireDoc(String)} 은 예외를 던진다.
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
final class RepositoryDocs {

    private RepositoryDocs() {
    }

    /** 저장소 루트의 {@code docs/} 디렉터리. backend 모듈 기준 {@code ../docs}. */
    static Path docsDir() {
        Path repositoryRoot = TestProjectPaths.backendDir().getParent();
        if (repositoryRoot == null) {
            throw new IllegalStateException(
                    "backend 모듈의 상위 디렉터리를 찾지 못했다 — 저장소 루트가 없다는 뜻이다.");
        }
        Path docs = repositoryRoot.resolve("docs");
        if (!Files.isDirectory(docs)) {
            throw new IllegalStateException(
                    "저장소 루트에 docs/ 가 없다: " + docs
                            + " — 문서가 옮겨졌다면 이 테스트들도 함께 고쳐야 한다. skip 하지 않는다.");
        }
        return docs;
    }

    /**
     * {@code docs/} 기준 상대 경로의 파일을 읽는다.
     *
     * <p>없으면 던진다. 이 테스트들이 지키는 것이 바로 "문서가 제자리에 있고 코드와 맞는가"
     * 라서, 파일 부재를 통과로 처리하면 검사 자체가 사라진다.
     */
    static String requireDoc(String relativePath) {
        Path resolved = docsDir().resolve(relativePath);
        if (!Files.isRegularFile(resolved)) {
            throw new IllegalStateException(
                    "테스트가 요구하는 문서가 없다: " + resolved
                            + " — 파일이 옮겨졌거나 이름이 바뀌었다면 이 테스트도 함께 고쳐야 한다.");
        }
        try {
            return Files.readString(resolved, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("문서를 읽지 못했다: " + resolved, e);
        }
    }
}
