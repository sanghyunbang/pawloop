import 'dart:convert';
import 'package:heat_trip_flutter/features/bookmark/domain/collection_repository.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';

class CollectionRepositoryImpl implements CollectionRepository {
  final String base = (Env.apiBase ?? '').replaceAll(RegExp(r'/+$'), '');

  /// 인증 헤더 부착과 401 갱신은 전부 여기가 한다 (#11).
  final AuthedClient _client = AuthedClient.instance;

  @override
  Future<List<CollectionSummary>> list() async {
    final r = await _client.getJson(Uri.parse('$base/collections'));
    if (r.statusCode != 200) throw Exception('컬렉션 조회 실패');
    final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
    return list
        .map(CollectionSummary.fromJson)
        .toList(); // ★ fromJson이 contentTypeId도 처리
  }

  @override
  Future<CollectionSummary> create(String name) async {
    final r = await _client.postJson(
      Uri.parse('$base/collections'),
      body: {'name': name},
    );
    if (r.statusCode != 200 && r.statusCode != 201)
      throw Exception('컬렉션 생성 실패');
    return CollectionSummary.fromJson(jsonDecode(r.body));
  }

  @override
  Future<void> rename(int id, String name) async {
    final r = await _client.putJson(
      Uri.parse('$base/collections/$id'),
      body: {'name': name},
    );
    if (r.statusCode != 200) throw Exception('이름 변경 실패');
  }

  @override
  Future<void> delete(int id) async {
    final r = await _client.deleteJson(Uri.parse('$base/collections/$id'));
    if (r.statusCode != 204) throw Exception('삭제 실패');
  }
}
