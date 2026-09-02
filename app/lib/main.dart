// lib/main.dart
//
// 목적
// - 전역 DI(MultiProvider)로 MediaApiClient/MediaRepository를 주입.
// - 인증 헤더 부착과 401 자동 갱신은 AuthedClient 한 곳에서 한다 (#11). [①]
// - 에러 핸들링(Widget build, 플랫폼, 비동기) 기본 설정.
//
// 필수 포인트
// - --dart-define=API_BASE=... (또는 API_BASE_URL)로 baseUrl 지정 가능. [②]
// - Provider를 사용하는 모든 화면(AvatarPicker/MediaRepository 등)이 의존성을 해결하게 됨. [③]

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:provider/provider.dart';

// go_router 설정
import 'package:heat_trip_flutter/app/app_router.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
// 기본 테마
import 'package:heat_trip_flutter/core/theme/theme.dart';

// ★ shared/media 배럴 (models, picker, api client, repository, widgets 포함)
import 'package:heat_trip_flutter/shared/media/media.dart';
// ★ 토큰 보안 저장소 (Bearer 주입 + 구버전 평문 토큰 마이그레이션에 사용)
import 'package:heat_trip_flutter/features/auth/service/secure_token_store.dart';
// 전역 로그인 상태
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/location_service.dart';

Future<void> main() async {
  // 비동기 초기화 전에 바인딩
  WidgetsFlutterBinding.ensureInitialized();

  // 환경값은 컴파일 타임 --dart-define 으로 들어온다 (Env). 런타임 로드가 없다. → 이슈 #29

  // 네이버 지도 SDK 초기화.
  //
  // Client ID 가 없으면 **여기서 건너뛰고**, 지도를 그리는 화면 셋이 `Env.hasNaverMap` 을
  // 보고 안내문으로 대신한다(explore · walk_tracking · emotion_map). 예전 주석은 "감정지도
  // 탭만 안내문 표시" 였는데 두 번 틀렸다 — 감정지도는 탭이 아니고, 안내문은 없었다.
  // 그래서 키 없는 빌드는 빨간 assertion 을 그대로 보여 줬다 (이슈 #182).
  final naverClientId = Env.naverMapClientId;
  if (naverClientId.isNotEmpty) {
    try {
      await FlutterNaverMap().init(
        clientId: naverClientId,
        onAuthFailed: (ex) => debugPrint('[NaverMap] auth failed: $ex'),
      );
    } catch (e) {
      debugPrint('[NaverMap] init failed: $e');
    }
  } else {
    debugPrint('[NaverMap] NAVER_MAP_CLIENT_ID 미설정 — 지도 비활성');
  }

  // 위치 이용중지(위치정보법 제24조) 설정을 되살린다. **첫 화면이 그려지기 전에**
  // 해야 한다 — 늦으면 중단해 둔 사용자의 현위치를 한 번 조회한 뒤에 꺼진다.
  await LocationService.restorePaused();

  // 구버전(SharedPreferences 평문 'jwt_token') → 보안 저장소 1회 마이그레이션.
  // 로그인 상태를 복원하기 전에 돌려야 기존 사용자가 재로그인 없이 넘어온다.
  await SecureTokenStore.instance.migrateLegacyToken();

  // 세션이 끝나면(refresh 불가 · 재시도 후에도 401) 상태만 내린다 (#11).
  // 저장된 토큰을 지우는 것은 AuthedClient 가 이미 했다.
  //
  // **여기서 화면을 직접 옮기지 않는다.** 라우터가 `AuthState.status` 를
  // `refreshListenable` 로 듣고 있어서(#12), 보호 라우트에 있었다면 알아서 로그인
  // 화면으로 밀려나고 공개 라우트(지도·탐색)에 있었다면 그대로 둘러보기를 이어간다.
  // 예전처럼 무조건 `goNamed('login')` 을 하면, 지도를 보던 사용자가 백그라운드
  // 요청 하나 때문에 로그인 화면으로 튕긴다.
  AuthedClient.instance.onSessionExpired = () async {
    AuthState.markSessionExpired();
  };

  // 저장된 토큰을 서버(`GET /auth/me`)로 검증한다. **await 하지 않는다** —
  // 여기서 네트워크 왕복을 기다리면 첫 프레임 자체가 늦는다. 검증이 끝날 때까지
  // 상태는 `AuthStatus.unknown` 이고 라우터는 스플래시를 띄운다(완료 조건 7).
  unawaited(AuthState.init());

  // Flutter 위젯 트리에서 발생한 모든 에러를 콘솔로
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    // 필요 시 Sentry/Crashlytics 전송 지점
  };

  // 위젯 빌드 중 에러 UI 대체
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      return const SizedBox.shrink(); // 릴리스에선 빈 위젯
    }
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: .3)),
        ),
        child: SingleChildScrollView(
          child: Text(
            'Widget build error:\n\n${details.exceptionAsString()}',
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ),
    );
  };

  // 프레임워크 밖에서 던져진 예외도 잡아 앱 종료 방지
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('UNCAUGHT (PlatformDispatcher): $error');
    if (kDebugMode) {
      debugPrintStack(stackTrace: stack);
    }
    return true; // true 반환 시 프로세스 종료를 막음
  };

  // 비동기 예외 수집
  runZonedGuarded(() => runApp(const HeatTrip()), (error, stack) {
    debugPrint('UNCAUGHT (runZonedGuarded): $error');
    if (kDebugMode) {
      debugPrintStack(stackTrace: stack);
    }
  });
}

class HeatTrip extends StatelessWidget {
  const HeatTrip({super.key});

  @override
  Widget build(BuildContext context) {
    // 베이스 URL은 Env 단일 진입점 사용(운영/로컬 전환 일원화).
    final baseUrl = Env.apiBase;

    return MultiProvider(
      providers: [
        // [A] MediaApiClient: 인증 헤더 부착과 401 갱신은 AuthedClient 가 한다 (#11).
        Provider(create: (_) => MediaApiClient(baseUrl: baseUrl)),
        // [B] MediaRepository: API 클라이언트를 의존성으로 받음. [③]
        ProxyProvider<MediaApiClient, MediaRepository>(
          update: (_, api, __) => MediaRepository(api),
        ),
      ],
      child: MaterialApp.router(
        title: 'Pawloop',
        debugShowCheckedModeBanner: false,
        theme: theme(),
        routerConfig: appRouter,
        builder: (context, child) => child ?? const SizedBox.shrink(),
      ),
    );
  }
}

/* ─────────────────────────── 각주 ───────────────────────────
[①] /media 엔드포인트는 @SecurityRequirement에 의해 인증이 필요합니다.
     tokenProvider를 주입하지 않으면 업로드 시 401/403이 떨어지고,
     로컬 미리보기만 보이는 "착시"가 발생합니다.

[②] baseUrl은 dev/prod에서 달라질 수 있습니다. 빌드 시 --dart-define 으로 관리하세요.
     (.env 에셋 번들링은 폐기했습니다 → 이슈 #29)

[③] AvatarPicker → MediaRepository → MediaApiClient → 백엔드(/media)
     라는 계층으로 연결되어 있으며, Provider가 없으면 의존성 주입에 실패합니다.
────────────────────────────────────────────────────────── */
