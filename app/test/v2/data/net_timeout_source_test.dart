// 망 요청의 상한을 **아무 데서나 새로 정하지 못하게** 한다 — 이슈 #573.
//
// ## 무엇이 있었나
//
// 상한이 파일마다 흩어져 있었다. 5 · 8 · **12** · 15 · 30 이었고 12 가 아홉 개였다.
// 그중 하나는 주석이 이렇게 적혀 있었다.
//
// > 12초는 `CommunityRepository.timeout` 과 같은 수다.
//
// **그건 근거가 아니라 복사해 온 흔적이다.** 그리고 그 하나가 하필 스플래시를 막는
// `GET /auth/me` 였다 — 서버가 안 뜨면 로고와 점 하나를 12초 동안 보게 된다.
//
// 처음에 `lib/v2/data/` 만 훑고 고쳤다가 `features/auth/` 의 그것을 놓쳤다. 눈으로 훑는
// 것으로는 다음에 또 놓친다.
//
// ## 이 검사가 하는 일
//
// `app/lib` 의 모든 `.dart` 를 읽고, **망 상한처럼 보이는 날숫자**를 찾는다. 예외는
// [_allowed] 에 이름과 **이유**를 함께 적는다 — 목록에 넣는 것 자체가 한 번 생각하는 자리다.
//
// **훑은 개수를 함께 잰다.** 전수 검사의 실패 모드는 "틀린 답" 이 아니라 "아무것도 안 봄"
// 이다. 경로가 틀어지면 파일 0개를 읽고도 초록이 된다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 날숫자를 그대로 둬도 되는 자리. **이름과 이유를 함께 적는다.**
const Map<String, String> _allowed = {
  // 여기가 그 값을 정의하는 곳이다.
  'lib/core/net/net_timeouts.dart': '상한을 정하는 파일 자신',

  // 401 뒤에 조용히 붙는 갱신 왕복이다. 사람이 보는 화면 뒤에 있고, 서버가 401 을
  // 준 이상 **닿기는 닿은 것**이라 못 닿는 경우의 상한과 성격이 다르다.
  'lib/core/net/authed_client.dart': '갱신 왕복 — 401 뒤에만 붙는다',

  // 망 요청이 아니다. 외부 브라우저가 돌아오기를 기다리는 시간이다.
  'lib/v2/data/auth_state.dart': '망 왕복이 아니라 외부 브라우저 대기',

  // 영상 PUT 은 몸통이 커서 따로 잰다. NetTimeouts.long 과 나누는 이유가 그 파일에 있다.
  'lib/v2/data/post_media_repository.dart': '영상 업로드 — 파일 안에 이유가 있다',
};

void main() {
  test('망 상한은 NetTimeouts 가 정한다 — 파일마다 날숫자를 두지 않는다 (#573)', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue,
        reason: 'lib 을 못 찾았다. 경로가 틀어지면 파일 0개를 읽고도 초록이 된다');

    var scanned = 0;
    final offenders = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      scanned++;
      if (_allowed.containsKey(path)) continue;

      final lines = const LineSplitter().convert(entity.readAsStringSync());
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('Duration(seconds:')) continue;
        // 상한처럼 보이는 줄만 — 애니메이션 · 디바운스는 상관없다.
        if (!line.toLowerCase().contains('timeout')) continue;
        offenders.add('$path:${i + 1}  ${line.trim()}');
      }
    }

    // 바닥은 **재서** 정한다. 2026-09-16 에 178개였다 — 처음엔 200 이라고 어림으로
    // 적었다가 이 줄이 빨개져서 알았다. 어림수는 "아무것도 안 봄" 을 못 잡는다.
    expect(scanned, greaterThan(150),
        reason: '훑은 파일이 $scanned개뿐이다 — 경로가 틀어졌는지 본다');
    expect(offenders, isEmpty,
        reason: '망 상한은 NetTimeouts.standard · NetTimeouts.long 을 쓴다.\n'
            '정말 예외라면 이 테스트의 _allowed 에 **이유와 함께** 적는다.\n'
            '${offenders.join('\n')}');
  });

  test('예외 목록이 실재하는 파일만 가리킨다 — 옮긴 파일을 영원히 봐주면 안 된다 (#573)', () {
    for (final path in _allowed.keys) {
      expect(File(path).existsSync(), isTrue,
          reason: '$path 가 없다. 파일이 옮겨졌으면 목록도 따라 옮긴다 — '
              '없는 경로는 아무것도 안 막으면서 막고 있는 것처럼 보인다');
    }
  });
}
