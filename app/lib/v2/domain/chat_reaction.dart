/// 말풍선 아래 반응의 어휘 — #452. 계약의 `ChatReactionKind` 와 **글자까지 같다**.
///
/// ## 왜 다섯인가
///
/// 좋아요 · 최고예요 · 웃겨요 · 슬퍼요 · **확인했어요**. 마지막 하나가 이 앱에 있는 이유가 있다 —
/// 가족 방의 "밥 줬어?" 에 필요한 답은 감정이 아니라 **확인**이고, 그걸 말로 하면 방이 "응" 으로
/// 채워진다. 커뮤니티의 셋(도움돼요 · 귀여워요 · 공감)을 그대로 쓰지 않은 것도 같은 이유다 —
/// 그건 글에 매기는 평가라 "밥 먹었어?" 에는 뜻이 없다.
///
/// ## 순서는 서버가 정한다
///
/// 응답의 배열 순서가 그리는 순서다. 여기 [values] 의 순서는 **고르는 줄**(길게 누르면 뜨는 다섯)의
/// 순서일 뿐이고, 말풍선 아래 줄은 서버가 준 차례대로 그린다 — 앱이 다시 정렬하면 같은 말이
/// 기기마다 다르게 보인다.
///
/// ## 모르는 종류는 안 그린다
///
/// 서버가 우리가 모르는 종류를 늘려도 앱은 [tryOf] 가 null 을 주는 것을 그냥 건너뛴다. 숫자는
/// 서버에 그대로 있고, 새 앱이 받는 날 보인다 — 모르는 글자를 그리면 말풍선 아래에 남이 만든
/// 아무 글자나 뜨는 자리가 된다.
enum ChatReactionKind {
  like('like', '👍', '좋아요'),
  heart('heart', '❤️', '최고예요'),
  laugh('laugh', '😂', '웃겨요'),
  sad('sad', '😢', '슬퍼요'),
  check('check', '✅', '확인했어요');

  const ChatReactionKind(this.wire, this.emoji, this.label);

  /// 서버와 주고받는 값. 경로에도 이 글자가 들어간다.
  final String wire;

  /// 칩에 그리는 그림 하나.
  final String emoji;

  /// 고르는 줄의 접근성 이름. 칩에는 숫자만 붙는다 — 다섯 개가 글자까지 붙으면 한 줄에 안 들어간다.
  final String label;

  /// 계약의 값 → 종류. 모르는 값이면 null(클래스 javadoc).
  static ChatReactionKind? tryOf(String wire) {
    for (final kind in values) {
      if (kind.wire == wire) {
        return kind;
      }
    }
    return null;
  }
}
