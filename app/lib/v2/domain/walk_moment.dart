// lib/v2/domain/walk_moment.dart
//
// 산책 중에 한 탭으로 남긴 일 — 이슈 #340.
//
// ## 왜 한 탭인가
//
// 산책하는 사람은 한 손에 줄, 다른 손에 배변봉투를 들고 있다. 그 상태에서 화면을 보고
// 무엇을 고르고 확인을 누르는 흐름은 **안 쓰이고 끝난다**(페르소나 P3 — 입력 마찰이 크면
// 결국 안 쓴다). 그래서 종류마다 버튼 하나이고, 그 버튼을 누르는 것이 곧 기록이다.
//
// 실수로 눌렀을 때를 위해 **5초 안에 같은 버튼을 다시 누르면 취소**한다. 확인 대화상자를
// 띄우지 않는 이유도 같다 — 되돌리는 일에도 손이 하나만 있다.
//
// ## 위치는 좌표로 안 든다
//
// 어디서 눴는지는 [WalkMoment.pathIndex] 로 **경로 위의 몇 번째 점인가**만 적는다. 좌표를
// 새로 베껴 두지 않는 것이 요점이다 — 그 좌표는 이미 `WalkDraft.path` 에 있고, 그 path 는
// A안(#235)에서 서버로 나가지 않는다. 여기에 위도·경도를 또 두면 "좌표가 사는 자리" 가
// 하나 늘고, 그 자리는 언젠가 다른 경로로 새어 나간다.
//
// 서버로 나가는 것은 **종류와 시각뿐**이다 — `care-logs` 의 `type` 이고, 그 계약에는 위치
// 필드가 없다(`CareLogInput`).
library;

/// 한 탭으로 남길 수 있는 세 가지.
///
/// [wire] 는 서버 계약(`openapi.yaml` 의 `CareType`)과 **같은 문자열**이다. 물은 이미 있던
/// `water` 를 그대로 쓴다 — 산책 중에 마신 물도 오늘의 케어에서는 같은 칸이다.
enum WalkMomentKind {
  poop('poop', '배변'),
  pee('pee', '마킹'),
  water('water', '물');

  const WalkMomentKind(this.wire, this.label);

  /// DB·계약·앱이 공유하는 단 하나의 표기.
  final String wire;

  /// 화면에 쓰는 이름.
  final String label;

