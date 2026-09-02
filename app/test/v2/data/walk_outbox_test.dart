// WalkOutbox · WalkSync — "산책이 사라지지 않는다" 를 잠근다 (이슈 #145 완료 조건 9).
//
// ## 여기서 재는 것
//
//  1. 초안이 **전송을 시도하기 전에** 저장되는가. 이 순서가 뒤집히면 저장 화면에서
//     앱이 죽었을 때 기록이 사라진다.
//  2. 재시도 가능한 실패와 영구 거절이 **다른 큐**에 가는가. 한 큐에 섞으면 400 짜리가
//     자리를 차지한 채 영원히 재시도되고 정상 기록이 밀려난다.
//  3. 멱등키가 재전송에도 **그대로**인가. 새로 만들면 서버의 UNIQUE 그물을 통과해
//     같은 산책이 두 줄이 된다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_sync.dart';

WalkDraft draftOf({String? key, int distanceM = 2400, List<List<double>>? path}) {
  final fresh = WalkDraft.fresh(
    startedAt: DateTime(2026, 9, 1, 9, 0),
    endedAt: DateTime(2026, 9, 1, 9, 30),
    distanceM: distanceM,
    durationS: 1800,
    path: path ??
        const [
          [126.9780, 37.5665],
          [126.9800, 37.5670],
        ],
  );
  if (key == null) return fresh;
  return WalkDraft(
    clientWalkId: key,
    startedAt: fresh.startedAt,
    endedAt: fresh.endedAt,
    distanceM: fresh.distanceM,
    durationS: fresh.durationS,
    path: fresh.path,
  );
}

/// 정해 둔 대로 답하는 저장소. 네트워크도 `AuthedClient` 도 타지 않는다.
class _ScriptedRepository implements WalkRepository {
  _ScriptedRepository({this.pets_ = const [], this.onSave});

  List<ServerPet> pets_;
  Object? Function(String clientWalkId)? onSave;

  int saveCalls = 0;
  final List<String> savedKeys = [];

  /// 매 저장에 실린 점별 시각. `null` 이면 안 보낸 것이다 (#155).
  final List<List<int>?> sentPathT = [];

  @override
  Future<List<ServerPet>> pets() async => pets_;

