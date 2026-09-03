import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/screens/family_chat_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/message_actions_sheet.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 가려진 메시지가 화면에 어떻게 나오는가 — 이슈 #82 완료 조건 3 · 6.
///
/// ## 여기서 재는 것
///
/// **화면에 무엇이 보이는가.** 서버가 `hiddenByBlock` 을 붙여 보내도 화면이 그것을 안 읽으면
/// 가린 말이 그대로 보인다 — 그 상태로는 백엔드가 아무리 맞아도 사용자에게는 안 고쳐진 것이다.
///
/// 그리고 **접혀도 목록에서 빠지지 않는다.** 빼면 그 `roomSeq` 가 읽음 커서에 도달하지 않아
/// 미읽음 뱃지가 영원히 남는다.
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

http.Response _json(String body, int status) => http.Response(
      body,
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// 메시지 두 줄 — 하나는 가려졌고 하나는 아니다.
ChatRepository _repoWithOneHiddenMessage({List<String>? calls}) {
  return ChatRepository(
    baseUrl: _base,
    client: AuthedClient(
      inner: MockClient((req) async {
        calls?.add('${req.method} ${req.url.path}');
        if (req.url.path.endsWith('/read')) {
          return _json('{}', 200);
        }
        if (req.method == 'POST' || req.method == 'DELETE') {
          return _json('{"reportId":1,"createdAt":"2026-08-31T10:00:00"}', 201);
        }
        return _json(
          '{"items":['
          '{"id":1,"roomSeq":1,"senderUserId":9,"senderName":"가려진 사람",'
          '"body":"접히지만 사라지지는 않는 말","createdAt":"2026-08-31T10:00:00",'
          '"hiddenByBlock":true},'
          '{"id":2,"roomSeq":2,"senderUserId":8,"senderName":"보통 사람",'
          '"body":"그냥 보이는 말","createdAt":"2026-08-31T10:01:00"}'
          '],"lastSeq":2,"hasMore":false}',
          200,
        );
      }),
      baseUrl: _base,
      store: _FakeTokenStore(),
    ),
  );
}

Future<void> _pump(WidgetTester tester, ChatRepository repo, {bool isOwner = false}) async {
  await tester.pumpWidget(MaterialApp(
    home: FamilyChatScreen(roomId: 7, repository: repo, isOwner: isOwner),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('가려진 메시지는 본문 대신 안내가 뜨고, 안 가려진 것은 그대로다', (tester) async {
    await _pump(tester, _repoWithOneHiddenMessage());

    expect(find.text('가린 사람의 메시지입니다.'), findsOneWidget);
    expect(
      find.text('접히지만 사라지지는 않는 말'),
      findsNothing,
      reason: '서버가 본문을 보내도 화면이 접어야 한다 — 안 접으면 고쳐진 게 아니다',
    );
    expect(find.text('그냥 보이는 말'), findsOneWidget);
  });

  testWidgets('접혀도 목록에서 빠지지 않는다 — 빠지면 미읽음 뱃지가 영원히 남는다', (tester) async {
    await _pump(tester, _repoWithOneHiddenMessage());

    expect(
      find.text('가려진 사람'),
      findsOneWidget,
      reason: '발신자 줄이 남아 있어야 그 roomSeq 가 화면에 도달한 것이다',
    );
  });

  testWidgets('보기를 누르면 그 자리에서 펼쳐진다 — 요청을 더 보내지 않는다', (tester) async {
    final calls = <String>[];
    await _pump(tester, _repoWithOneHiddenMessage(calls: calls));
    final before = calls.length;

    await tester.tap(find.text('보기'));
    await tester.pumpAndSettle();

    expect(find.text('접히지만 사라지지는 않는 말'), findsOneWidget);
    expect(
      calls.length,
      before,
      reason: '본문이 이미 와 있어서 "보기" 는 네트워크를 안 탄다',
    );
  });

  testWidgets('남의 메시지를 길게 누르면 신고·가리기가 뜬다', (tester) async {
    await _pump(tester, _repoWithOneHiddenMessage());

    await tester.longPress(find.text('그냥 보이는 말'));
    await tester.pumpAndSettle();

    expect(find.text('신고하기'), findsOneWidget);
    expect(find.text('이 사람 가리기'), findsOneWidget);
    expect(
      find.text('방에서 내보내기'),
      findsNothing,
      reason: '방장이 아니면 못 하는 버튼을 보여 주고 403 을 받게 하지 않는다',
    );
  });

  testWidgets('이미 가린 사람에게는 해제가 뜬다', (tester) async {
    await _pump(tester, _repoWithOneHiddenMessage());

    await tester.longPress(find.text('가린 사람의 메시지입니다.'));
    await tester.pumpAndSettle();

    expect(find.text('가리기 해제'), findsOneWidget);
    expect(find.text('이 사람 가리기'), findsNothing);
  });

  testWidgets('방장에게만 내보내기가 뜬다', (tester) async {
    await _pump(tester, _repoWithOneHiddenMessage(), isOwner: true);

    await tester.longPress(find.text('그냥 보이는 말'));
    await tester.pumpAndSettle();

    expect(find.text('방에서 내보내기'), findsOneWidget);
  });

  testWidgets('내보내기는 확인을 받고, 문구가 재입장 금지와 푸는 법을 함께 말한다', (tester) async {
    await _pump(tester, _repoWithOneHiddenMessage(), isOwner: true);

    await tester.longPress(find.text('그냥 보이는 말'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('방에서 내보내기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('초대코드를 다시 받아도 들어올 수 없습니다'), findsOneWidget);
    expect(
      find.textContaining('방 설정에서 다시 풀 수 있습니다'),
      findsOneWidget,
      reason: '푸는 방법을 안 말하면 화면이 지키지 못할 약속을 하는 것이다',
    );
  });

  testWidgets('신고 화면의 가리기 체크박스는 기본값이 꺼짐이다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ReportSheet.show(context, senderName: '아무개', subject: '메시지 1개'),
            child: const Text('열기'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(
      checkbox.value,
      isFalse,
      reason: '카카오는 신고하면 자동 차단이다. 가족방에서 그건 되돌릴 수 없는 사고가 된다',
    );
  });

  testWidgets('사유를 안 고르면 신고 버튼이 안 눌린다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ReportSheet.show(context, senderName: '아무개', subject: '메시지 1개'),
            child: const Text('열기'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.text('욕설 · 괴롭힘'));
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });
}
