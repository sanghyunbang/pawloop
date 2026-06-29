import 'package:flutter/foundation.dart';

/// 가벼운 분석 이벤트 훅 (Phase 0 측정 스캐폴드).
///
/// Phase 0의 North Star는 "무드 체크인 완료율"과 "입력 소요시간"입니다
/// (`docs/03-product-roadmap.md` 5절). 측정이 가능하려면 이벤트가 필요해서,
/// 지금은 단일 진입점만 만들어 둡니다. 추후 Firebase/Amplitude 등 실제 SDK를
/// 이 [log] 한 곳에서 연결하면 됩니다(나머지 호출부는 변경 불필요).
class Analytics {
  Analytics._();

  /// 이벤트 이름 상수 (오탈자 방지).
  static const evMoodCheckinStarted = 'mood_checkin_started';
  static const evMoodCheckinCompleted = 'mood_checkin_completed';
  static const evMoodCheckinAdvanced = 'mood_checkin_advanced'; // 심화 입력 진입

  static void log(String event, [Map<String, Object?> params = const {}]) {
    // TODO(analytics): 실제 분석 SDK 연결 지점.
    if (kDebugMode) {
      debugPrint('[analytics] $event ${params.isEmpty ? '' : params}');
    }
  }
}
