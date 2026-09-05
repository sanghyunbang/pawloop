// 프로필 지우기 — 이슈 #156. 묻고, 확인해야 보내고, 서버는 소프트 삭제라 산책 기록은 남는다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/pet_sync.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/edit_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _base = 'https://api.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT-1';
  @override
  Future<String?> readRefreshToken() async => 'RT-1';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

const _bori = DogProfile(serverId: 7, name: '보리', breed: '믹스견', size: DogSize.small, ageMonths: 30);
const _tan = DogProfile(serverId: 8, name: '탄이', breed: '', size: DogSize.medium, ageMonths: 12);

({PetSync sync, List<http.Request> seen}) fixture({int deleteStatus = 204}) {
  final seen = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      seen.add(request);
      if (request.method == 'DELETE') {
        return deleteStatus == 204
            ? http.Response('', 204)
            : http.Response(jsonEncode({'error': {}}), deleteStatus,
                headers: const {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('[]', 200,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (
    sync: PetSync(repository: WalkRepository(baseUrl: _base, client: client)),
    seen: seen,
  );
}

Future<void> pumpEdit(WidgetTester tester, PetSync sync) async {
  // 화면을 길게 잡아 아래쪽의 "프로필 지우기" 까지 한 화면에 들어오게 한다 — 스크롤러블이
  // 여럿(세로 목록·가로 테두리 고르기)이라 scrollUntilVisible 이 어느 것을 밀지 못 정한다.
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: EditScreen(pet: _bori, sync: sync)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    replacePets(const [_bori, _tan]);
    selectPet(0);
  });

  testWidgets('"프로필 지우기" 는 바로 지우지 않고 묻는다 — 기록은 남고 프로필은 못 되돌린다고',
      (tester) async {
    final f = fixture();
    await pumpEdit(tester, f.sync);

    await tester.tap(find.text('프로필 지우기'));
    await tester.pumpAndSettle();

    expect(find.text('보리 프로필을 지울까요?'), findsOneWidget);
    expect(find.text('산책 기록은 그대로 남고 통계에도 계속 세요. 프로필은 되돌릴 수 없어요.'),
        findsOneWidget,
        reason: '되살리기가 없다(#156 6번). 확인 문구가 그만큼 분명해야 한다');
    expect(f.seen.where((r) => r.method == 'DELETE'), isEmpty);
  });

  testWidgets('"지우기" 를 누르면 DELETE /api/dogs/{id} 를 보내고 목록에서 빠진다', (tester) async {
    final f = fixture();
    await pumpEdit(tester, f.sync);

    await tester.tap(find.text('프로필 지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();

    final sent = f.seen.where((r) => r.method == 'DELETE').toList();
    expect(sent, hasLength(1));
    expect(sent.single.url.path, '/api/dogs/7');
    expect(kMyPets.value.map((p) => p.name), ['탄이']);
    expect(kMyDog.value?.name, '탄이');
  });

  testWidgets('취소하면 아무것도 보내지 않는다', (tester) async {
    final f = fixture();
    await pumpEdit(tester, f.sync);

    await tester.tap(find.text('프로필 지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(f.seen.where((r) => r.method == 'DELETE'), isEmpty);
    expect(kMyPets.value, hasLength(2));
  });

  testWidgets('서버가 거절하면 목록은 그대로고 이유를 보여 준다', (tester) async {
    final f = fixture(deleteStatus: 404);
    await pumpEdit(tester, f.sync);

    await tester.tap(find.text('프로필 지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();

    expect(kMyPets.value, hasLength(2), reason: '실패했는데 화면에서 사라지면 지워진 줄 안다');
    expect(find.text('반려동물을 찾을 수 없어요'), findsOneWidget);
  });
}
