// lib/core/net/net_timeouts.dart
//
// 요청 하나가 포기하기까지의 상한 — 이슈 #573.
//
// ## 왜 한 곳인가
//
// 전에는 저장소마다 자기 상수를 들고 있었다. 5 · 8 · **12** · 15 · 30 이 흩어져 있었고,
// 12 가 일곱 개였다 — 처음 하나를 정한 뒤로 **복사돼 온 값**이다. 기준이 한 곳에 없으면
// 다음 사람도 12 를 복사한다.
//
// ## 왜 10초 안쪽인가
//
// Nielsen 의 응답 시간 세 한계에서 **10초가 "사용자의 주의를 붙들어 둘 수 있는 한계"** 다.
// 그보다 오래 걸리면 사람은 다른 일을 하러 간다.
//
// > 10 seconds is about the limit for keeping the user's attention focused on the dialogue.
// > — Jakob Nielsen, *Response Time Limits* (NN/g)
// > https://www.nngroup.com/articles/response-times-3-important-limits/
//
// 12초는 그 밖이다. **한 번 실패하는 것만으로** 이미 사용자가 화면을 떠난 뒤다. 그래서
// [standard] 를 그 한계 안쪽에 둔다 — 실패도 주의가 남아 있는 동안 도착해야 "다시 시도" 가
// 눌릴 수 있다.
//
// 9초를 고른 이유: 10 은 한계 **그 자체**라 딱 맞추면 경계에 걸린다. 그렇다고 더 줄이면
// 느린 모바일 회선에서 정상 응답을 실패로 만든다 — 우리 요청은 작은 JSON 이고 실측은
// 수백 ms 지만, 상한은 p99 를 덮어야지 평균을 덮는 값이 아니다.
//
// ## 예외는 이유를 적는다
//
// [long] 은 **몸통이 큰 것**에만 쓴다. 사진 한 장을 9초에 올리라고 하면 정상적인 업로드가
// 실패한다 — 그건 느린 것이지 죽은 것이 아니다.
library;

/// 망 요청의 상한. 저장소가 각자 숫자를 들지 않고 여기를 가리킨다(#573).
class NetTimeouts {
  const NetTimeouts._();

  /// 보통 요청. 작은 JSON 한 왕복이다.
  ///
  /// Nielsen 의 10초 주의 한계 **안쪽**이다 — 머리말 참조.
  static const Duration standard = Duration(seconds: 9);

  /// 몸통이 큰 요청 — 사진 · 영상 업로드, 카탈로그 통째 내려받기.
  ///
  /// [standard] 를 쓰면 **정상 업로드가 실패한다.** 오래 걸리는 것이 당연한 요청이라
  /// 사람도 그렇게 기대한다(진행 표시가 따로 있다).
  static const Duration long = Duration(seconds: 30);
}
