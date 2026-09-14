// 방 목록의 마지막 말 시각 (#452) — 오늘은 HH:mm, 어제는 "어제", 말이 없으면 없다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/screens/chat_list_screen.dart';

const _base = 'https://api.test';

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT';
  @override
  Future<String?> readRefreshToken() async => 'RT';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

String _room(int id, String title, {String? at}) =>
    '{"id":$id,"title":"$title","tag":"가족","lastSeq":3,"lastReadSeq":3,"unread":0,"memberCount":2,"myRole":"OWNER","muted":false'
    '${at == null ? '' : ',"lastMessage":{"id":9,"roomId":$id,"roomSeq":3,"senderUserId":8,"senderName":"보리아빠","contentType":"text","body":"저녁 산책 갈까요?","createdAt":"$at","hiddenByBlock":false}'}'
    '}';

ChatRepository _repo(String rooms) => ChatRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((request) async => http.Response(rooms, 200,
            headers: {'content-type': 'application/json; charset=utf-8'})),
        baseUrl: _base,
        store: _Tokens(),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: '보리아빠'));
  });

  testWidgets('오늘 온 말은 HH:mm, 어제 온 말은 "어제", 말이 없는 방은 시각이 없다', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9, 7);
    final yesterday = today.subtract(const Duration(days: 1));
    final rooms = '[${_room(1, "우리 가족", at: today.toUtc().toIso8601String())},'
        '${_room(2, "옆집 가족", at: yesterday.toUtc().toIso8601String())},'
        '${_room(3, "새 방")}]';

    await tester.pumpWidget(MaterialApp(home: ChatListScreen(repository: _repo(rooms))));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-time-1')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('room-time-1'))).data, '09:07');
    expect(tester.widget<Text>(find.byKey(const Key('room-time-2'))).data, '어제');
    expect(find.byKey(const Key('room-time-3')), findsNothing, reason: '말이 없는 방에 시각을 지어내지 않는다');
  });
}
