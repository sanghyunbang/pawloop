// 위치 스트림 설정 — 안드로이드는 포그라운드 서비스 알림, iOS 는 백그라운드 갱신 허용 (#335).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:heat_trip_flutter/v2/data/location_service.dart';

void main() {
  test('안드로이드 — 포그라운드 서비스 알림이 붙고, 깨어 있고, 지울 수 없는 알림이다', () {
    final s = LocationService.settingsFor(TargetPlatform.android, title: 'Bori랑 산책 기록 중', text: '탭하면 돌아가요');

    expect(s, isA<AndroidSettings>());
    final a = s as AndroidSettings;
    expect(a.accuracy, LocationAccuracy.high);
    expect(a.distanceFilter, 5);
    expect(a.forceLocationManager, isTrue, reason: '포그라운드 서비스 안의 FusedLocation 은 갱신을 막았다 — GPS 제공자 직접');
    final fg = a.foregroundNotificationConfig;
    expect(fg, isNotNull, reason: '이게 없으면 화면을 끈 뒤 시스템이 위치 갱신을 끊는다');
    expect(fg!.notificationTitle, 'Bori랑 산책 기록 중');
    expect(fg.notificationText, '탭하면 돌아가요');
    expect(fg.enableWakeLock, isTrue);
    expect(fg.setOngoing, isTrue, reason: '산책 중에 알림을 지우면 서비스가 죽는 것으로 오해한다');
  });

  test('iOS — 백그라운드 갱신을 허용하고 파란 표시를 켠다, 자동 일시정지는 끈다', () {
    final s = LocationService.settingsFor(TargetPlatform.iOS, title: 't', text: 'x');

    expect(s, isA<AppleSettings>());
    final i = s as AppleSettings;
    expect(i.accuracy, LocationAccuracy.high);
    expect(i.distanceFilter, 5);
    expect(i.allowBackgroundLocationUpdates, isTrue);
    expect(i.showBackgroundLocationIndicator, isTrue, reason: '위치를 계속 읽는다는 것을 숨기지 않는다');
    expect(i.pauseLocationUpdatesAutomatically, isFalse, reason: '멈춰 서서 줄을 푸는 동안 iOS 가 스트림을 끊으면 안 된다');
    expect(i.activityType, ActivityType.fitness);
  });

  test('첫 위치 한 번 — 안드로이드는 GPS 제공자 직접, 어디서든 25초 제한', () {
    final a = LocationService.currentSettingsFor(TargetPlatform.android) as AndroidSettings;
    expect(a.forceLocationManager, isTrue);
    expect(a.timeLimit, const Duration(seconds: 25), reason: '실내에서 "위치를 잡는 중" 이 영원히 돌면 안 된다');
    expect(LocationService.currentSettingsFor(TargetPlatform.iOS).timeLimit, const Duration(seconds: 25));
    expect(LocationService.currentSettingsFor(TargetPlatform.windows).timeLimit, const Duration(seconds: 25));
  });

  test('그 밖의 플랫폼 — 평범한 설정', () {
    final s = LocationService.settingsFor(TargetPlatform.windows, title: 't', text: 'x');
    expect(s, isNot(isA<AndroidSettings>()));
    expect(s, isNot(isA<AppleSettings>()));
    expect(s.distanceFilter, 5);
  });
}
