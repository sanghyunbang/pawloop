// 버튼이 달린 말풍선은 `persist:` 를 반드시 적는다 — 이슈 #531.
//
// ## 무엇이 있었나
//
// 산책을 저장하면 `산책이 기록됐어요 · 보기` 가 떴고, 적어 둔 시간은 3.2초였다. 그런데
// 에뮬레이터에서 **6분 뒤에도 그대로**였다. 이 말풍선은 화면 맨 아래 **탭 바를 덮는다** —
// 홈·지도·일정·커뮤니티·채팅 어느 것도 누를 수 없었다.
//
// 플러터 3.32 부터 `SnackBar` 는 `action` 이 있으면 `persist` 가 **기본 참**이고, `persist`
// 면 `duration` 을 **통째로 무시한다**(`material/snack_bar.dart` 의 `persist ?? action != null`,
// `material/scaffold.dart` 의 `if (snackBar.persist) return;`). 적어 둔 3.2초가 조용히
// 거짓말이 되어 있었다.
//
// ## 왜 눈으로 못 지키나
//
// 새 말풍선을 만드는 사람이 플러터의 이 기본값을 알 이유가 없다. `duration` 을 적어 놓고
// "6초 뒤 사라진다" 고 믿는 것이 자연스럽다. 게다가 **테스트도 안 잡았다** — 저장 직후만
// 보고 시간을 안 밀면 초록이다(`create_screen_saved_test.dart` 가 그랬다).
//
// 그래서 여기서 소스로 잠근다: `lib/` 안의 `SnackBar(` 중 `action:` 이 있는데 `persist:`
// 를 안 적은 것이 하나라도 있으면 빨간불이다. 값은 `v2/widgets/snack.dart` 의
// `snackBarPersists(context)` 가 정한다 — 낭독기를 쓸 때만 남긴다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../v2/support/dart_source.dart';

void main() {
  test('lib/ 의 버튼 달린 말풍선은 전부 persist: 를 적었다 — 안 적으면 영원히 남는다', () {
    final offenders = <String>[];

    for (final file in _dartFilesUnder('lib')) {
      final source = file.readAsStringSync();
      for (final line in offendingSnackBarLines(source)) {
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'SnackBar 는 action 이 있으면 persist 가 기본 참이라 duration 을 무시합니다.\n'
          '말풍선이 탭 바 위에 영원히 남습니다(#531).\n'
          "persist: snackBarPersists(context) 를 적으세요 — v2/widgets/snack.dart.\n"
          '${offenders.join('\n')}',
    );
  });

  test('훑은 자리가 실제로 있다 — 아무것도 못 찾는 검사는 언제나 초록이다', () {
    var seen = 0;
    for (final file in _dartFilesUnder('lib')) {
      seen += snackBarCallLines(file.readAsStringSync()).length;
    }

    expect(seen, greaterThan(30),
        reason: '이 저장소에는 SnackBar( 가 수십 개 있습니다. 한 자릿수면 정규식이나 '
            '경로가 깨진 것이지 코드가 깨끗해진 것이 아닙니다 — 훑은 개수: $seen');
  });

  group('장치가 실제로 가르는가 — 손으로 심어서 잰다', () {
    test('버튼은 있는데 persist 가 없으면 잡는다', () {
      expect(
        offendingSnackBarLines('''
void f() {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: const Text('끊겼어요'),
    duration: const Duration(seconds: 6),
    action: SnackBarAction(label: '다시', onPressed: () => retry()),
  ));
}
'''),
        [2],
        reason: '이것이 #531 그 자체다 — 줄 번호까지 맞아야 고칠 자리를 가리킨다',
      );
    });

    test('persist 를 적었으면 넘어간다', () {
      expect(
        offendingSnackBarLines('''
SnackBar(
  content: Text(m),
  action: SnackBarAction(label: '보기', onPressed: open),
  persist: snackBarPersists(context),
)
'''),
        isEmpty,
      );
    });

    test('버튼이 없으면 상관없다 — 그때는 duration 이 그대로 산다', () {
      expect(
        offendingSnackBarLines("SnackBar(content: Text(m), duration: d)"),
        isEmpty,
      );
    });

    test('주석 속 예시는 안 센다 — 안 그러면 이 규칙을 설명하는 파일이 스스로 걸린다', () {
      expect(
        offendingSnackBarLines('''
// SnackBar(content: Text('x'), action: SnackBarAction(label: 'y', onPressed: f))
/* SnackBar(content: Text('x'), action: SnackBarAction(label: 'y', onPressed: f)) */
'''),
        isEmpty,
      );
    });

    test('문자열 속 // 가 뒤를 삼키지 않는다', () {
      expect(
        offendingSnackBarLines('''
SnackBar(
  content: Text('https://heattrip.app 에서 보기'),
  action: SnackBarAction(label: '열기', onPressed: open),
)
'''),
        [1],
        reason: "주석을 걷을 때 'https://…' 의 // 를 주석으로 보면 그 뒤가 통째로 사라져 "
            'action 을 못 본다 — 그러면 진짜 위반이 조용히 통과한다',
      );
    });

    test('닫는 괄호를 콜백 속 괄호와 헷갈리지 않는다', () {
      // 인자 목록이 여기서 끝난다고 착각하면 action 이 밖으로 밀려 안 보인다.
      expect(
        offendingSnackBarLines('''
SnackBar(
  content: Builder(builder: (c) => Text(f(g(h)))),
  action: SnackBarAction(label: 'a', onPressed: () { done(); }),
)
'''),
        [1],
      );
    });

    test('showSnackBar 는 SnackBar 가 아니다', () {
      expect(snackBarCallLines('messenger.showSnackBar(x);'), isEmpty);
    });
  });
}

// ── 장치 ──

/// `SnackBar(` 가 시작하는 줄 번호들(1부터). 주석과 문자열은 먼저 걷는다.
List<int> snackBarCallLines(String source) =>
    _snackBars(stripCommentsKeepingLines(source)).map((s) => s.line).toList();

/// 그중 **`action:` 은 있는데 `persist:` 가 없는** 것의 줄 번호들.
List<int> offendingSnackBarLines(String source) => _snackBars(stripCommentsKeepingLines(source))
    .where((s) => s.args.contains('action:') && !s.args.contains('persist:'))
    .map((s) => s.line)
    .toList();

class _Call {
  const _Call(this.line, this.args);
  final int line;
  final String args;
}

/// 이름 앞에 글자나 점이 없어야 한다 — `showSnackBar(`·`_FakeSnackBar(` 를 거른다.
final _snackBarCall = RegExp(r'(?<![.\w])SnackBar\s*\(');

Iterable<_Call> _snackBars(String source) sync* {
  for (final m in _snackBarCall.allMatches(source)) {
    final open = source.indexOf('(', m.start);
    final close = _matchingParen(source, open);
    if (close < 0) continue;
    yield _Call(
      '\n'.allMatches(source.substring(0, m.start)).length + 1,
      source.substring(open + 1, close),
    );
  }
}

/// [open] 의 `(` 와 짝이 되는 `)` 의 자리. 못 찾으면 -1.
int _matchingParen(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}


/// `lib/` 아래의 모든 `.dart`.
Iterable<File> _dartFilesUnder(String root) sync* {
  final dir = Directory(root);
  if (!dir.existsSync()) {
    fail('$root 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
  }
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}
