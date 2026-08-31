/// 다음 폴링까지 얼마나 기다릴 것인가. **순수 함수다.** (이슈 #81)
///
/// ## 왜 순수 함수인가
///
/// 타이머를 붙인 채로는 테스트가 시간에 매달린다 — 3초를 검증하려면 3초를 기다리거나
/// 가짜 시계를 주입해야 하고, 둘 다 이 정책이 맞는지와 상관없는 배관이다. 상태를 받아
/// 간격을 돌려주는 함수로 떼어 두면 `flutter_test` 가 즉시 판정한다.
///
/// 실제 타이머는 화면이 갖는다. 이 파일은 **얼마나 기다릴지만** 답한다.
///
/// ## 왜 간격을 조절하는가
///
/// 폴링 비용은 "DB 를 읽는 것" 이 아니라 **"아무것도 없는데 왕복하는 것"** 이다. 캐시는
/// 왕복을 못 없앤다. 클라이언트가 간격을 늘리면 비용 0으로 왕복 자체가 줄어든다.
///
/// 서버에 `chat.poll{result=empty|hit}` 메트릭이 있고(#80), **empty 비율이 0.95 를 넘으면
/// 한도를 낮출 것이 아니라 여기 숫자를 키우라**고 운영 문서가 적어 뒀다.
///
/// ## 규칙
///
/// | 상태 | 간격 |
/// |---|---|
/// | 포그라운드 복귀 직후 | **0** — 즉시 한 번 |
/// | 백그라운드 | 30초 |
/// | 방을 보는 중, 방금 새 메시지를 받음 | 3초 |
/// | 방을 보는 중, 빈 응답이 이어짐 | 3 → 6 → 12 → 24 → 30초에서 멈춤 |
///
/// 빈 응답이 이어질 때 늘리는 것은 **사람이 대화를 쉬고 있다**는 뜻이기 때문이다. 새 메시지가
/// 하나라도 오면 곧바로 3초로 돌아간다 — 대화가 다시 시작된 순간 반응이 느리면 안 된다.
library;

/// 폴링 간격 정책. 상태를 넣으면 다음 간격이 나온다.
class ChatPollingPolicy {
  const ChatPollingPolicy._();

  /// 방을 보고 있고 대화가 살아 있을 때. 사람이 답장을 기다리는 체감의 상한이다.
  static const Duration activeInterval = Duration(seconds: 3);

  /// 앱이 뒤로 갔을 때. 배지 숫자만 맞으면 되므로 실시간일 이유가 없다.
  static const Duration backgroundInterval = Duration(seconds: 30);

  /// 빈 응답이 이어져도 여기까지만 늘어난다. 더 늘리면 대화 재개를 놓친다.
  static const Duration maxInterval = Duration(seconds: 30);

  /// 빈 응답 한 번마다 간격을 이만큼 곱한다.
  static const int backoffFactor = 2;

  /// 다음 폴링까지의 간격.
  ///
  /// [justResumed] 가 참이면 나머지를 보지 않고 [Duration.zero] 다 — 사용자가 앱으로
  /// 돌아온 순간 화면이 낡아 있으면 그게 가장 눈에 띈다.
  ///
  /// [consecutiveEmptyPolls] 는 **연속으로** 빈손이었던 횟수다. 새 메시지를 하나라도 받으면
  /// 부르는 쪽이 0으로 되돌린다.
  static Duration nextInterval({
    required bool inForeground,
    required int consecutiveEmptyPolls,
    bool justResumed = false,
  }) {
    if (justResumed) {
      return Duration.zero;
    }
    if (!inForeground) {
      return backgroundInterval;
    }

    // 음수가 들어와도 기본 간격으로 떨어진다. 부르는 쪽의 실수가 폴링을 멈추면 안 된다.
    final empties = consecutiveEmptyPolls < 0 ? 0 : consecutiveEmptyPolls;

    var millis = activeInterval.inMilliseconds;
    for (var i = 0; i < empties; i++) {
      millis *= backoffFactor;
      if (millis >= maxInterval.inMilliseconds) {
        return maxInterval;
      }
    }
    return Duration(milliseconds: millis);
  }
}
