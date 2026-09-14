// lib/v2/data/walk_outbox.dart
//
// 아직 서버에 닿지 않은 산책들 — 이슈 #145.
//
// ## 왜 필요한가
//
// 산책이 끝나는 순간 사용자는 이미 걸었다. 그 기록이 사라지는 경우가 넷이다.
//
//   1. 반려동물이 서버에 없다 (등록 전)
//   2. 로그인이 안 돼 있다
//   3. 연결이 없다 (지하 주차장·지하철)
//   4. 저장 화면에서 앱이 강제 종료된다
//
// 넷 다 **같은 자리**를 지난다 — 트래킹이 끝나는 순간이다. 그래서 초안을 "실패했을
// 때" 가 아니라 **끝나는 즉시 무조건** 저장한다. 실패를 기다렸다가 저장하면 4번은
// 영원히 못 잡는다.
//
// ## 두 큐를 나눈다
//
// 재시도할 수 있는 실패(연결 없음·미로그인·429)와 영구 거절(400·404)은 **다른 곳에**
// 둔다. 한 큐에 섞으면 영구 거절 요청이 자리를 차지한 채 영원히 재시도되고, 자리가
// 차면 **정상 기록이 밀려난다.**
//
// ## 새 의존성을 넣지 않는다
//
// `shared_preferences` 는 이미 있고 `uuid` 는 없다. 멱등키는 `chat_outbox.dart` 와
// 같은 방식으로 `Random.secure()` 16바이트를 base64url 로 적는다 — 서버는 이 값을
// **불투명 문자열**로만 쓴다(형식을 검사하지 않는다).
library;

import 'dart:convert';
import 'walk_repository.dart';
import '../domain/walk_moment.dart';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 아직 서버에 없는 산책 하나.
class WalkDraft {
  /// 멱등키. **한 번 만들고 재전송에도 그대로 쓴다.**
  ///
  /// 재전송할 때 키를 새로 만들면 멱등이 무의미해진다 — 첫 전송이 서버에 닿았는데
  /// 응답만 못 받은 경우, 새 키로 보내면 같은 산책이 두 줄이 된다. 서버는
  /// `(dog_id, client_walk_id)` UNIQUE 로 두 번째를 거르는데 키가 다르면 그냥 통과한다.
  final String clientWalkId;

  final DateTime startedAt;
  final DateTime endedAt;
  final int distanceM;
  final int durationS;

  /// `[경도, 위도]` 순서. **비어 있을 수 있다** — 손입력 기록과 위치 권한 거부다.
  final List<List<double>> path;

  /// 각 점의 시각 — 시작 기준 델타 초. **`path` 와 길이가 같다.** 이슈 #155.
  ///
  /// 길이가 다르면 서버가 400 을 준다. 손입력 기록처럼 경로가 없으면 이것도 비어 있다.
  final List<int> pathT;

  final String? memo;
  final String? weather;

  /// 어느 반려동물의 산책인가. **기록할 때는 모를 수 있다** — 서버에 등록된 반려동물이
  /// 아직 없으면 `null` 이고, 등록한 뒤 전송할 때 채워진다.
  final int? dogId;

  /// 함께 나간 아이들의 **서버 id** — 이슈 #343.
  ///
  /// **비어 있을 수 있다.** 한 마리만 키우면 시작 전에 묻지 않으므로 비고, 그때는
  /// [dogId] 하나로 보낸다(서버도 `dogIds` 를 선택으로 받는다). 아이가 둘 이상이면
  /// `WalkDogPicker` 가 고른 것이 여기 담긴다.
  ///
  /// **초안에 실어 두는 이유**는 [place] 와 같다 — 전송이 며칠 뒤일 수 있는데 그 사이에
  /// 고른 목록이 사라지면 다시 만들 수 없다. 비행기 모드에서 두 마리와 걸은 산책이
  /// 한 마리 것으로 올라가면 사용자는 알 길이 없다.
  final List<int> dogIds;

  /// 어디를 걸었나 (#338). 지도에서 "여기서 산책 시작" 으로 왔거나 저장 화면에서 골랐으면
  /// 채워진다. **초안에 실어 두는 이유**는 전송이 나중일 수 있기 때문이다 — 비행기 모드에서
  /// 저장한 산책이 며칠 뒤 올라갈 때 장소만 사라지면, 그 장소는 다시 만들 수 없다.
  final WalkPlaceRef? place;

