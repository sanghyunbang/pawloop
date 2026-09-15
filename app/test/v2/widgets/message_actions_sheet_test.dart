// 메시지 길게 누르면 뜨는 시트 — 이슈 #197 (내 메시지 삭제).
//
// 내 메시지에는 "삭제" 하나만, 남의 메시지에는 신고·가리기(·내보내기)만 뜬다. 두 목록이 섞이면
// 내 메시지를 신고하거나 남의 메시지에 "삭제" 가 떠서 403 을 보게 된다.
// "답장"(#452)은 둘 다의 첫 줄이다 — 지워진 말에는 없다(`canReply`, `family_chat_reply_test` 가 잰다).
// 반응 다섯(#452)은 그보다 위의 가로 한 줄이다 — 목록의 줄로 늘어놓으면 시트가 화면을 덮는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/widgets/message_actions_sheet.dart';

Widget _host(Widget sheet) => MaterialApp(home: Scaffold(body: sheet));

void main() {
  testWidgets('내 메시지: "답장" 과 "이 메시지 삭제" 둘뿐이다 — 신고·가리기·내보내기는 없다', (tester) async {
    await tester.pumpWidget(_host(const MessageActionsSheet(
      senderName: '내 메시지',
      hiddenByBlock: false,
      canRemoveMember: true,
      isMine: true,
    )));

    expect(find.text('답장'), findsOneWidget, reason: '내 말에도 답장할 수 있다(#452)');
    expect(find.text('이 메시지 삭제'), findsOneWidget);
    expect(find.text('신고하기'), findsNothing, reason: '내 메시지를 신고하는 것은 뜻이 없다');
    expect(find.text('이 사람 가리기'), findsNothing);
    expect(find.text('방에서 내보내기'), findsNothing, reason: '방장이라도 자기 자신을 내보내는 자리가 아니다');
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('남의 메시지: 신고·가리기가 뜨고 "삭제" 는 없다', (tester) async {
    await tester.pumpWidget(_host(const MessageActionsSheet(
      senderName: '보리아빠',
      hiddenByBlock: false,
      canRemoveMember: false,
    )));

    expect(find.text('신고하기'), findsOneWidget);
    expect(find.text('이 사람 가리기'), findsOneWidget);
    expect(find.text('이 메시지 삭제'), findsNothing, reason: '남의 메시지에 삭제가 뜨면 누르는 순간 403 이다');
    expect(find.text('방에서 내보내기'), findsNothing);
  });

  testWidgets('남의 메시지 + 방장: 답장 · 신고 · 가리기 해제 · 내보내기 넷이다', (tester) async {
    await tester.pumpWidget(_host(const MessageActionsSheet(
      senderName: '보리아빠',
      hiddenByBlock: true,
      canRemoveMember: true,
    )));

    expect(find.text('가리기 해제'), findsOneWidget, reason: '이미 가린 사람이면 해제가 떠야 한다');
    expect(find.text('방에서 내보내기'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(4));
  });

  testWidgets('반응 다섯이 한 줄로 뜬다 — 이미 누른 것은 표시가 있고, 지워진 말에는 줄이 없다', (tester) async {
    await tester.pumpWidget(_host(const MessageActionsSheet(
      senderName: '보리아빠',
      hiddenByBlock: false,
      canRemoveMember: false,
      myKinds: {'check'},
    )));

    for (final wire in ['like', 'heart', 'laugh', 'sad', 'check']) {
      expect(find.byKey(Key('reaction-pick-$wire')), findsOneWidget);
    }
    expect(
      tester.getSemantics(find.byKey(const Key('reaction-pick-check'))),
      containsSemantics(isSelected: true),
      reason: '이미 누른 것을 표시 안 하면 그것을 또 눌러 취소되는 일을 예측할 수 없다',
    );

    await tester.pumpWidget(_host(const MessageActionsSheet(
      senderName: '보리아빠',
      hiddenByBlock: false,
      canRemoveMember: false,
      canReact: false,
    )));
    expect(find.byKey(const Key('reaction-pick-like')), findsNothing,
        reason: '지워진 말에는 반응을 못 붙인다 — 서버도 409 다');
  });

  testWidgets('반응을 고르면 종류와 함께 돌아온다 — 열거값 하나로는 어느 반응인지 못 싣는다', (tester) async {
    MessageChoice? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await MessageActionsSheet.show(
                context,
                senderName: '보리아빠',
                hiddenByBlock: false,
                canRemoveMember: false,
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reaction-pick-heart')));
    await tester.pumpAndSettle();

    expect(picked?.action, MessageAction.react);
    expect(picked?.kind, 'heart');
  });

  testWidgets('"이 메시지 삭제" 를 누르면 delete 가 돌아온다', (tester) async {
    MessageChoice? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await MessageActionsSheet.show(
                context,
                senderName: '내 메시지',
                hiddenByBlock: false,
                canRemoveMember: false,
                isMine: true,
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 메시지 삭제'));
    await tester.pumpAndSettle();

    expect(picked?.action, MessageAction.delete);
    expect(picked?.kind, isNull, reason: '반응이 아닌 선택에는 종류가 없다');
  });
}
