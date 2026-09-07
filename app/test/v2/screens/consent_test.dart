// 약관 동의 — 게이트와 화면. 이슈 #180 · #190.
//
// ## 여기서 재는 것
//
//  1. 서버가 정본이다. 서버가 지금 버전으로 동의를 갖고 있으면 지나가고, **옛 버전이면
//     다시 묻는다** — 약관을 올렸는데 아무도 새 조항을 안 본 것이 #190 의 출발점이었다.
//  2. 서버를 못 부르면 기기 캐시를 쓰되, 캐시에도 없으면 묻는다. 그 방향의 실수(한 번 더
//     묻기)가 반대(동의 없이 진행)보다 낫다.
//  3. 적을 때 서버가 안 받아 주면 넘어가지 않고, 기기에도 안 적는다.
//  4. 계정마다 따로 센다. 한 기기를 가족이 나눠 쓸 때 앞사람의 동의가 뒷사람에게 적용되면
//     그 사람은 약관을 본 적이 없는데 동의한 것이 된다.
//  5. 화면 — 필수를 다 안 채우면 못 넘어가는가. 위치기반서비스 동의가 필수인가.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/consent_gate.dart';
import 'package:heat_trip_flutter/v2/data/consent_repository.dart';
import 'package:heat_trip_flutter/v2/screens/consent_screen.dart';
import 'package:heat_trip_flutter/v2/screens/settings/legal_document_screen.dart';

/// 서버 흉내. 무엇을 돌려줄지, 받았는지, 죽었는지를 테스트가 정한다.
class _FakeServer implements ConsentRepository {
  _FakeServer({this.stored = const [], this.dead = false});

  List<ServerConsent> stored;
  bool dead;
  final recorded = <List<ConsentEntry>>[];

  @override
  Future<List<ServerConsent>> fetch() async {
    if (dead) throw const ConsentFailure();
    return stored;
  }

  @override
  Future<List<ServerConsent>> record(List<ConsentEntry> entries) async {
    if (dead) throw const ConsentFailure();
    recorded.add(entries);
    stored = [
      for (final e in entries)
        ServerConsent(kind: e.kind, version: e.version, agreed: e.agreed, at: DateTime.utc(2026)),
    ];
    return stored;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

ServerConsent _agreed(LegalDocument doc, {String? version}) => ServerConsent(
    kind: doc.kind, version: version ?? doc.version, agreed: true, at: DateTime.utc(2026));

/// 필수 셋을 지금 버전으로 동의한 서버 상태.
List<ServerConsent> _allCurrent() => [
      for (final d in ConsentGate.requiredDocuments) _agreed(d),
    ];

ConsentGate _gate(_FakeServer server) => ConsentGate(repository: server);

/// 동의가 끝난 횟수. **값이 아니라 통을 돌려준다** — 값으로 돌려주면 호출부가 든 것은
/// 그때의 0 이고, 화면이 올려도 그 숫자는 영원히 0 이다.
Future<ValueNotifier<int>> _pump(WidgetTester t,
    {required ConsentGate gate, int userId = 11}) async {
  final agreed = ValueNotifier<int>(0);
  await t.pumpWidget(MaterialApp(
    home: ConsentScreen(userId: userId, onAgreed: () => agreed.value++, gate: gate),
  ));
  await t.pumpAndSettle();
  return agreed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('게이트 — 서버가 정본', () {
    test('서버에 아무것도 없으면 동의하지 않은 것이다', () async {
      expect(await _gate(_FakeServer()).hasAgreed(11), isFalse);
    });

    test('서버가 지금 버전으로 필수 셋을 갖고 있으면 지나간다', () async {
      expect(await _gate(_FakeServer(stored: _allCurrent())).hasAgreed(11), isTrue);
    });

    test('옛 버전에 동의한 사람은 다시 묻는다 — 약관을 올린 의미가 그것이다', () async {
      final server = _FakeServer(stored: [
        _agreed(LegalDocument.terms, version: 'v1.0'),
        _agreed(LegalDocument.privacy),
        _agreed(LegalDocument.location),
      ]);

      expect(await _gate(server).hasAgreed(11), isFalse, reason: '''
#190 의 출발점: 약관을 v1.2 로 올렸는데 저장 키에 버전이 없어 아무도 새 조항을 다시
보지 않았다. 버전이 하나라도 다르면 동의하지 않은 것이다.''');
    });

    test('필수 하나가 빠지면 다시 묻는다 — 위치기반서비스가 그 하나여도', () async {
      final server = _FakeServer(stored: [
        _agreed(LegalDocument.terms),
        _agreed(LegalDocument.privacy),
      ]);
      expect(await _gate(server).hasAgreed(11), isFalse);
    });

    test('철회한 문서는 동의로 안 센다 — 마지막 기록이 false 다', () async {
      final server = _FakeServer(stored: [
        _agreed(LegalDocument.terms),
        _agreed(LegalDocument.privacy),
        ServerConsent(
            kind: ConsentKind.location, version: LegalDocument.location.version,
            agreed: false, at: DateTime.utc(2026)),
      ]);
      expect(await _gate(server).hasAgreed(11), isFalse);
    });

    test('동의하면 서버에 필수 셋 + 마케팅이 지금 버전으로 적힌다', () async {
      final server = _FakeServer();

      expect(await _gate(server).markAgreed(11, marketing: false), isTrue);

      final sent = server.recorded.single;
      expect(sent.map((e) => e.kind).toSet(), ConsentKind.values.toSet(),
          reason: '마케팅은 거부도 기록이다 — 안 보내면 서버는 물어봤는지조차 모른다');
      for (final doc in LegalDocument.values) {
        final entry = sent.firstWhere((e) => e.kind == doc.kind);
        expect(entry.version, doc.version, reason: '${doc.name} 은 지금 문서 버전으로 적혀야 한다');
        expect(entry.agreed, doc == LegalDocument.marketing ? isFalse : isTrue);
      }
      expect(await _gate(server).hasAgreed(11), isTrue);
    });

    test('서버가 안 받아 주면 넘어가지 않고 기기에도 안 적는다', () async {
      final server = _FakeServer(dead: true);

      expect(await _gate(server).markAgreed(11, marketing: true), isFalse, reason: '''
기기에만 적고 넘어가면 서버는 여전히 모르는 채다 — 그게 바로 이 이슈가 없애려던 상태다.''');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ConsentGate.keyFor(11)), isNull);
    });
  });

