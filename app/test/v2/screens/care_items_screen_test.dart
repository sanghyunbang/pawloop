// 할 일 고치기 화면 — 이슈 #560 조각 3.
//
// 가짜 저장소를 만들지 않고 **진짜 FamilyRepository 에 MockClient 를 꽂는다**(카드 테스트와
// 같은 규약). 그래야 JSON 파싱·경로·본문까지 한 번에 지난다 — 저장소를 목으로 갈아끼우면
// "보낸 본문이 계약과 다르다" 는 회귀가 이 테스트를 그대로 통과한다.
//
// 이 화면에서 제일 조심한 것은 **끌어 놓기가 한 칸 어긋나는 것**이다. `onReorderItem` 의
// `newIndex` 는 이미 조정된 값이라 옛 `onReorder` 처럼 1 을 빼면 틀린다 — 여기서 결과
// 순서를 직접 잰다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/screens/care_items_screen.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';

  @override
  Future<String?> readRefreshToken() async => 'refresh-token';

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _item({
  required int id,
  required String name,
  String icon = 'meal',
  String? systemType,
  int? dailyTarget,
  int sortOrder = 0,
  String? archivedAt,
}) =>
    {
      'id': id,
      'dogId': null,
      'name': name,
      'icon': icon,
      'systemType': systemType,
      'dailyTarget': dailyTarget,
      'sortOrder': sortOrder,
      'archivedAt': archivedAt,
    };

/// 기본 셋 — 물 · 밥 · 산책.
final _three = [
  _item(id: 1, name: '물', icon: 'water', systemType: 'water', sortOrder: 0),
  _item(id: 2, name: '밥', icon: 'meal', systemType: 'meal', sortOrder: 1),
  _item(id: 3, name: '산책', icon: 'walk', systemType: 'walk', sortOrder: 2),
];

({FamilyRepository repo, List<http.Request> sent, List<String> bodies}) fixture({
  List<Map<String, Object?>>? items,
  int writeStatus = 200,
  Object? writeBody,
}) {
  final sent = <http.Request>[];
  final bodies = <String>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.method == 'GET') {
        return _json(items ?? _three);
      }
      sent.add(request);
      bodies.add(request.body);
      if (writeStatus >= 400) {
        return _json({'code': 'VALIDATION', 'message': '목록의 항목을 모두 보내야 합니다.'},
            status: writeStatus);
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      if (request.url.path.endsWith('/order')) return http.Response('', 204);
      return _json(writeBody ?? _item(id: 9, name: '양치', icon: 'tooth', sortOrder: 3),
          status: request.method == 'POST' ? 201 : 200);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (
    repo: FamilyRepository(baseUrl: _base, client: client),
    sent: sent,
    bodies: bodies,
  );
}

Future<void> _open(WidgetTester tester, FamilyRepository repo) async {
  await tester.pumpWidget(MaterialApp(
    home: CareItemsScreen(groupId: 3, repository: repo),
  ));
  await tester.pumpAndSettle();
}

