// lib/v2/domain/walk_labels.dart
//
// 산책 하나를 사람 말로 적는 두 마디 — 걸린 시간과 페이스 — 이슈 #537.
//
// ## 왜 한 자리에 모았나
//
// 같은 산책이 화면마다 다른 말을 했다. 트래킹 화면과 끝내기 시트는 `00:44 · 1'02"` 였는데,
// 기록 목록과 상세는 **`0분 · -`** 였다. 기록 쪽이 `durationS ~/ 60` 으로 분만 보고 있어서,
// **1분이 안 되는 산책이 통째로 사라졌다.**
//
// 거리는 `0.7km` 인데 시간이 `0분` 이면 사용자는 기록이 잘못됐다고 읽는다. 짧은 산책은
// 실제로 있다 — 비 오는 날 배변만, 아픈 아이와 5분, 아파트 한 바퀴.
//
// ## 여기에 없는 것
//
// 주간 합계는 이 자리가 아니다. 서버가 **초로 더한 뒤** 분으로 내린다(`WalkService`, #341 —
// "산책 다섯 번이 5분이 아니라 0분이 된다"). 그쪽은 이미 맞다.
library;

/// 걸린 시간 한 마디 — **1분이 안 되면 초로** 적는다.
///
/// `44` → `44초` · `720` → `12분` · `0` → `0초`.
///
/// 분 아래를 버리지 않는 이유는 위의 것 그대로다. 1분이 넘으면 초는 안 적는다 — 기록 카드는
/// 훑는 자리라 `12분 34초` 는 읽는 데 드는 값이 더 크다.
String walkTimeLabel(int durationS) {
  if (durationS < 60) {
    return '${durationS < 0 ? 0 : durationS}초';
  }
  return '${durationS ~/ 60}분';
}

/// 1km 에 걸린 시간 — `1'02"`. 잴 수 없으면 `null`.
///
/// **분이 아니라 초로 나눈다.** 예전에는 `minutes / km` 라, 분이 0 이면 나눌 수가 없어
/// `-` 를 적었다 — 0.70km 를 44초에 걸은 산책의 페이스는 `1'02"` 다.
///
/// 거리가 10m 아래면 `null` 이다. 그 밑에서는 GPS 오차가 페이스를 몇 배로 부풀린다 —
/// 트래킹 화면이 같은 자리에서 같은 문턱을 쓴다.
String? walkPaceLabel({required int durationS, required double km}) {
  if (km < 0.01 || durationS <= 0) {
    return null;
  }
  final secondsPerKm = durationS / km;
  final minutes = secondsPerKm ~/ 60;
  final seconds = (secondsPerKm % 60).round();
  // 59.6초가 60초로 반올림되면 `3'60"` 이 된다.
  if (seconds == 60) {
    return "${minutes + 1}'00\"";
  }
  return "$minutes'${seconds.toString().padLeft(2, '0')}\"";
}
