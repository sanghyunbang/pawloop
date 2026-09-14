// 통계 응답의 aiSummaryPending — 서버가 "만드는 중" 이라 하면 읽고, 옛 서버(필드 없음)는 false 다.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';

Map<String, dynamic> _base() => {
      'weekStart': '2026-09-14',
      'weekEnd': '2026-09-20',
      'weekKm': [0.4, 0, 0, 0, 0, 0, 0],
      'weekMinutes': [2, 0, 0, 0, 0, 0, 0],
      'totalKm': 0.4,
      'walkCount': 1,
      'avgKm': 0.4,
      'allTimeKm': 0.4,
      'allTimeCount': 1,
      'allTimeMinutes': 2,
      'topPlaces': [],
      'aiSummary': null,
    };

void main() {
  test('aiSummaryPending: true 를 읽는다', () {
    final stats = ServerWalkStats.parse({..._base(), 'aiSummaryPending': true});

    expect(stats.aiSummaryPending, isTrue);
    expect(stats.aiSummary, isNull);
  });

  test('필드가 없거나 false 면 false — 옛 서버와도 그린다', () {
    expect(ServerWalkStats.parse(_base()).aiSummaryPending, isFalse);
    expect(ServerWalkStats.parse({..._base(), 'aiSummaryPending': false}).aiSummaryPending, isFalse);
    expect(ServerWalkStats.parse({..._base(), 'aiSummaryPending': 'yes'}).aiSummaryPending, isFalse);
  });
}
