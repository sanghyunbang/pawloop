import 'dart:convert';
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import '../domain/emotion_map_place.dart';

/// 감정 지도 장소 조회 리포지토리.
class EmotionMapRepository {
  /// 인증 헤더 부착과 401 갱신은 전부 여기가 한다 (#11).
  final AuthedClient _client = AuthedClient.instance;

  String get _baseUrl =>
      Env.apiBase.isNotEmpty ? Env.apiBase : 'http://10.0.2.2:8080';

  Future<List<EmotionMapPlace>> fetchNearby({
    required double lat,
    required double lng,
    double radiusKm = 8,
    int limit = 200,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/curation/places/emotion-map').replace(
      queryParameters: {
        'lat': '$lat',
        'lng': '$lng',
        'radiusKm': '$radiusKm',
        'limit': '$limit',
      },
    );
    final res = await _client
        .getJson(uri)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw Exception('emotion-map 응답 ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! List) return const [];
    return body
        .whereType<Map<String, dynamic>>()
        .map(EmotionMapPlace.fromJson)
        .toList();
  }

  /// 감정 + 키워드 장소 검색. (탐색 화면)
  Future<List<EmotionMapPlace>> search({
    String? mood,
    String? q,
    double? lat,
    double? lng,
    int limit = 60,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (mood != null && mood.trim().isNotEmpty) params['mood'] = mood.trim();
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    if (lat != null && lng != null) {
      params['lat'] = '$lat';
      params['lng'] = '$lng';
    }
    final uri = Uri.parse('$_baseUrl/api/curation/places/search')
        .replace(queryParameters: params);
    final res = await _client
        .getJson(uri)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('search 응답 ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! List) return const [];
    return body
        .whereType<Map<String, dynamic>>()
        .map(EmotionMapPlace.fromJson)
        .toList();
  }
}
