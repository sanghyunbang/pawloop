// 글 카드 위젯 — 이슈 #729 (피드에서 꺼냄).
//
// 여기서 재는 것 셋. 피드 검사들이 보던 키(`bookmark-` · `reaction-` · `post-comment-count-`)가
// 그대로인지, 안쪽 탭(저장 · 반응)이 카드를 **열지 않는지**, 차단한 사람의 글이 들어오면 **아무것도**
// 안 그리는지(애플 지침 1.2 — 목록이 먼저 빼지만 카드가 마지막 그물이다).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/blocked_authors.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/post_card.dart';

CommunityPost _post({bool hidden = false, bool bookmarked = false}) => CommunityPost.tryParse({
      'id': 12,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'pet_place',
      'title': '성수연방 마당',
      'body': '그늘 벤치가 좋아요',
      'loc': '성수연방',
      'contentId': '2745594',
      'commentCount': 3,
      'reactions': {'help': 1, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': const [],
      'bookmarked': bookmarked,
      'hiddenByBlock': hidden,
      'dog': null,
    })!;

Future<void> _pump(WidgetTester t, CommunityPost post, {required void Function(String) log}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PostCard(
        post: post,
        onOpen: () => log('open'),
        onDoubleTapLike: () => log('double'),
        onToggleReaction: (r) => log('reaction:${r.wire}'),
        onToggleBookmark: () => log('bookmark'),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('제목 · 본문 · 장소 · 댓글 수를 그리고, 키가 피드 검사들이 보던 그대로다', (t) async {
    final log = <String>[];
    await _pump(t, _post(), log: log.add);

    expect(find.text('성수연방 마당'), findsOneWidget);
    expect(find.text('그늘 벤치가 좋아요'), findsOneWidget);
    expect(find.text('성수연방'), findsOneWidget);
    expect(find.byKey(const Key('post-comment-count-12')), findsOneWidget);
    expect(find.byKey(const Key('bookmark-12')), findsOneWidget);
    expect(find.byKey(const Key('reaction-help-12')), findsOneWidget);
  });

  testWidgets('저장 · 반응은 카드를 열지 않고 제 콜백만 부른다 — 본문 탭이 연다', (t) async {
    final log = <String>[];
    await _pump(t, _post(), log: log.add);

    await t.tap(find.byKey(const Key('bookmark-12')));
    await t.tap(find.byKey(const Key('reaction-help-12')));
    await t.tap(find.text('성수연방 마당'));
    await t.pumpAndSettle();

    expect(log, ['bookmark', 'reaction:help', 'open']);
  });

  testWidgets('차단한 사람의 글은 아무것도 안 그린다 — 접힌 자리도 "눌러서 보기" 도 없다', (t) async {
    final log = <String>[];
    await _pump(t, _post(hidden: true), log: log.add);

    expect(find.text('성수연방 마당'), findsNothing);
    expect(find.text('그늘 벤치가 좋아요'), findsNothing);
    expect(find.textContaining('눌러서 보기'), findsNothing,
        reason: '애플 지침 1.2 — 차단한 사람의 콘텐츠는 피드에서 사라져야 한다. 펴는 길이 있으면 사라진 것이 아니다');
    expect(find.byType(GestureDetector), findsNothing, reason: '누를 자리도 없다');
  });

  testWidgets('이 세션에서 방금 차단한 사람의 글도 서버 표시 없이 안 그린다', (t) async {
    addTearDown(BlockedAuthors.clear);
    BlockedAuthors.add(7);
    final log = <String>[];
    await _pump(t, _post(), log: log.add);

    expect(find.text('성수연방 마당'), findsNothing);
  });
}
