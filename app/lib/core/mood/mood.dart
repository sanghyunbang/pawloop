import 'package:meta/meta.dart';

/// 무드 체계 SSOT (Single Source of Truth).
///
/// Flutter / Backend(Spring) / Python(LLM) 세 레포가 공유하는 6종 무드입니다.
/// 값의 출처는 `docs/07-implementation-plan.md` 4-1 절의 무드 테이블입니다.
///
/// - `key`   : 서버로 전송하는 `moodKey`(한글). 집계/UGC의 식별자이기도 합니다.
/// - PAD     : 즐거움(p)/각성(a)/주도성(d) 기본 프리셋, 범위 -1..1.
/// - energy  : 에너지 상태, -1..1.
/// - social  : 사교 욕구, -1..1.
///
/// 1탭 무드 체크인은 [key]+강도(intensity)만으로 추천을 요청할 수 있어야 합니다.
/// PAD 프리셋은 클라이언트에서 [padFor]로 채워 전송하고, 백엔드도 동일한 프리셋을
/// SSOT로 보유해(B0-1) moodKey만 와도 동작하도록 이중 안전망을 둡니다.
@immutable
class Mood {
  final String key; // 한글 키 (서버 moodKey)
  final String emoji;
  final String english; // joy/sadness/...
  final double p; // pleasure  -1..1
  final double a; // arousal   -1..1
  final double d; // dominance -1..1
  final double energy; // -1..1
  final double social; // -1..1

  const Mood({
    required this.key,
    required this.emoji,
    required this.english,
    required this.p,
    required this.a,
    required this.d,
    required this.energy,
    required this.social,
  });

  /// 표시용 한글 라벨(= key). 가독성을 위해 별도 getter 제공.
  String get labelKo => key;

  /// 강도(1~5)를 반영한 PAD 트리플.
  ///
  /// 강도 3을 기준(scale 1.0)으로 `value * (intensity / 3)` 후 -1..1 클램프합니다.
  /// energy/social은 강도 스케일을 적용하지 않습니다(백엔드 계약과 동일).
  (double p, double a, double d) padFor(int intensity) {
    final s = intensity / 3.0;
    double clamp(double v) => v < -1 ? -1 : (v > 1 ? 1 : v);
    return (clamp(p * s), clamp(a * s), clamp(d * s));
  }
}

/// 6종 무드 SSOT 인스턴스 모음.
class Moods {
  Moods._();

  static const joy = Mood(
    key: '기쁨',
    emoji: '😊',
    english: 'joy',
    p: 0.6,
    a: 0.4,
    d: 0.3,
    energy: 0.3,
    social: 0.3,
  );
  static const sadness = Mood(
    key: '슬픔',
    emoji: '😢',
    english: 'sadness',
    p: -0.5,
    a: -0.3,
    d: -0.2,
    energy: -0.4,
    social: -0.3,
  );
  static const anxiety = Mood(
    key: '불안',
    emoji: '😰',
    english: 'anxiety',
    p: -0.3,
    a: 0.5,
    d: -0.4,
    energy: 0.0,
    social: -0.2,
  );
  static const anger = Mood(
    key: '분노',
    emoji: '😡',
    english: 'anger',
    p: -0.4,
    a: 0.6,
    d: 0.3,
    energy: 0.4,
    social: -0.1,
  );
  static const calm = Mood(
    key: '평온',
    emoji: '😌',
    english: 'calm',
    p: 0.4,
    a: -0.4,
    d: 0.2,
    energy: -0.3,
    social: 0.0,
  );
  static const excitement = Mood(
    key: '설렘',
    emoji: '✨',
    english: 'excitement',
    p: 0.6,
    a: 0.6,
    d: 0.2,
    energy: 0.5,
    social: 0.3,
  );

  /// 표시/선택 순서 고정.
  static const List<Mood> all = <Mood>[
    joy,
    sadness,
    anxiety,
    anger,
    calm,
    excitement,
  ];

  /// 한글 key 또는 영문명으로 무드를 찾습니다. 없으면 null.
  static Mood? byKey(String? key) {
    if (key == null) return null;
    for (final m in all) {
      if (m.key == key || m.english == key) return m;
    }
    return null;
  }
}
