// 케어 항목·기록의 **계약 키**를 잠근다 — 이슈 #560.
//
// 이 파일이 재는 것은 하나다: <b>서버가 보낸 것을 앱이 안 흘리는가.</b>
//
// #560 전에는 `CareLogEntry.tryParse` 가 종류를 못 읽으면 그 줄을 **통째로 버렸다.**
// 직접 만든 항목의 기록은 종류가 비어 있으므로, 그 규칙이 남아 있으면 사용자가 만든
// "양치" 를 눌러도 **카드에 아무 일도 안 일어난다** — 서버에는 쌓이는데 화면만 조용한,
// 이 저장소가 여러 번 겪은 모양이다.

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/family_repository.dart';

Map<String, dynamic> _log({String? type, int? careItemId}) => {
      'id': 41,
      'dogId': null,
      'groupId': 3,
      'careItemId': careItemId,
      'type': type,
      'doneBy': {'userId': 11, 'nickname': '엄마'},
      'occurredAt': '2026-09-16T05:20:00Z',
      'memo': null,
    };

void main() {
  group('CareLogEntry', () {
    test('종류가 없어도 안 버린다 — 직접 만든 항목의 기록이다', () {
      final entry = CareLogEntry.tryParse(_log(careItemId: 9));

      expect(entry, isNotNull);
      expect(entry!.type, isNull);
      expect(entry.careItemId, 9);
    });

    test('기본 일곱의 기록은 종류와 칸을 함께 든다', () {
      final entry = CareLogEntry.tryParse(_log(type: 'meal', careItemId: 2));

      expect(entry!.type, ServerCareType.meal);
      expect(entry.careItemId, 2,
          reason: '서버가 푼 값이다 — 앱이 종류로 칸을 다시 찾지 않는다');
    });

    test('모르는 종류는 종류만 비우고 줄은 남긴다 — 서버가 종류를 늘려도 화면이 안 빈다', () {
      final entry = CareLogEntry.tryParse(_log(type: 'brush', careItemId: 9));

      expect(entry, isNotNull);
      expect(entry!.type, isNull);
      expect(entry.careItemId, 9);
    });

    test('시각을 못 읽으면 버린다 — 언제 한 일인지 모르면 그릴 자리가 없다', () {
      final broken = _log(type: 'meal')..['occurredAt'] = '언제인지 모름';

      expect(CareLogEntry.tryParse(broken), isNull);
    });
  });

  group('CareItemEntry', () {
    Map<String, dynamic> item({
      String? systemType,
      String? archivedAt,
      int? dailyTarget,
      Object? name = '양치',
    }) =>
        {
          'id': 9,
          'dogId': 4,
          'name': name,
          'icon': 'tooth',
          'systemType': systemType,
          'dailyTarget': dailyTarget,
          'sortOrder': 7,
          'archivedAt': archivedAt,
        };

    test('키를 하나도 안 흘린다', () {
      final parsed = CareItemEntry.tryParse(
          item(systemType: null, dailyTarget: 2, archivedAt: '2026-09-16T03:00:00Z'))!;

      expect(parsed.id, 9);
      expect(parsed.dogId, 4);
      expect(parsed.name, '양치');
      expect(parsed.icon, 'tooth');
      expect(parsed.dailyTarget, 2);
      expect(parsed.sortOrder, 7);
      expect(parsed.archived, isTrue);
    });

    test('기본 항목은 종류를 든다 — 부가 기능이 붙는 자리다', () {
      final parsed = CareItemEntry.tryParse(item(systemType: 'vet'))!;

      expect(parsed.systemType, ServerCareType.vet);
      expect(parsed.isSystem, isTrue,
          reason: '기본 배지에만 "주변 찾기" 같은 것이 붙는다(사장님, 2026-09-16)');
    });

    test('직접 만든 항목은 종류가 없다', () {
      final parsed = CareItemEntry.tryParse(item())!;

      expect(parsed.systemType, isNull);
      expect(parsed.isSystem, isFalse);
    });

    test('이름이 비면 버린다 — 그릴 것이 없는 칸이다', () {
      expect(CareItemEntry.tryParse(item(name: '')), isNull);
      expect(CareItemEntry.tryParse(item(name: null)), isNull);
    });
  });
}