/// 손잡이를 잡고 한 줄 아래로 끈다 — 기본 손잡이를 껐으므로 길게 누르기가 아니다.
Future<void> _dragDown(WidgetTester tester, int itemId) async {
  final handle = find.byKey(Key('care-item-drag-$itemId'));
  final rowHeight = tester.getSize(find.byKey(Key('care-item-$itemId'))).height;
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await tester.pump(const Duration(milliseconds: 50));
  // 한 번에 멀리 밀면 끌기로 안 잡힐 수 있다 — 몇 번에 나눠 옮기고 그때마다 그린다.
  for (var i = 0; i < 4; i++) {
    await gesture.moveBy(Offset(0, rowHeight / 4 + 1));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('목록이 순서대로 뜬다 — 접힌 것도 함께', (tester) async {
    final f = fixture(items: [
      ..._three,
      _item(
          id: 4,
          name: '투약',
          icon: 'med',
          systemType: 'med',
          sortOrder: 3,
          archivedAt: '2026-09-16T03:00:00Z'),
    ]);
    await _open(tester, f.repo);

    expect(find.text('물'), findsOneWidget);
    expect(find.text('투약'), findsOneWidget,
        reason: '접힌 것을 빼면 다시 켤 방법이 화면에서 사라진다');
    expect(find.textContaining('접힘'), findsOneWidget);
  });

  testWidgets('하루 목표가 있으면 줄에 적힌다', (tester) async {
    final f = fixture(items: [
      _item(id: 1, name: '밥', systemType: 'meal', dailyTarget: 2),
    ]);
    await _open(tester, f.repo);

    expect(find.textContaining('하루 2번'), findsOneWidget);
  });

  testWidgets('끌어 놓으면 한 칸씩 어긋나지 않는다 — 전부를 그 순서대로 보낸다', (tester) async {
    final f = fixture();
    await _open(tester, f.repo);

    await _dragDown(tester, 1);

    expect(f.sent, hasLength(1));
    expect(f.sent.single.method, 'PUT');
    expect(f.sent.single.url.path, '/api/groups/3/care-items/order');
    expect(jsonDecode(f.bodies.single)['itemIds'], [2, 1, 3],
        reason: '한 칸 어긋나면 [1,2,3] 이나 [2,3,1] 이 된다');
  });

  testWidgets('순서 저장이 거절되면 서버 순서로 되돌린다 — 화면만 바뀐 채로 두지 않는다',
      (tester) async {
    final f = fixture(writeStatus: 400);
    await _open(tester, f.repo);

    await _dragDown(tester, 1);

    // **끌기가 실제로 일어났는지 먼저 본다.** 이 줄이 없으면, 드래그가 아무 일도 안 해도
    // "첫 줄이 물" 이라는 아래 단언이 그대로 통과한다 — 아무것도 안 재는 테스트가 된다.
    expect(jsonDecode(f.bodies.single)['itemIds'], [2, 1, 3]);
    expect(find.text('목록의 항목을 모두 보내야 합니다.'), findsOneWidget,
        reason: '거절 사유를 안 보여 주면 사용자는 왜 되돌아갔는지 모른다');

    final tiles = find.byType(ListTile);
    expect((tester.widget<ListTile>(tiles.first).title! as Text).data, '물',
        reason: '거절했으면 화면도 서버 순서로 돌아와야 한다');
  });

  testWidgets('접기는 DELETE 다 — 지우기가 아니다', (tester) async {
    final f = fixture();
    await _open(tester, f.repo);

    await tester.tap(find.byKey(const Key('care-item-archive-2')));
    await tester.pumpAndSettle();

    expect(f.sent.single.method, 'DELETE');
    expect(f.sent.single.url.path, '/api/groups/3/care-items/2');
  });

  testWidgets('접힌 것을 다시 켜면 PUT archived:false 다', (tester) async {
    final f = fixture(items: [
      _item(
          id: 4,
          name: '투약',
          icon: 'med',
          systemType: 'med',
          archivedAt: '2026-09-16T03:00:00Z'),
    ]);
    await _open(tester, f.repo);

    await tester.tap(find.byKey(const Key('care-item-archive-4')));
    await tester.pumpAndSettle();

    expect(f.sent.single.method, 'PUT');
    final body = jsonDecode(f.bodies.single) as Map<String, dynamic>;
    expect(body['archived'], false);
    expect(body['name'], '투약', reason: '전량 교체라 이름을 같이 안 보내면 지워진다');
  });

  testWidgets('추가 시트가 이름·그림·목표를 그대로 보낸다', (tester) async {
    final f = fixture();
    await _open(tester, f.repo);

    await tester.tap(find.byKey(const Key('care-item-add')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('care-item-name')), '양치');
    await tester.tap(find.byKey(const Key('care-icon-tooth')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('care-target-2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('care-item-save')));
    await tester.pumpAndSettle();

    expect(f.sent.single.method, 'POST');
    expect(jsonDecode(f.bodies.single), {
      'name': '양치',
      'icon': 'tooth',
      'dailyTarget': 2,
    });
  });

  testWidgets('이름이 비면 서버에 안 보낸다 — 왕복을 돌고 기다리게 하지 않는다', (tester) async {
    final f = fixture();
    await _open(tester, f.repo);

    await tester.tap(find.byKey(const Key('care-item-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('care-item-name')), '   ');
    await tester.tap(find.byKey(const Key('care-item-save')));
    await tester.pumpAndSettle();

    expect(f.sent, isEmpty);
    expect(find.text('이름을 적어 주세요'), findsOneWidget);
  });

  testWidgets('고치기는 전량 교체다 — 목표를 없음으로 바꾸면 그 키가 빠진다', (tester) async {
    final f = fixture(items: [
      _item(id: 2, name: '밥', systemType: 'meal', dailyTarget: 2),
    ]);
    await _open(tester, f.repo);

    await tester.tap(find.byKey(const Key('care-item-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('care-target-none')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('care-item-save')));
    await tester.pumpAndSettle();

    final body = jsonDecode(f.bodies.single) as Map<String, dynamic>;
    expect(body.containsKey('dailyTarget'), isFalse,
        reason: '안 보내면 서버가 비운다 — PUT 이라 그게 "지우기" 다');
    expect(body['name'], '밥');
  });
}
