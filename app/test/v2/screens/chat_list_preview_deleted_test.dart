// 마지막 말이 지워진 방 — 이슈 #517.
//
// 소프트 삭제(#197)는 행을 남기고 **본문만 비운다.** 그래서 목록이 본문만 보면 "아직
// 대화가 없어요" 로 떨어지는데, 그 옆에는 지워진 말의 시각(00:20)이 그대로 떠 있다 —
// 한 줄 안에서 앞뒤가 안 맞고, 무엇보다 **있었던 대화를 없었다고** 말한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/domain/chat_reply.dart';
import 'package:heat_trip_flutter/v2/screens/chat_list_screen.dart';

ChatRoomSummary _room({
  String? body,
  bool deleted = false,
  bool image = false,
  bool hidden = false,
  String? sender = '보리아빠',
}) =>
    ChatRoomSummary(
      id: 4,
      title: '크루',
      tag: '크루',
      lastSeq: 3,
      lastReadSeq: 1,
      unread: 0,
      memberCount: 2,
      lastMessageBody: body,
      lastMessageSender: sender,
      lastMessageDeleted: deleted,
      lastMessageHidden: hidden,
      lastMessageIsImage: image,
    );

void main() {
  test('지워진 마지막 말은 "삭제된 메시지" 다 — "아직 대화가 없어요" 가 아니다', () {
    expect(chatRoomPreview(_room(body: '', deleted: true)), deletedPreview);
  });

  test('사진이 지워져도 "사진" 이 아니라 "삭제된 메시지" 다', () {
    expect(chatRoomPreview(_room(body: '', deleted: true, image: true)), deletedPreview);
  });

  test('정말 아무 말도 없는 방은 예전 그대로다', () {
    expect(chatRoomPreview(_room(body: null)), '아직 대화가 없어요');
  });

  test('가린 사람의 마지막 말은 그대로 접는다 — 지워진 것과 다른 상태다', () {
    expect(chatRoomPreview(_room(body: '안녕', hidden: true)), '가린 사람의 메시지입니다');
  });

  test('계약의 lastMessage.deletedAt 을 읽는다 — 이 값이 없으면 위의 판정이 아예 안 돈다', () {
    final parsed = ChatRoomSummary.tryParse(<String, dynamic>{
      'id': 7,
      'title': '가족방',
      'tag': '가족',
      'lastSeq': 9,
      'lastReadSeq': 9,
      'unread': 0,
      'memberCount': 2,
      'lastMessage': <String, dynamic>{
        'id': 31,
        'body': '',
        'senderName': '보리아빠',
        'createdAt': '2026-09-15T00:20:00Z',
        'deletedAt': '2026-09-15T00:21:00Z',
      },
    });

    expect(parsed, isNotNull);
    expect(parsed!.lastMessageDeleted, isTrue);
    expect(chatRoomPreview(parsed), deletedPreview);
  });
}