  static WalkMomentKind? tryParse(String? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// 산책 중 한 순간. 종류 · 시작 기준 초 · 경로 위의 점.
class WalkMoment {
  const WalkMoment({required this.kind, required this.tSec, this.pathIndex});

  final WalkMomentKind kind;

  /// 시작 기준 델타 초. `WalkDraft.pathT` 와 **같은 기준**이라 나중에 둘을 나란히 읽을 수 있다.
  final int tSec;

  /// 경로의 몇 번째 점에서 눌렀나. 위치를 아직 못 받았으면 `null` 이다 —
  /// 그래도 기록은 남는다(횟수와 시각이 이 기능의 값이다).
  final int? pathIndex;

  Map<String, dynamic> toJson() => {
        'kind': kind.wire,
        'tSec': tSec,
        if (pathIndex != null) 'pathIndex': pathIndex,
      };

  /// 모양이 다르면 `null`. 옛 초안 하나 때문에 큐 전체를 못 읽으면 안 된다(`WalkDraft.tryParse`).
  static WalkMoment? tryParse(Object? json) {
    if (json is! Map) return null;
    final kind = WalkMomentKind.tryParse(json['kind'] as String?);
    if (kind == null) return null;
    final index = (json['pathIndex'] as num?)?.toInt();
    return WalkMoment(
      kind: kind,
      tSec: (json['tSec'] as num?)?.toInt() ?? 0,
      pathIndex: index != null && index >= 0 ? index : null,
    );
  }
}

/// 종류별 횟수. 화면이 "배변 2회 · 물 1회" 를 그리는 자리이고, 저장할 때 케어 로그를
/// 몇 개 보낼지도 이것이 정한다.
class WalkMomentTally {
  const WalkMomentTally(this._counts);

  factory WalkMomentTally.of(Iterable<WalkMoment> moments) {
    final counts = <WalkMomentKind, int>{};
    for (final moment in moments) {
      counts[moment.kind] = (counts[moment.kind] ?? 0) + 1;
    }
    return WalkMomentTally(counts);
  }

  final Map<WalkMomentKind, int> _counts;

  int operator [](WalkMomentKind kind) => _counts[kind] ?? 0;

  bool get isEmpty => _counts.values.every((n) => n == 0);

  /// "배변 2회 · 물 1회". **0 인 종류는 안 적는다** — 안 한 일을 굳이 세어 보여 주면
  /// 못 한 것처럼 읽힌다. 하나도 없으면 빈 문자열이다.
  String get summary => [
        for (final kind in WalkMomentKind.values)
          if (this[kind] > 0) '${kind.label} ${this[kind]}회',
      ].join(' · ');
}

/// 한 번의 탭이 기록인가 취소인가.
enum WalkMomentTap { recorded, cancelled }

/// 산책 하나 동안 눌린 것들과 **취소 규칙**.
///
/// ## 왜 화면 밖에 있나
///
/// 트래킹 화면은 네이버 지도와 geolocator 를 물고 있어 위젯 테스트로 못 띄운다. 규칙이
/// 그 안에 있으면 "5초 안에 다시 누르면 취소" 를 재는 방법이 손으로 걸어 보는 것뿐이다.
/// 그래서 규칙만 여기 두고 화면은 [tap] 을 부르기만 한다.
///
/// 시각은 [tap] 이 받는다 — 안에서 `DateTime.now()` 를 부르면 테스트가 5초를 진짜로
/// 기다려야 하고, 가짜 시간을 쓰면 그 테스트는 시계가 아니라 자기 자신을 잰다.
class WalkMomentLog {
  /// 잘못 눌렀다는 것을 알아차리는 데 걸리는 시간. 걸으면서라 넉넉히 잡는다.
  static const Duration undoWindow = Duration(seconds: 5);

  final List<WalkMoment> _moments = [];
  WalkMomentKind? _lastKind;
  DateTime? _lastAt;

  List<WalkMoment> get moments => List.unmodifiable(_moments);

  WalkMomentTally get tally => WalkMomentTally.of(_moments);

  /// 이어 걷기(#335)로 살아난 것들을 담는다. 취소 창은 열지 않는다 —
  /// 앱이 죽었다 살아난 뒤에 "다시 누르면 취소" 가 떠 있으면 뜻이 없다.
  void addAll(Iterable<WalkMoment> moments) => _moments.addAll(moments);

  /// [now] 기준으로 취소할 수 있는 종류. 창이 닫혔으면 `null`.
  WalkMomentKind? undoableAt(DateTime now) {
    final at = _lastAt, kind = _lastKind;
    if (at == null || kind == null) return null;
    return now.difference(at) < undoWindow ? kind : null;
  }

  /// 한 번의 탭. 같은 종류를 5초 안에 다시 누르면 **그 종류의 마지막 하나를 뺀다**.
  WalkMomentTap tap(
    WalkMomentKind kind, {
    required int tSec,
    required DateTime now,
    int? pathIndex,
  }) {
    if (undoableAt(now) == kind) {
      final last = _moments.lastIndexWhere((m) => m.kind == kind);
      if (last >= 0) _moments.removeAt(last);
      _lastKind = null;
      _lastAt = null;
      return WalkMomentTap.cancelled;
    }
    _moments.add(WalkMoment(kind: kind, tSec: tSec, pathIndex: pathIndex));
    _lastKind = kind;
    _lastAt = now;
    return WalkMomentTap.recorded;
  }
}
