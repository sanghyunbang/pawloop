// lib/features/bookmark/service/collection_store_ext.dart

// 컬렉션에서 특정 contentId를 모든 컬렉션에서 제거하는 확장 메서드
// 백엔드에 배치 엔드포인트가 있으면 우선 사용하고, 없으면 컬렉션들을 순회하며 제거

import 'package:heat_trip_flutter/features/bookmark/service/collection_store.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';

extension BulkRemoveEverywhere on CollectionStore {
  /// 주어진 contentId를 포함하는 '모든' 컬렉션에서 제거하고 목록/카운트 갱신
  Future<void> removeContentEverywhere(String contentId) async {
    if (contentId.isEmpty) return;

    final base = (Env.apiBase ?? '').replaceAll(RegExp(r'/+$'), '');
    // 인증 헤더 부착과 401 갱신은 전부 AuthedClient 가 한다 (#11).
    final client = AuthedClient.instance;

    // 1) 배치 엔드포인트가 있다면 먼저 시도 (백엔드에 구현돼 있을 때)
    try {
      final res = await client.postJson(
        Uri.parse('$base/collections/items:removeAll'),
        body: {'contentId': contentId},
      );
      if (res.statusCode == 200) {
        await refresh(); // 카운트/프리뷰 갱신
        return;
      }
    } catch (_) {
      // 무시하고 폴백 수행
    }

    // 2) 폴백: 모든 컬렉션을 순회하며 제거 시도
    final snapshot = List.of(items); // 현재 메모리상의 컬렉션 스냅샷
    for (final c in snapshot) {
      try {
        final url = Uri.parse('$base/collections/${c.id}/items/$contentId');
        await client.deleteJson(url);
      } catch (_) {
        // 개별 실패는 넘어가고 계속
      }
    }

    await refresh(); // 최종 갱신
  }
}
