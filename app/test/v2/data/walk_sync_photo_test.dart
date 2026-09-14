// 저장할 때 사진이 먼저 올라가고 mediaIds 로 붙는다 — 이슈 #450.
//
// 연결이 끊기면 대기, 서버가 거절한 한 장은 빼고 간다, 다시 보낼 때 앞의 것을 또 올리지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_photos.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_sync.dart';

class _Walks implements WalkRepository {
  final List<List<int>> sentMediaIds = [];
  bool failNext = false;

  @override
  Future<List<ServerPet>> pets() async => const [
        ServerPet(id: 1, name: 'Bori', species: ServerPetSpecies.dog, size: ServerPetSize.medium, neutered: false),
      ];

  @override
  Future<ServerWalk> saveWalk({
    required int dogId,
    List<int> dogIds = const [],
    required String clientWalkId,
    required DateTime startedAt,
    DateTime? endedAt,
    required int distanceM,
    required int durationS,
    List<List<double>>? path,
    List<int>? pathT,
    String? memo,
    String? weather,
    WalkPlaceRef? place,
    List<int> mediaIds = const [],
  }) async {
    if (failNext) {
      failNext = false;
      throw const WalkFailure(WalkFailureKind.network);
    }
    sentMediaIds.add(mediaIds);
    return ServerWalk(
      id: 100 + sentMediaIds.length,
      dogId: dogId,
      clientWalkId: clientWalkId,
      startedAt: startedAt,
      distanceM: distanceM,
      durationS: durationS,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<String> _file(Directory dir, String name) async {
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  await f.writeAsBytes([1, 2, 3]);
  return f.path;
}

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('walk_sync_photo_');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  WalkDraft draft(List<String> photos) => WalkDraft.fresh(
        startedAt: DateTime(2026, 9, 14, 7),
        endedAt: DateTime(2026, 9, 14, 7, 30),
        distanceM: 1200,
        durationS: 1800,
        path: const [],
        photoPaths: photos,
      );

  test('사진 경로가 있으면 먼저 올리고, 받은 id 를 mediaIds 로 붙여 저장한다 — 저장되면 파일은 지운다', () async {
    final a = await _file(tmp, 'a.jpg');
    final b = await _file(tmp, 'b.jpg');
    final uploaded = <String>[];
    final walks = _Walks();
    final sync = WalkSync(
      walks,
      await WalkOutbox.open(),
      uploadPhoto: (path) async {
        uploaded.add(path);
        return 30 + uploaded.length;
      },
      photos: WalkPhotoStore(root: () async => tmp),
    );

    final result = await sync.push(draft([a, b]));

    expect(result.outcome, WalkSyncOutcome.saved);
    expect(uploaded, [a, b], reason: '찍은 순서대로 올린다');
    expect(walks.sentMediaIds.single, [31, 32]);
    expect(await File(a).exists(), isFalse, reason: '서버가 정본이 됐으니 기기 파일은 지운다');
    expect(sync.pending, isEmpty);
  });

  test('사진 없는 산책은 mediaIds 를 안 보낸다', () async {
    final walks = _Walks();
    final sync = WalkSync(walks, await WalkOutbox.open(), uploadPhoto: (_) async => fail('부르면 안 된다'));

    await sync.push(draft(const []));

    expect(walks.sentMediaIds.single, isEmpty);
  });

  test('올리다 연결이 끊기면 대기에 남고, 다시 보낼 때 이미 올린 것은 다시 올리지 않는다', () async {
    final a = await _file(tmp, 'a.jpg');
    final b = await _file(tmp, 'b.jpg');
    var calls = 0;
    var cut = true;
    final walks = _Walks();
    final sync = WalkSync(
      walks,
      await WalkOutbox.open(),
      uploadPhoto: (path) async {
        calls++;
        if (cut && path == b) throw const PostMediaFailure(PostMediaFailureKind.network);
        return path == a ? 31 : 32;
      },
      photos: WalkPhotoStore(root: () async => tmp),
    );

    final first = await sync.push(draft([a, b]));
    expect(first.outcome, WalkSyncOutcome.queued);
    expect(first.reason, contains('사진'));
    expect(walks.sentMediaIds, isEmpty, reason: '사진이 다 안 올라갔으니 산책도 안 보낸다');
    expect(sync.pending.single.mediaIds, [31], reason: '올린 만큼은 초안에 적어 둔다');
    expect(await File(a).exists(), isTrue, reason: '아직 저장 전이라 파일을 안 지운다');

    cut = false;
    final callsBefore = calls;
    final second = await sync.push(sync.pending.single);
    expect(second.outcome, WalkSyncOutcome.saved);
    expect(calls - callsBefore, 1, reason: 'b 만 다시 올린다');
    expect(walks.sentMediaIds.single, [31, 32]);
  });

  test('서버가 거절한 사진(너무 큼 등)은 그 한 장만 빼고 간다 — 사진 하나가 산책을 막지 않는다', () async {
    final a = await _file(tmp, 'a.jpg');
    final b = await _file(tmp, 'b.jpg');
    final walks = _Walks();
    final sync = WalkSync(
      walks,
      await WalkOutbox.open(),
      uploadPhoto: (path) async {
        if (path == a) throw const PostMediaFailure(PostMediaFailureKind.rejected, message: '너무 커요');
        return 32;
      },
      photos: WalkPhotoStore(root: () async => tmp),
    );

    final result = await sync.push(draft([a, b]));

    expect(result.outcome, WalkSyncOutcome.saved);
    expect(walks.sentMediaIds.single, [32]);
    expect(await File(a).exists(), isFalse, reason: '거절된 파일은 버린다');
  });

  test('저장 자체가 연결로 실패해도 올린 id 는 초안에 남아, 다음엔 올리지 않고 저장만 다시 한다', () async {
    final a = await _file(tmp, 'a.jpg');
    var uploads = 0;
    final walks = _Walks()..failNext = true;
    final sync = WalkSync(
      walks,
      await WalkOutbox.open(),
      uploadPhoto: (_) async {
        uploads++;
        return 31;
      },
      photos: WalkPhotoStore(root: () async => tmp),
    );

    expect((await sync.push(draft([a]))).outcome, WalkSyncOutcome.queued);
    expect(sync.pending.single.mediaIds, [31]);

    expect((await sync.flush()), 1);
    expect(uploads, 1, reason: '두 번째엔 안 올린다');
    expect(walks.sentMediaIds.single, [31]);
  });
}