  @override
  Future<ServerWalk> saveWalk({
    required int dogId,
    required String clientWalkId,
    required DateTime startedAt,
    DateTime? endedAt,
    required int distanceM,
    required int durationS,
    List<List<double>>? path,
    List<int>? pathT,
    String? memo,
    String? weather,
  }) async {
    saveCalls++;
    savedKeys.add(clientWalkId);
    sentPathT.add(pathT);
    final result = onSave?.call(clientWalkId);
    if (result is WalkFailure) throw result;
    return ServerWalk(
      id: saveCalls,
      dogId: dogId,
      clientWalkId: clientWalkId,
      startedAt: startedAt,
      distanceM: distanceM,
      durationS: durationS,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 은 이 테스트가 안 쓴다');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ─────────────── 점별 시각 (#155) ───────────────
  //
  // LINESTRING 은 x, y 만 담아서 점마다 몇 초에 찍혔는지가 어디에도 없었다. 시각은 그
  // 순간에만 있는 정보라 나중에 만들 수 없다.

  group('점별 시각', () {
    test('앱을 껐다 켜도 시각이 살아 있다', () async {
      final first = await WalkOutbox.open();
      await first.put(WalkDraft.fresh(
        startedAt: DateTime(2026, 9, 2, 9, 0),
        endedAt: DateTime(2026, 9, 2, 9, 30),
        distanceM: 100,
        durationS: 7,
        path: const [
          [126.9780, 37.5665],
          [126.9800, 37.5670],
          [126.9820, 37.5675],
        ],
        pathT: const [0, 3, 7],
      ));

      final second = await WalkOutbox.open();

      expect(second.pending.single.pathT, [0, 3, 7]);
    });

    test('길이가 어긋나면 시각만 버리고 산책은 지킨다', () async {
      // 짝이 안 맞는 배열을 그대로 보내면 서버가 400 을 주고, 그러면 그 초안이 거절
      // 큐로 가서 **사용자가 실제로 걸은 기록이 못 올라간다.** 시각을 잃는 편이 낫다.
      SharedPreferences.setMockInitialValues(<String, Object>{
        WalkOutbox.pendingKey: <String>[
          jsonEncode({
            'clientWalkId': 'mismatched',
            'startedAt': '2026-09-02T09:00:00.000',
            'endedAt': '2026-09-02T09:30:00.000',
            'distanceM': 100,
            'durationS': 7,
            'path': [
              [126.9780, 37.5665],
              [126.9800, 37.5670],
              [126.9820, 37.5675],
            ],
            'pathT': [0, 7],
          }),
        ],
      });

      final outbox = await WalkOutbox.open();

      expect(outbox.pending.single.path, hasLength(3),
          reason: '산책은 남아야 한다');
      expect(outbox.pending.single.pathT, isEmpty,
          reason: '짝이 안 맞는 시각은 어느 점이 언제인지 말해 주지 못한다');
    });

    test('시각이 없으면 서버에 안 싣는다 — 손입력 기록이다', () async {
      final repo = _ScriptedRepository(pets_: [const ServerPet(id: 1, name: '콩이', species: ServerPetSpecies.dog, size: ServerPetSize.small, neutered: false)]);
      final sync = WalkSync(repo, await WalkOutbox.open());

      await sync.push(draftOf());

      expect(repo.sentPathT.single, isNull);
    });

    test('시각이 있으면 함께 보낸다', () async {
      final repo = _ScriptedRepository(pets_: [const ServerPet(id: 1, name: '콩이', species: ServerPetSpecies.dog, size: ServerPetSize.small, neutered: false)]);
      final sync = WalkSync(repo, await WalkOutbox.open());

      await sync.push(WalkDraft.fresh(
        startedAt: DateTime(2026, 9, 2, 9, 0),
        endedAt: DateTime(2026, 9, 2, 9, 30),
        distanceM: 100,
        durationS: 7,
        path: const [
          [126.9780, 37.5665],
          [126.9800, 37.5670],
        ],
        pathT: const [0, 7],
      ));

      expect(repo.sentPathT.single, [0, 7]);
    });
  });

  group('보관소', () {
    test('앱을 껐다 켠 것처럼 다시 열어도 초안이 남아 있다', () async {
      final first = await WalkOutbox.open();
      final draft = draftOf();
      await first.put(draft);

      // 같은 저장소를 새로 연다 = 앱 재시작.
      final second = await WalkOutbox.open();

      expect(second.pending.single.clientWalkId, draft.clientWalkId);
      expect(second.pending.single.distanceM, 2400);
      expect(second.pending.single.path.first, [126.9780, 37.5665],
          reason: '좌표 순서가 왕복해도 그대로여야 한다');
    });

    test('같은 키를 다시 넣으면 두 줄이 되지 않는다', () async {
      final outbox = await WalkOutbox.open();
      final draft = draftOf(key: 'same-key');

      await outbox.put(draft);
      await outbox.put(draft.copyWith(lastError: '연결이 불안정해요'));

      expect(outbox.pending.length, 1);
      expect(outbox.pending.single.lastError, '연결이 불안정해요');
    });

    test('가득 차면 가장 오래된 것을 밀어낸다 — 방금 걸은 것이 가장 생생하다', () async {
      final outbox = await WalkOutbox.open();
      for (var i = 0; i <= WalkOutbox.maxPending; i++) {
        await outbox.put(draftOf(key: 'key-$i'));
      }

      expect(outbox.pending.length, WalkOutbox.maxPending);
      expect(outbox.pending.first.clientWalkId, 'key-1');
      expect(outbox.pending.last.clientWalkId, 'key-${WalkOutbox.maxPending}');
    });

    test('거절된 것은 대기 큐에서 빠지고 따로 남는다 — 조용히 버리지 않는다', () async {
      final outbox = await WalkOutbox.open();
      final draft = draftOf(key: 'bad');
      await outbox.put(draft);

      await outbox.reject(draft, '기록을 저장할 수 없어요');

      expect(outbox.pending, isEmpty);
      expect(outbox.rejected.single.clientWalkId, 'bad');
      expect(outbox.rejected.single.lastError, '기록을 저장할 수 없어요');
    });

    test('못 읽는 줄 하나가 나머지를 못 읽게 만들지 않는다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        WalkOutbox.pendingKey: <String>[
          '이건 JSON 이 아니다',
          '{"clientWalkId":"ok","startedAt":"2026-09-01T00:00:00Z",'
              '"endedAt":"2026-09-01T00:30:00Z","distanceM":100,"durationS":600,"path":[]}',
        ],
      });

      final outbox = await WalkOutbox.open();

      expect(outbox.pending.single.clientWalkId, 'ok');
    });
  });

  group('동기화 정책', () {
    test('전송을 시도하기 전에 먼저 저장한다 — 그 다음에 앱이 죽어도 남는다', () async {
      final outbox = await WalkOutbox.open();
      late List<WalkDraft> queueDuringSave;

      final repo = _ScriptedRepository(
        pets_: [
          const ServerPet(
            id: 3,
            name: '보리',
            species: ServerPetSpecies.dog,
            size: ServerPetSize.small,
            neutered: false,
          )
        ],
        onSave: (_) {
          // 서버가 응답하는 순간 큐를 들여다본다. 여기서 앱이 죽는 상황과 같다.
          queueDuringSave = outbox.pending;
          return null;
        },
      );

      await WalkSync(repo, outbox).push(draftOf(key: 'first'));

      expect(queueDuringSave.map((d) => d.clientWalkId), contains('first'),
          reason: '보내는 동안에도 큐에 있어야 한다');
      expect(outbox.pending, isEmpty, reason: '성공하면 빠진다');
    });

    test('반려동물이 없으면 보내지 않고 큐에 남긴다 — dogId 를 지어낼 수 없다', () async {
      final outbox = await WalkOutbox.open();
      final repo = _ScriptedRepository(pets_: const []);

      final result = await WalkSync(repo, outbox).push(draftOf(key: 'nopet'));

      expect(result.outcome, WalkSyncOutcome.queued);
      expect(repo.saveCalls, 0, reason: '보낼 수 없다는 것을 알고 안 보낸다');
      expect(outbox.pending.single.clientWalkId, 'nopet');
      expect(result.reason, contains('반려동물'));
    });

    test('연결이 없으면 큐에 남는다 — 다시 보낼 수 있다', () async {
      final outbox = await WalkOutbox.open();
      final repo = _ScriptedRepository(
        pets_: [_pet],
        onSave: (_) => const WalkFailure(WalkFailureKind.network),
      );

      final result = await WalkSync(repo, outbox).push(draftOf(key: 'offline'));

      expect(result.outcome, WalkSyncOutcome.queued);
      expect(outbox.pending.single.clientWalkId, 'offline');
      expect(outbox.rejected, isEmpty);
    });

    test('서버가 거절하면 대기 큐에서 빼 거절 큐로 옮긴다 — 자리를 막지 않는다', () async {
      final outbox = await WalkOutbox.open();
      final repo = _ScriptedRepository(
        pets_: [_pet],
        onSave: (_) => const WalkFailure(WalkFailureKind.rejected),
      );

      final result = await WalkSync(repo, outbox).push(draftOf(key: 'bad'));

      expect(result.outcome, WalkSyncOutcome.rejected);
      expect(outbox.pending, isEmpty,
          reason: '여기 남으면 나갈 때마다 같은 400 을 받고 정상 기록이 밀려난다');
      expect(outbox.rejected.single.clientWalkId, 'bad');
    });

    test('재전송에 같은 멱등키를 쓴다 — 새로 만들면 두 줄이 된다', () async {
      final outbox = await WalkOutbox.open();
      var failFirst = true;
      final repo = _ScriptedRepository(
        pets_: [_pet],
        onSave: (_) {
          if (failFirst) {
            failFirst = false;
            return const WalkFailure(WalkFailureKind.network);
          }
          return null;
        },
      );
      final sync = WalkSync(repo, outbox);

      await sync.push(draftOf(key: 'retry-me'));
      final sent = await sync.flush();

      expect(sent, 1);
      expect(repo.savedKeys, ['retry-me', 'retry-me'],
          reason: '두 번 다 같은 키여야 서버의 UNIQUE 가 두 번째를 거른다');
      expect(outbox.pending, isEmpty);
    });

    test('밀린 것을 내보내다 막히면 거기서 멈춘다 — 12초씩 기다리지 않는다', () async {
      final outbox = await WalkOutbox.open();
      await outbox.put(draftOf(key: 'a'));
      await outbox.put(draftOf(key: 'b'));
      await outbox.put(draftOf(key: 'c'));

      final repo = _ScriptedRepository(
        pets_: [_pet],
        onSave: (key) =>
            key == 'b' ? const WalkFailure(WalkFailureKind.network) : null,
      );

      final sent = await WalkSync(repo, outbox).flush();

      expect(sent, 1, reason: 'a 만 나가고 b 에서 멈춘다');
      expect(outbox.pending.map((d) => d.clientWalkId), ['b', 'c']);
    });
  });
}

const _pet = ServerPet(
  id: 3,
  name: '보리',
  species: ServerPetSpecies.dog,
  size: ServerPetSize.small,
  neutered: false,
);