  group('게이트 — 서버를 못 부를 때', () {
    test('캐시가 지금 버전이면 지나간다 — 비행기 모드에서 앱을 못 쓰게 하지 않는다', () async {
      final alive = _FakeServer();
      await _gate(alive).markAgreed(11, marketing: false);

      final dead = _FakeServer(dead: true);
      expect(await _gate(dead).hasAgreed(11), isTrue);
    });

    test('캐시가 옛 버전이면 묻는다', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ConsentGate.keyFor(11),
          '{"TERMS":"v0.9","PRIVACY":"${LegalDocument.privacy.version}","LOCATION":"${LegalDocument.location.version}"}');

      expect(await _gate(_FakeServer(dead: true)).hasAgreed(11), isFalse);
    });

    test('캐시도 없으면 묻는다 — 그 방향의 실수가 반대보다 낫다', () async {
      expect(await _gate(_FakeServer(dead: true)).hasAgreed(11), isFalse);
    });

    test('옛 불리언 키(v1)만 있으면 안 센다 — 무엇에 동의했는지 말하지 못한다', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('account_consent_v1_11', true);

      expect(await _gate(_FakeServer(dead: true)).hasAgreed(11), isFalse);
    });

    test('서버가 답하면 캐시를 서버로 맞춘다 — 다른 기기에서 철회했을 수 있다', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ConsentGate.keyFor(11),
          '{"TERMS":"${LegalDocument.terms.version}","PRIVACY":"${LegalDocument.privacy.version}","LOCATION":"${LegalDocument.location.version}"}');

      expect(await _gate(_FakeServer(stored: const [])).hasAgreed(11), isFalse);
      expect(prefs.getString(ConsentGate.keyFor(11)), '{}',
          reason: '서버가 비었다고 하면 캐시도 비어야 한다 — 안 그러면 다음 오프라인 때 옛 캐시로 지나간다');
    });
  });

  group('게이트 — 계정과 선택 항목', () {
    test('계정마다 따로 센다 — 앞사람의 동의가 뒷사람에게 적용되면 안 된다', () async {
      final server = _FakeServer();
      await _gate(server).markAgreed(11, marketing: false);

      // 12번 계정으로 보면 서버(같은 가짜라 같은 상태)를 못 부르는 상황에서 캐시가 없다.
      expect(await _gate(_FakeServer(dead: true)).hasAgreed(12), isFalse,
          reason: '한 기기를 가족이 나눠 쓸 수 있다');
    });

    test('마케팅은 필수와 따로 센다', () async {
      final server = _FakeServer();
      await _gate(server).markAgreed(11, marketing: false);
      expect(await _gate(server).hasAgreed(11), isTrue);
      expect(await _gate(server).marketingOptIn(11), isFalse,
          reason: '한 값에 묶으면 마케팅 거부가 가입 거부가 된다');

      await _gate(server).markAgreed(11, marketing: true);
      expect(await _gate(server).marketingOptIn(11), isTrue);
    });

    test('지우면 캐시가 사라진다 — 탈퇴 뒤 같은 id 로 온 사람에게 적용되면 안 된다', () async {
      final server = _FakeServer();
      await _gate(server).markAgreed(11, marketing: true);
      await _gate(server).clear(11);

      expect(await _gate(_FakeServer(dead: true)).hasAgreed(11), isFalse);
      expect(await _gate(server).marketingOptIn(11), isFalse);
    });
  });

  group('화면', () {
    testWidgets('미체크는 빈 원이다 — 회색 체크는 "이미 체크된 비활성" 처럼 읽힌다(#325)', (t) async {
      await _pump(t, gate: _gate(_FakeServer()));

      expect(find.byIcon(Icons.check), findsNothing, reason: '아무것도 안 골랐는데 체크가 보이면 안 된다');

      await t.tap(find.text('전체 동의 (선택 항목 포함)'));
      await t.pump();
      expect(find.byIcon(Icons.check), findsNWidgets(5), reason: '전체 + 필수 3 + 선택 1');
    });

    testWidgets('필수 셋을 다 안 채우면 못 넘어간다', (t) async {
      final agreed = await _pump(t, gate: _gate(_FakeServer()));

      await t.tap(find.text('동의하고 시작하기'));
      await t.pumpAndSettle();
      expect(agreed.value, 0);

      // 둘만 채워도 안 된다.
      await t.tap(find.text('이용약관'));
      await t.tap(find.text('개인정보처리방침'));
      await t.pump();
      await t.tap(find.text('동의하고 시작하기'));
      await t.pumpAndSettle();
      expect(agreed.value, 0, reason: '위치기반서비스 동의가 빠졌다');
    });

    testWidgets('위치기반서비스가 필수다 — 산책 기록이 이 앱의 본체다', (t) async {
      await _pump(t, gate: _gate(_FakeServer()));
      expect(find.text('[필수] '), findsNWidgets(3));
      expect(find.text('[선택] '), findsOneWidget);
      expect(find.text('위치기반서비스 이용약관'), findsOneWidget);
    });

    testWidgets('필수 셋을 채우면 넘어간다 — 마케팅은 안 해도 된다', (t) async {
      final server = _FakeServer();
      final agreed = await _pump(t, gate: _gate(server));

      await t.tap(find.text('이용약관'));
      await t.tap(find.text('개인정보처리방침'));
      await t.tap(find.text('위치기반서비스 이용약관'));
      await t.pump();
      await t.tap(find.text('동의하고 시작하기'));
      await t.pumpAndSettle();

      expect(agreed.value, 1);
      expect(server.recorded, hasLength(1), reason: '화면이 넘어갔으면 서버에 적혔어야 한다');
    });

    testWidgets('서버가 안 받아 주면 넘어가지 않고 말한다', (t) async {
      final agreed = await _pump(t, gate: _gate(_FakeServer(dead: true)));

      await t.tap(find.text('이용약관'));
      await t.tap(find.text('개인정보처리방침'));
      await t.tap(find.text('위치기반서비스 이용약관'));
      await t.pump();
      await t.tap(find.text('동의하고 시작하기'));
      await t.pumpAndSettle();

      expect(agreed.value, 0, reason: '삼키면 다음 실행에 또 뜨고, 사용자는 "동의했는데 왜 또 묻지" 를 겪는다');
      expect(find.text('동의를 저장하지 못했어요. 다시 시도해 주세요'), findsOneWidget);
    });
  });
}
