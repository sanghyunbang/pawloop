// 방 목록의 마지막 말이 사진이면 "사진" — 이슈 #452. 캡션이 있으면 캡션.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/screens/chat_list_screen.dart';

ChatRoomSummary _room({String? body, bool image = false, String? sender = '보리아빠'}) => ChatRoomSummary(
      id: 4,
      title: '크루',
      tag: '크루',
      lastSeq: 3,
      lastReadSeq: 1,
      unread: 2,
      memberCount: 2,
      lastMessageBody: body,
      lastMessageSender: sender,
      lastMessageIsImage: image,
    );

void main() {
  test('캡션 없는 사진 메시지는 "사진" 이라고 말한다 — 빈 줄을 그리지 않는다', () {
    expect(chatRoomPreview(_room(body: '', image: true)), '보리아빠 · 사진');
  });

  test('캡션이 있으면 캡션이다', () {
    expect(chatRoomPreview(_room(body: '공원이에요', image: true)), '보리아빠 · 공원이에요');
  });

  test('글자 메시지와 빈 방은 예전 그대로', () {
    expect(chatRoomPreview(_room(body: '글자')), '보리아빠 · 글자');
    expect(chatRoomPreview(_room(body: null)), '아직 대화가 없어요');
  });
}
