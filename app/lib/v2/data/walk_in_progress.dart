// 진행 중인 산책의 스냅숏 — 앱이 죽었다 살아나도 이어서 기록하기 위해 (#335).
//
// 트래킹 화면은 경로를 메모리에만 들고 있었다. 화면을 끄고 주머니에 넣은 채 시스템이 앱을
// 죽이면 30분 산책이 통째로 사라졌다. 5초마다 기기 저장소에 적어 두고, 다시 열면
// "이어서 기록할까요?" 를 묻는다.
//
// 좌표열이 기기 안 `shared_preferences` 에 남는다 — 저장이 끝나면 지운다. 안드로이드 자동
// 백업은 꺼져 있고(`android_backup_is_off_test`), 서버로는 가지 않는다(A안, #235).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/walk_moment.dart';

/// 진행 중인 산책 한 장. 저장 화면이 받는 `WalkDraft` 와 달리 **끝나지 않은** 산책이다.
class WalkInProgress {
  final DateTime startedAt;

  /// 기록된 초 — 일시정지 동안은 안 센다. 앱이 죽어 있던 시간도 안 센다.
  final int seconds;
  final int distanceM;

  /// `[경도, 위도]` 순. `WalkDraft.path` 와 같은 모양이다.
  final List<List<double>> path;

  /// 각 점의 시각(시작 기준 델타 초). `path` 와 길이가 같다.
  final List<int> pathT;

  /// 산책 중 한 탭으로 남긴 것들 (#340). 앱이 죽었다 살아나도 눌러 둔 것이 안 사라진다.
  /// 옛 스냅숏에는 이 키가 없다 — 그때는 빈 목록이다.
  final List<WalkMoment> moments;

  /// 마지막으로 적은 시각. "지난 산책이 몇 분 전에 끊겼나" 를 말할 때 쓴다.
  final DateTime savedAt;

  const WalkInProgress({
    required this.startedAt,
    required this.seconds,
    required this.distanceM,
    required this.path,
    required this.pathT,
    required this.savedAt,
    this.moments = const [],
  });

  double get km => distanceM / 1000;

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'seconds': seconds,
        'distanceM': distanceM,
        'path': path,
        'pathT': pathT,
        if (moments.isNotEmpty) 'moments': [for (final m in moments) m.toJson()],
        'savedAt': savedAt.toIso8601String(),
      };

  /// 모양이 어긋난 값(길이가 다른 `path`/`pathT`, 빠진 키)은 `null` — 깨진 스냅숏으로 이어 걷지 않는다.
  static WalkInProgress? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final startedAt = DateTime.tryParse('${raw['startedAt']}');
    final savedAt = DateTime.tryParse('${raw['savedAt']}');
    final seconds = raw['seconds'];
    final distanceM = raw['distanceM'];
    final path = raw['path'];
    final pathT = raw['pathT'];
    if (startedAt == null || savedAt == null || seconds is! int || distanceM is! int) return null;
    if (path is! List || pathT is! List || path.length != pathT.length) return null;
    final points = <List<double>>[];
    for (final p in path) {
      if (p is! List || p.length != 2 || p[0] is! num || p[1] is! num) return null;
      points.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
    }
    final times = <int>[];
    for (final t in pathT) {
      if (t is! int) return null;
      times.add(t);
    }
    // 순간들은 **깨져도 스냅숏을 버리지 않는다** — 걸은 경로가 배변 한 줄 때문에
    // 통째로 사라지면 안 된다. 모양이 아닌 항목만 조용히 뺀다.
    final rawMoments = raw['moments'];
    final moments = rawMoments is List
        ? [for (final m in rawMoments) WalkMoment.tryParse(m)].whereType<WalkMoment>().toList()
        : <WalkMoment>[];

    return WalkInProgress(
      startedAt: startedAt,
      seconds: seconds,
      distanceM: distanceM,
      path: points,
      pathT: times,
      moments: moments,
      savedAt: savedAt,
    );
  }
}

/// 스냅숏을 기기에 적고 읽는다. 자리는 하나다 — 산책은 한 번에 하나만 한다.
class WalkInProgressStore {
  const WalkInProgressStore();

  static const String key = 'walk_in_progress_v1';

  /// 이보다 오래된 스냅숏은 잇지 않는다 — 어제 끊긴 산책을 오늘 산책에 붙이면 거리가 거짓이 된다.
  static const Duration staleAfter = Duration(hours: 6);

  Future<void> save(WalkInProgress walk) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(walk.toJson()));
  }

  /// 없거나 깨졌거나 너무 오래됐으면 `null`. 오래된 것은 지운다.
  Future<WalkInProgress?> load({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
    final walk = WalkInProgress.tryParse(decoded);
    if (walk == null) {
      await prefs.remove(key);
      return null;
    }
    final at = now ?? DateTime.now();
    if (at.difference(walk.savedAt) > staleAfter) {
      await prefs.remove(key);
      return null;
    }
    return walk;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
