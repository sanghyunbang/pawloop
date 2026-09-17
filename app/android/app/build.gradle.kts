// android/app/build.gradle.kts
// -----------------------------------------------------------------------------
// 목적
// - 디버그(개발) 빌드는 key.properties 없이 항상 빌드 가능
// - 릴리스 빌드(assembleRelease/bundleRelease)일 때만 서명 파일을 읽고 엄격히 검증
// - key.properties 경로와 .gitignore 정책을 표준화(android/key.properties)
// -----------------------------------------------------------------------------

import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")      // (= "kotlin-android")
    id("dev.flutter.flutter-gradle-plugin") // Flutter Gradle 플러그인
}

android {
    // ──────────────────────────────────────────────────────────────────────────
    // [앱 기본 메타]
    // ──────────────────────────────────────────────────────────────────────────
    namespace = "app.pawloop"

    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        // 자바 17 타깃
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications(#341)가 java.time 을 쓴다. minSdk 가 23 이라
        // 그 API 가 없는 기기가 있어서 디슈가링이 필요하다 — 끄면 빌드가 아니라
        // **실행 중에** NoClassDefFoundError 로 죽는다.
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        applicationId = "app.pawloop"
        // flutter_naver_map(1.4.x)는 minSdk 23 이상 필요
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ──────────────────────────────────────────────────────────────────────────
    // [서명 파일 로딩 정책]
    //   - 구성(Configuration) 단계에서 실패하지 않도록 "조건부 로드"만 수행.
    //   - 실제 실패(throw)는 릴리스 buildType 내부에서만 일으킴.
    // ──────────────────────────────────────────────────────────────────────────

    // ① 현재 Gradle 태스크가 릴리스 계열인지(assembleRelease/bundleRelease 등) 검사
    val isReleaseTask = gradle.startParameter.taskNames.any {
        it.contains("Release", ignoreCase = true)
    }

    // ② 서명 파일 표준 경로 → app/android/key.properties
    //    ※ 루트에 두지 않고 android/ 아래에 두는 이유: 안드 폴더와 결합, gitignore 관리 용이
    //
    //    **rootProject 는 저장소 루트가 아니라 `app/android/` 다** — Flutter 가 안드로이드
    //    빌드를 그 폴더를 루트로 삼아 돌린다(android/settings.gradle.kts 가 그 증거로,
    //    local.properties 를 자기 폴더에서 읽는다).
    //
    //    그래서 여기가 "android/key.properties" 였을 때 실제로 찾은 경로는
    //    `app/android/android/key.properties` 였고, 그런 폴더는 없다. 키스토어와
    //    key.properties 가 **멀쩡히 있는데도** 아래 정책이 "Missing android/key.properties"
    //    로 릴리스 빌드를 막았다(2026-09-17 실측, #634). 서명이 조용히 빠지는 대신 크게
    //    막아 준 것은 그 정책이 옳았기 때문이고, 틀린 것은 이 한 줄이었다.
    val keystoreFile = rootProject.file("key.properties")
    val hasKeystore = keystoreFile.exists()

    // ③ 파일이 있으면 **태스크 종류와 무관하게** 읽는다 (#646)
    //
    //    예전에는 `hasKeystore && isReleaseTask` 였다. "디버그면 안 읽어도 된다" 는 뜻이었는데,
    //    아래 `signingConfigs.create("release") { ... }` 의 블록이 **설정 단계에서 즉시 실행된다.**
    //    지연 평가가 아니다. 그래서 디버그 태스크에서도 그 블록이 돌고, 안 읽어 둔 빈 Properties
    //    에서 `req("storeFile")` 이 예외를 던졌다 — **서명 파일을 갖춘 기계에서만** 디버그 빌드가
    //    막혔다. 그 기계가 곧 실기기 확인과 스토어 제출을 하는 기계다(2026-09-17 실측, #646).
    //
    //    `create("release")` 를 `isReleaseTask` 로 막는 방법은 못 쓴다. 아래 buildTypes 의 릴리스
    //    블록이 `hasKeystore` 만 보고 `signingConfigs.getByName("release")` 를 부르는데, 그 블록도
    //    설정 단계에 돌기 때문이다 — 없는 이름을 찾다 다른 예외가 난다.
    //
    //    불완전한 key.properties 면 디버그도 실패한다. 그건 의도다 — 서명 설정이 깨진 채로 조용히
    //    가는 것보다 낫고, 릴리스의 엄격함(#634)도 그대로다.
    val keystoreProps = Properties().also { props ->
        if (hasKeystore) {
            FileInputStream(keystoreFile).use(props::load)
        }
    }

    // ④ Properties 안전 접근 헬퍼 (키가 없으면 명확한 에러 메시지)
    fun Properties.req(key: String): String =
        this[key]?.toString()
            ?: throw GradleException("key.properties is missing required entry: $key")

    // ──────────────────────────────────────────────────────────────────────────
    // [Signing Configs]
    //   - debug: Android가 제공하는 기본 debug.keystore 사용
    //   - release: 파일이 있을 때만 생성(없으면 buildTypes.release에서 정책 처리)
    // ──────────────────────────────────────────────────────────────────────────
    signingConfigs {
        // 디버그: 명시만 해도 기본 debug.keystore 사용
        getByName("debug")

        // 릴리스: 키파일이 실제 존재할 때만 구성 생성
        if (hasKeystore) {
            create("release") {
                // 이 블록은 **설정 단계에서 즉시** 실행된다(지연 평가가 아니다). 그래서 위 ③ 이
                // 태스크 종류와 무관하게 읽어 둬야 한다 — #646.
                storeFile = file(keystoreProps.req("storeFile"))
                storePassword = keystoreProps.req("storePassword")
                keyAlias = keystoreProps.req("keyAlias")
                keyPassword = keystoreProps.req("keyPassword")
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // [Build Types]
    // ──────────────────────────────────────────────────────────────────────────
    buildTypes {
        // 개발(디버그) 빌드: 축소/리소스 제거 OFF, 디버그 키로 서명
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }

        // 릴리스 빌드: 축소/리소스 제거 ON, proguard 적용
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            isDebuggable = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            when {
                // (정상경로) 키가 있으면 release 서명 구성 사용
                hasKeystore -> signingConfig = signingConfigs.getByName("release")

                // (보안 우선) 릴리스 태스크인데 키가 없음 → 의도적으로 실패
                isReleaseTask -> throw GradleException(
                    "Missing android/key.properties for release signing.\n" +
                    "Add the file or switch to a non-release task."
                )

                // (개발 편의) 릴리스 태스크가 아닌데 키가 없음 → 디버그 키로 임시 서명
                // 스토어 제출 전 반드시 위 정책으로 되돌릴 것
                else -> signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

// Flutter 소스 루트
flutter { source = "../.." }

dependencies {
    // isCoreLibraryDesugaringEnabled 의 짝. 이 줄이 없으면 그 옵션이 빌드 오류다.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
