import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';

/// 컬렉션 1개 요약 정보
class CollectionInfo {
  final int id;
  String name;
  int count;
  String? latestItemContentId;

  CollectionInfo({
    required this.id,
    required this.name,
    required this.count,
    this.latestItemContentId,
  });

  factory CollectionInfo.fromJson(Map<String, dynamic> j) {
    return CollectionInfo(
      id: (j['id'] as num).toInt(),
      name: (j['name'] ?? '').toString(),
      count: (j['count'] as num?)?.toInt() ?? 0,
      latestItemContentId: j['latestItemContentId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'count': count,
    if (latestItemContentId != null) 'latestItemContentId': latestItemContentId,
  };
}

/// 앱 전역에서 사용하는 컬렉션 관리 스토어
class CollectionStore extends ChangeNotifier {
  CollectionStore._internal();
  static final CollectionStore instance = CollectionStore._internal();

  final String _base = Env.apiBase.replaceAll(RegExp(r'/+$'), '');

  /// 인증 헤더 부착과 401 갱신은 전부 여기가 한다 (#11).
  final AuthedClient _client = AuthedClient.instance;

  final List<CollectionInfo> _items = [];
  List<CollectionInfo> get items => List.unmodifiable(_items);

  CollectionInfo? _find(int id) =>
      _items.firstWhere((e) => e.id == id, orElse: () => null as dynamic);

  /// 서버에서 최신 목록으로 동기화
  Future<void> refresh() async {
    final res = await _client.getJson(Uri.parse('$_base/collections'));
    if (res.statusCode != 200) {
      throw Exception('컬렉션 조회 실패(${res.statusCode})');
    }
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    _items
      ..clear()
      ..addAll(list.map(CollectionInfo.fromJson));
    notifyListeners();
  }

  /// 컬렉션 생성
  Future<int?> create(String name) async {
    final res = await _client.postJson(
      Uri.parse('$_base/collections'),
      body: {'name': name},
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final created = CollectionInfo.fromJson(j);
        _items.insert(0, created);
        notifyListeners();
        return created.id;
      } catch (_) {
        // 응답에 본문이 없거나 포맷이 다르면 전체 새로고침
        await refresh();
        return null;
      }
    } else {
      throw Exception('컬렉션 생성 실패(${res.statusCode})');
    }
  }

  /// 이름 변경
  Future<void> rename(int id, String name) async {
    final res = await _client.putJson(
      Uri.parse('$_base/collections/$id'),
      body: {'name': name},
    );
    if (res.statusCode != 200) {
      throw Exception('컬렉션 이름 변경 실패(${res.statusCode})');
    }
    final t = _find(id);
    if (t != null) {
      t.name = name;
      notifyListeners();
    }
  }

  /// 컬렉션 삭제
  Future<void> remove(int id) async {
    final res = await _client.deleteJson(Uri.parse('$_base/collections/$id'));
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception('컬렉션 삭제 실패(${res.statusCode})');
    }
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  /// ★ 컬렉션에 아이템 추가 (하트 바텀시트에서 사용)
  /// 백엔드 엔드포인트 가정: POST /collections/{id}/items  body: { "contentId": "..." }
  Future<void> addItem(int collectionId, String contentId) async {
    final res = await _client.postJson(
      Uri.parse('$_base/collections/$collectionId/items'),
      body: {'contentId': contentId},
    );
    if (res.statusCode != 200 &&
        res.statusCode != 201 &&
        res.statusCode != 204) {
      throw Exception('컬렉션 항목 추가 실패(${res.statusCode})');
    }

    // 로컬 즉시 반영
    final t = _find(collectionId);
    if (t != null) {
      t.count += 1;
      t.latestItemContentId = contentId;
      notifyListeners();
    } else {
      // 혹시 목록에 없으면 전체 동기화
      await refresh();
    }
  }

  /// (옵션) 컬렉션에서 아이템 제거가 필요하면 사용
  Future<void> removeItem(int collectionId, String contentId) async {
    final res = await _client.deleteJson(
      Uri.parse('$_base/collections/$collectionId/items/$contentId'),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('컬렉션 항목 제거 실패(${res.statusCode})');
    }
    final t = _find(collectionId);
    if (t != null) {
      t.count = (t.count > 0) ? t.count - 1 : 0;
      // latestItemContentId는 서버 정답을 모르면 건드리지 않음(정확도 우선)
      notifyListeners();
    }
  }
}