  /// 산책 중 한 탭으로 남긴 것들 (#340) — 배변·마킹·물.
  ///
  /// **초안에만 산다.** `POST /api/walks` 에는 이 필드가 없다 — 종류와 횟수는 저장 뒤
  /// `care-logs` 로 따로 가고, 어디서 눴는지는 [WalkMoment.pathIndex] 라 경로를 안 보내는
  /// 빌드에서는 기기를 떠나지 않는다(A안 #235).
  final List<WalkMoment> moments;

  /// 마지막 실패의 사유. 화면이 "왜 아직 안 올라갔는지" 를 말해 준다.
  final String? lastError;

  /// 산책 중 찍은 사진의 **기기 안 경로**(#450). 올릴 때 읽는다. 없으면 빈 목록.
  final List<String> photoPaths;

  /// 이미 올린 사진의 서버 id — 재시도에서 다시 올리지 않으려고 적어 둔다. [photoPaths] 의 앞에서부터
  /// 짝이 맞는다(i 번째 경로 = i 번째 id).
  final List<int> mediaIds;

  const WalkDraft({
    required this.clientWalkId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceM,
    required this.durationS,
    required this.path,
    this.pathT = const [],
    this.memo,
    this.weather,
    this.dogId,
    this.dogIds = const [],
    this.place,
    this.moments = const [],
    this.lastError,
    this.photoPaths = const [],
    this.mediaIds = const [],
  });

  double get km => distanceM / 1000.0;

  int get minutes => durationS ~/ 60;

  /// 트래킹이 끝난 직후. **여기서만 키를 만든다.**
  factory WalkDraft.fresh({
    required DateTime startedAt,
    required DateTime endedAt,
    required int distanceM,
    required int durationS,
    required List<List<double>> path,
    List<int> pathT = const [],
    int? dogId,
    List<int> dogIds = const [],
    WalkPlaceRef? place,
    List<WalkMoment> moments = const [],
    List<String> photoPaths = const [],
  }) =>
      WalkDraft(
        clientWalkId: _newKey(),
        startedAt: startedAt,
        endedAt: endedAt,
        distanceM: distanceM,
        durationS: durationS,
        path: path,
        pathT: pathT,
        dogId: dogId,
        dogIds: dogIds,
        place: place,
        moments: moments,
        photoPaths: photoPaths,
      );

  WalkDraft copyWith({
    int? dogId,
    List<int>? dogIds,
    int? distanceM,
    int? durationS,
    String? memo,
    String? weather,
    WalkPlaceRef? place,

    /// 장소를 **없앤다**. 이름 칸을 비우고 저장하면 초안이 들고 온 장소도 함께 지운다 —
    /// `place: null` 만으로는 "안 바꿈" 과 구분되지 않는다.
    bool dropPlace = false,
    String? lastError,
    List<String>? photoPaths,
    List<int>? mediaIds,
  }) =>
      WalkDraft(
        clientWalkId: clientWalkId,
        startedAt: startedAt,
        endedAt: endedAt,
        distanceM: distanceM ?? this.distanceM,
        durationS: durationS ?? this.durationS,
        path: path,
        // path 와 짝이라 함께 옮긴다. 빠뜨리면 서버로 나가는 길에서 시각만 사라진다 —
        // 테스트가 그것을 잡았다. (#155)
        pathT: pathT,
        memo: memo ?? this.memo,
        weather: weather ?? this.weather,
        dogId: dogId ?? this.dogId,
        dogIds: dogIds ?? this.dogIds,
        place: dropPlace ? null : (place ?? this.place),
        // 저장 화면이 copyWith 로 이름·거리를 고칠 때 눌러 둔 것이 떨어지면 안 된다.
        moments: moments,
        lastError: lastError ?? this.lastError,
        photoPaths: photoPaths ?? this.photoPaths,
        mediaIds: mediaIds ?? this.mediaIds,
      );

  Map<String, dynamic> toJson() => {
        'clientWalkId': clientWalkId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
        'distanceM': distanceM,
        'durationS': durationS,
        'path': path,
        if (pathT.isNotEmpty) 'pathT': pathT,
        if (memo != null) 'memo': memo,
        if (weather != null) 'weather': weather,
        if (dogId != null) 'dogId': dogId,
        if (dogIds.isNotEmpty) 'dogIds': dogIds,
        if (place != null) 'place': place!.toJson(),
        if (moments.isNotEmpty) 'moments': [for (final m in moments) m.toJson()],
        if (lastError != null) 'lastError': lastError,
        if (photoPaths.isNotEmpty) 'photoPaths': photoPaths,
        if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
      };

