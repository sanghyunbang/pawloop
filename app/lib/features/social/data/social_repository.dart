import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/features/auth/service/token_storage.dart';
import '../domain/emotion_card.dart';

/// 소셜(감정 카드 공유 + 리액션) 리포지토리.
class SocialRepository {
  String get _baseUrl =>
      Env.apiBase.isNotEmpty ? Env.apiBase : 'http://10.0.2.2:8080';

  Future<Map<String, String>> _headers() async {
    final token = await TokenStorage.getToken();
    return {
      'Content-Type': 'application/json; charset=utf-8',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// 함께 피드 (최신순).
  Future<List<EmotionCard>> feed({int limit = 50}) async {
    final uri = Uri.parse('$_baseUrl/api/social/cards')
        .replace(queryParameters: {'limit': '$limit'});
    final res = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('feed ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! List) return const [];
    return body
        .whereType<Map<String, dynamic>>()
        .map(EmotionCard.fromJson)
        .toList();
  }

  /// 내 기록을 감정 카드로 공유.
  Future<void> share({
    required String moodKey,
    required String body,
    String? placeName,
    int? placeId,
    String? handle,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/social/cards');
    final res = await http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({
            'moodKey': moodKey,
            'body': body,
            if (placeName != null) 'placeName': placeName,
            if (placeId != null) 'placeId': placeId,
            if (handle != null) 'handle': handle,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode ~/ 100 != 2) {
      throw Exception('share ${res.statusCode} ${res.body}');
    }
  }

  /// 리액션 토글. 갱신된 {reactions, myReactions} 반환.
  Future<(Map<String, int>, List<String>)> react({
    required int cardId,
    required String type,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/social/cards/$cardId/reactions');
    final res = await http
        .post(uri, headers: await _headers(), body: jsonEncode({'type': type}))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode ~/ 100 != 2) {
      throw Exception('react ${res.statusCode}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final counts = <String, int>{};
    final rx = j['reactions'];
    if (rx is Map) {
      rx.forEach((k, val) => counts['$k'] = (val as num?)?.toInt() ?? 0);
    }
    final mine =
        (j['myReactions'] as List? ?? const []).map((e) => '$e').toList();
    return (counts, mine);
  }

  /// 카드 댓글 목록 (오래된 순).
  Future<List<CardComment>> comments(int cardId) async {
    final uri = Uri.parse('$_baseUrl/api/social/cards/$cardId/comments');
    final res = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('comments ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! List) return const [];
    return body
        .whereType<Map<String, dynamic>>()
        .map(CardComment.fromJson)
        .toList();
  }

  /// 댓글 작성.
  Future<CardComment> addComment({
    required int cardId,
    required String body,
    String? handle,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/social/cards/$cardId/comments');
    final res = await http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({
            'body': body,
            if (handle != null && handle.isNotEmpty) 'handle': handle,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode ~/ 100 != 2) {
      throw Exception('addComment ${res.statusCode}');
    }
    return CardComment.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
