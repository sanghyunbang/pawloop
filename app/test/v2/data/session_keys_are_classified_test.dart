// 기기에 남는 키는 전부 **분류돼 있어야 한다** — 이슈 #513.
//
// 저장소를 하나 더 만들고 "세션이 끝나면 지울 것" 목록에 안 넣는 날이 온다. 그러면 그
// 값은 다음 사람 화면에서만 드러나고, 그때는 이미 앞사람의 동네나 일정 제목이 보인 뒤다.
//
// 그래서 여기서 소스를 훑어 `SharedPreferences` 키 상수를 전부 모으고, 그것이
// `sessionScopedKeys`(지운다) 나 아래 [_deviceKeys](안 지운다) 중 **한쪽에** 적혀
// 있는지 본다. 새 키를 만들면 어느 쪽인지 적기 전까지 빨간불이다.
//
// 계정 id 가 붙는 키(`ConsentGate.keyFor` · `ChatTermsGate.keyFor`)는 함수라 여기 안
// 걸린다. 걸릴 필요도 없다 — 사람마다 다른 키라 섞이지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/session_traces.dart';

/// 세션이 끝나도 **남기는** 키와 그 이유. 이유를 못 적겠으면 지우는 쪽이다.
const Map<String, String> _deviceKeys = <String, String>{
  'intro_seen_v1': '소개는 기기에 한 번이다. 다음 사람이 다시 볼 이유가 없다',
  'login_terms_agreed_v1': '로그인 전 약관 체크는 계정이 생기기 전의 기기 사실이다(문서 버전과 함께 남는다). '
      '계정마다의 동의는 로그인 뒤 동의 화면이 서버에 따로 남긴다',
  'location_paused_v1': '끈 것을 켜면 안 된다 — 지우면 위치 수집이 도로 켜진다(위치정보법 제24조)',
  'location_priming_asked_v1': '"OS 권한을 한 번 물었다" 는 기기의 사실이다',
  'place_catalog_etag_v1': '공개 카탈로그 캐시라 개인의 것이 아니다',
  'place_catalog_checked_at_v1': '같은 카탈로그를 언제 확인했는지다. 개인의 것이 아니다',
  'access_token': '토큰은 AuthTokenStore 가 지운다(#12 — 지우는 경로는 한 곳)',
  'refresh_token': '토큰은 AuthTokenStore 가 지운다',
  'jwt_token': '구버전 평문 토큰. 시작할 때 한 번 옮기고 지운다',
};

/// `static const [String] <이름Key|key|prefix> = '<값>';`
final _keyConstant = RegExp(
    r"""static\s+const\s+(?:String\s+)?\w*(?:[kK]ey|prefix)\s*=\s*'([^']+)'""");

/// `prefs.getString('foo')` 처럼 키를 문자열 그대로 쓰는 자리.
final _literalKeyCall = RegExp(r"""\.(?:get|set|remove)[A-Za-z]*\(\s*'""");

void main() {
  List<File> prefsFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => f.readAsStringSync().contains('shared_preferences'))
      .toList();

  String rel(File f) => f.path.replaceAll(r'\', '/');

  /// 주석은 뺀다 — 이 규칙을 설명하는 주석이 자기 검사에 걸리면 안 된다.
  String code(File f) => f
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i < 0 ? l : l.substring(0, i);
      })
      .join('\n');

  test('SharedPreferences 키 상수는 전부 "지운다" 나 "남긴다" 중 한쪽에 적혀 있다', () {
    final classified = <String>{...sessionScopedKeys, ...sessionScopedKeyPrefixes, ..._deviceKeys.keys};
    final unclassified = <String>[];

    for (final f in prefsFiles()) {
      for (final m in _keyConstant.allMatches(code(f))) {
        final key = m.group(1)!;
        if (!classified.contains(key)) unclassified.add('$key  ← ${rel(f)}');
      }
    }

    expect(unclassified, isEmpty,
        reason: '새 키는 session_traces.dart 의 sessionScopedKeys 에 넣거나, '
            '이 테스트의 _deviceKeys 에 **남기는 이유와 함께** 적는다. '
            '어느 쪽도 아니면 로그아웃 뒤 다음 사람이 그 값을 본다');
  });

  test('키를 문자열 그대로 쓰는 자리가 없다 — 이름 있는 상수라야 여기서 보인다', () {
    final offenders = <String>[];

    for (final f in prefsFiles()) {
      final text = code(f);
      for (final line in text.split('\n')) {
        if (!line.contains('prefs') && !line.contains('_prefs')) continue;
        if (_literalKeyCall.hasMatch(line)) offenders.add('${rel(f)}: ${line.trim()}');
      }
    }

    expect(offenders, isEmpty,
        reason: '문자열을 그 자리에 적으면 위 검사가 그 키를 못 본다 — '
            '상수(또는 사람마다 다른 키면 keyFor 같은 함수)로 둔다');
  });

  test('남긴다고 적은 키에는 이유가 함께 있다', () {
    for (final entry in _deviceKeys.entries) {
      expect(entry.value.length, greaterThan(10),
          reason: '${entry.key} 를 왜 남기는지 한 줄로 적는다 — 이유 없이 남기면 다음 사람이 못 고친다');
    }
  });
}