  /// 모양이 다르면 `null`. **저장 형식이 바뀌어도 앱이 죽지 않아야 한다** — 옛 초안
  /// 하나 때문에 전체 큐를 못 읽으면 그 사람의 기록이 전부 사라진다.
  static WalkDraft? tryParse(Map<String, dynamic> json) {
    final key = json['clientWalkId'];
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    final endedAt = DateTime.tryParse(json['endedAt'] as String? ?? '');
    if (key is! String || key.isEmpty || startedAt == null || endedAt == null) {
      return null;
    }

    final rawPath = json['path'];
    final path = rawPath is List
        ? rawPath
            .whereType<List>()
            .map((point) => point.whereType<num>().map((n) => n.toDouble()).toList())
            .where((point) => point.length == 2)
            .toList()
        : <List<double>>[];

    // **길이가 안 맞으면 통째로 버린다.** 짝이 안 맞는 시각 배열은 어느 점이 언제인지
    // 말해 주지 못하고, 그대로 보내면 서버가 400 을 준다 — 그러면 그 초안이 거절 큐로
    // 가고 사용자가 실제로 걸은 기록이 못 올라간다. 시각을 잃는 편이 산책을 잃는 것보다
    // 낫다. (#155)
    final rawPathT = json['pathT'];
    final parsedT = rawPathT is List
        ? rawPathT.whereType<num>().map((n) => n.toInt()).toList()
        : <int>[];
    final pathT = parsedT.length == path.length ? parsedT : <int>[];

    return WalkDraft(
      clientWalkId: key,
      startedAt: startedAt.toLocal(),
      endedAt: endedAt.toLocal(),
      distanceM: (json['distanceM'] as num?)?.toInt() ?? 0,
      durationS: (json['durationS'] as num?)?.toInt() ?? 0,
      path: path,
      pathT: pathT,
      memo: json['memo'] as String?,
      weather: json['weather'] as String?,
      dogId: (json['dogId'] as num?)?.toInt(),
      // 목록이 깨졌으면 비운다 — 그러면 대표 아이 하나로 올라간다. 통째로 버리는 것보다
      // 낫다(#155 의 pathT 와 같은 판단).
      dogIds: json['dogIds'] is List
          ? (json['dogIds'] as List).whereType<num>().map((n) => n.toInt()).toList()
          : const [],
      // 장소는 모양이 다르면 없는 것으로 둔다 — 그것 하나 때문에 산책을 잃지 않는다.
      place: WalkPlaceRef.tryParse(json['place']),
      // 순간들도 같다 — 배변 한 줄이 깨졌다고 걸은 기록을 통째로 버리지 않는다(#340).
      moments: json['moments'] is List
          ? [for (final m in json['moments'] as List) WalkMoment.tryParse(m)]
              .whereType<WalkMoment>()
              .toList()
          : const [],
      lastError: json['lastError'] as String?,
      photoPaths: json['photoPaths'] is List
          ? (json['photoPaths'] as List).whereType<String>().toList()
          : const [],
      mediaIds: json['mediaIds'] is List
          ? (json['mediaIds'] as List).whereType<num>().map((n) => n.toInt()).toList()
          : const [],
    );
  }

  /// 16바이트 난수. `chat_outbox.dart` 와 같은 방식이다 — `uuid` 의존성을 넣지 않는다.
  static String _newKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// 전송 대기 산책들의 보관소. 앱을 껐다 켜도 남는다.
///
/// `chat_outbox` 는 메모리에만 산다(대화는 다시 칠 수 있다). 산책은 **다시 걸을 수
/// 없으므로** 디스크에 둔다.
class WalkOutbox {
  /// 재시도할 수 있는 초안들. 연결이 돌아오면 이 큐가 나간다.
  static const String pendingKey = 'walk_outbox_pending_v1';

  /// 서버가 영구히 거절한 초안들. **재시도하지 않는다.**
  ///
  /// 지우지 않고 남기는 이유: 사용자가 실제로 걸은 기록이고, 왜 못 올라갔는지 보고
  /// 스스로 지울 기회를 줘야 한다. 조용히 버리면 그건 사라진 것과 같다.
  static const String rejectedKey = 'walk_outbox_rejected_v1';

