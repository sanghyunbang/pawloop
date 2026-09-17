// 홈의 안전 지수 카드가 **위치를 안 잡는다** — 이슈 #682.
//
// ## 왜 소스를 세는가
//
// "이 카드는 위치를 안 쓴다" 는 **없음의** 주장이다. 가짜를 꽂아 호출 0 을 단언하는 방법도
// 있지만, 그건 꽂을 자리가 있다는 뜻이라 자리가 남아 있는 한 다음 사람이 거기에 다시
// GPS 를 꽂을 수 있다. 그래서 자리를 없애고 **없어진 것을 센다** —
// `location_upload_policy_test` 와 `legacy_shell_reachability_test` 가 같은 이유로 같은
// 방식을 쓴다.
//
// ## 무엇이 걸린 일인가
//
// 이 카드가 서버로 보내는 것은 기상청 5km 격자 번호 둘뿐이고, 그건 예전에도 그랬다. 바뀐
// 것은 **그 격자를 무엇으로 만드는가**다. 단말이 잰 좌표에서 만들면 위경도가 안 실려도
// 나가는 값의 출처가 기기의 관측이라, 원스토어 '수집정보' 의 "대략적인 위치 정보(3㎢ 이상
// 영역)" 에 그대로 들어맞는다. 그렇게 선언하면 위치기반서비스 사업 신고필증을 요구받는데,
// 우리는 위치정보법 제9조제1항 괄호("개인위치정보를 대상으로 하지 아니하는")에 해당해
// 신고 대상이 아니고 그 서류가 없다.
//
// 지금은 사용자가 목록에서 고른 행정동의 중심에서 만든다 — `neighborhood.dart` 가 적어 둔
// 그대로, 스스로 고른 행정동은 단말이 잰 값이 아니라 사람이 고른 텍스트다.
//
// ## 여기서 재지 않는 것
//
// 이 카드가 여는 **고르기 화면**에는 "현재 위치로 찾기" 단추가 있고 그쪽은 위치를 쓴다
// (`neighborhood_picker_screen.dart`). 그래서 이 검사는 "앱이 위치를 안 쓴다" 가 아니라
// **"이 카드가 안 쓴다"** 만 말한다. 둘의 차이가 이 일의 전부다 — 고르기 화면의 좌표는
// 사용자가 그 단추를 눌렀을 때만, 기기 안에서 목록과 견주는 데만 쓰이고(`RegionCatalog.nearest`)
// 밖으로 안 나간다. 홈에 들어오는 것만으로 위치를 잡던 쪽이 이 카드였다.
//
// ## 주석은 세지 않는다
//
// 이 파일이 막으려는 이름들이 카드의 **주석에는 남아 있다**(무엇이 왜 없어졌는지 적혀
// 있으므로). 주석을 안 걷으면 이 검사는 지우자마자 빨간불이고, 그러면 다음 사람이 내력을
// 지우게 된다. 걷는 일은 `support/dart_source.dart` 가 한다.
//
// **그 손은 문자열 속도 함께 비운다**(`'…'` 안이 빈 채로 돌아온다). import 경로가 전부
// 문자열이라, 그것만 쓰면 "geolocator 를 import 하는가" 가 **영원히 초록**인 헛검사가
// 된다 — 실제로 한 번 그렇게 썼다가 걸렸다. 그래서 import 는 원문에서 따로 읽는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

const _card = 'lib/v2/widgets/walk_safety_card.dart';

/// `import '…'` 의 경로만. 주석 줄은 `//` 로 시작하므로 이 눈에 안 걸린다.
List<String> _imports(String source) => RegExp(r"""^\s*import\s+['"]([^'"]+)['"]""", multiLine: true)
    .allMatches(source)
    .map((m) => m.group(1)!)
    .toList();

/// 카드가 위치를 잡으려면 반드시 지나야 하는 이름들. 하나라도 코드에 있으면 "안 쓴다" 가
/// 거짓이다.
const _forbidden = <String, String>{
  'LocationService': '위치를 잡는 손이다 — 이 카드가 부르면 홈에 들어오는 것만으로 위치를 쓴다',
  'Geolocator': '플러그인을 직접 부르는 우회로',
  'LocationFix': '위치를 잡은 결과 — 이 카드가 다룰 값이 아니다',
  'LocationDenial': '위치 권한이 없는 이유 — 이 카드는 권한을 안 쓰므로 이유도 없다',
};

/// import 로 들어오면 안 되는 경로 조각.
const _forbiddenImports = <String>['location_service', 'geolocator', 'location_priming'];

void main() {
  test('카드 소스에 위치를 잡는 이름이 하나도 없다', () {
    final file = File(_card);
    expect(file.existsSync(), isTrue,
        reason: '파일을 옮겼다면 이 검사도 함께 옮긴다. skip 하지 않는다');

    final source = file.readAsStringSync();
    final code = stripCommentsKeepingLines(source);
    final found = <String>[];
    _forbidden.forEach((name, why) {
      if (code.contains(name)) found.add('$name — $why');
    });
    for (final path in _imports(source)) {
      for (final bad in _forbiddenImports) {
        if (path.contains(bad)) found.add("import '$path'");
      }
    }

    expect(found, isEmpty,
        reason: '홈 카드가 위치를 다시 잡기 시작했다. 격자는 고른 동네의 중심에서 뽑는다 '
            '(#682) — 단말이 잰 값에서 뽑으면 원스토어 수집정보를 「위치 수집」 으로 '
            '선언해야 하고, 그러면 우리에게 없는 신고필증을 요구받는다');
  });

  test('대신 고른 동네에서 중심 좌표를 얻는다 — 자리가 빈 채로 통과하지 않는다', () {
    // 위 검사만 있으면 좌표를 아예 안 쓰는 빈 카드도 초록이다. 무엇이 그 자리를 채웠는지
    // 함께 못 박아 둔다.
    final source = File(_card).readAsStringSync();
    final code = stripCommentsKeepingLines(source);

    expect(_imports(source), contains('../data/neighborhood_store.dart'));
    expect(code, contains('NeighborhoodStore'));
    expect(code, contains('center: (lat: mine.lat, lng: mine.lng)'),
        reason: '격자의 재료는 고른 동네의 중심이다');
    // 동네가 바뀌면 다시 재야 한다 — 아이가 바뀔 때와 같은 배선을 쓴다.
    expect(code, contains('kNeighborhoodRev.addListener'));
  });

  test('홈 화면도 이 카드에 위치를 쥐여 주지 않는다', () {
    // 카드에서 손을 뗐어도 홈이 다시 꽂으면 같은 일이 벌어진다. 꽂을 자리가 사라졌으므로
    // 컴파일이 막아 주지만, **왜** 안 꽂는지는 여기 한 줄로 남는다.
    final home = stripCommentsKeepingLines(
        File('lib/v2/screens/today_screen.dart').readAsStringSync());

    expect(home, contains('WalkSafetyCard()'));
    expect(home.contains('askLocationPermission'), isFalse,
        reason: '위치 권한을 설명하는 손은 산책 시작 쪽 자리다 — 홈 카드에는 안 꽂는다');
  });
}