  /// 대기 큐의 상한.
  ///
  /// 20 은 **관측이 아니다.** `SharedPreferences` 가 안드로이드에서 XML 하나를 통째로
  /// 메모리에 올린다는 사실에서 보수적으로 고른 값이고(초안 하나가 경로 포함 약 11KB
  /// 이면 20건은 220KB), 플랫폼의 문서화된 하드 리밋을 확인하지는 않았다. 실사용에서
  /// 초과가 잦으면 별도 파일 저장으로 옮겨야 한다.
  static const int maxPending = 20;

  final SharedPreferences _prefs;

  WalkOutbox(this._prefs);

  static Future<WalkOutbox> open() async =>
      WalkOutbox(await SharedPreferences.getInstance());

  /// 대기 중인 초안들. **호출할 때마다 새 리스트다** — [put] 이 그것을 제자리에서 고친다.
  List<WalkDraft> get pending => _read(pendingKey);

  List<WalkDraft> get rejected => _read(rejectedKey);

  /// 초안 하나를 대기 큐에 넣는다.
  ///
  /// 같은 키가 이미 있으면 **그 자리에서** 덮어쓴다(재시도 상태 갱신). 지우고 뒤에 다시
  /// 붙이면 실패한 초안이 맨 뒤로 가는데, 그러면 큐가 가득 찼을 때 **계속 실패하는 것이
  /// 살아남고 오래된 정상 기록이 밀려난다.** 순서는 걸은 순서로 둔다.
  ///
  /// 큐가 가득 차면 **가장 오래된 것을 밀어낸다.** 새 것을 버리지 않는 이유는 방금 걸은
  /// 산책이 사용자에게 가장 생생하기 때문이다.
  Future<void> put(WalkDraft draft) async {
    final list = pending;
    final at = list.indexWhere((d) => d.clientWalkId == draft.clientWalkId);
    if (at >= 0) {
      list[at] = draft;
    } else {
      list.add(draft);
    }
    while (list.length > maxPending) {
      list.removeAt(0);
    }
    await _write(pendingKey, list);
  }

  /// 전송에 성공했다. 대기 큐에서 뺀다.
  Future<void> remove(String clientWalkId) async {
    await _write(
      pendingKey,
      pending.where((d) => d.clientWalkId != clientWalkId).toList(),
    );
  }

  /// 서버가 영구히 거절했다. **대기 큐에서 빼고 거절 큐로 옮긴다.**
  ///
  /// 대기 큐에 그대로 두면 나갈 때마다 같은 400 을 받고, 그 자리가 채워져 있는 동안
  /// 정상 기록이 밀려난다.
  Future<void> reject(WalkDraft draft, String reason) async {
    await remove(draft.clientWalkId);
    final list = rejected
        .where((d) => d.clientWalkId != draft.clientWalkId)
        .toList()
      ..add(draft.copyWith(lastError: reason));
    while (list.length > maxPending) {
      list.removeAt(0);
    }
    await _write(rejectedKey, list);
  }

  /// 거절 큐에서 하나를 지운다. 사용자가 "지우기" 를 눌렀을 때다.
  Future<void> discardRejected(String clientWalkId) async {
    await _write(
      rejectedKey,
      rejected.where((d) => d.clientWalkId != clientWalkId).toList(),
    );
  }

  List<WalkDraft> _read(String key) {
    final out = <WalkDraft>[];
    final raw = _prefs.getStringList(key);
    // **항상 늘릴 수 있는 리스트를 준다.** const [] 를 돌려주면 put 이 그 위에서
    // add 를 부르다 터진다(실측).
    if (raw == null) return out;
    for (final line in raw) {
      try {
        final json = jsonDecode(line);
        if (json is Map<String, dynamic>) {
          final draft = WalkDraft.tryParse(json);
          // 못 읽는 줄 하나가 나머지를 못 읽게 만들지 않는다.
          if (draft != null) out.add(draft);
        }
      } catch (_) {
        // 같은 이유로 넘어간다.
      }
    }
    return out;
  }

  Future<void> _write(String key, List<WalkDraft> drafts) async {
    await _prefs.setStringList(
      key,
      drafts.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }
}
