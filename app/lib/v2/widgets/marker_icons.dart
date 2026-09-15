// lib/v2/widgets/marker_icons.dart
//
// 지도 핀 그림을 **카테고리마다 한 번만** 굽는다 — 이슈 #533.
//
// ## 무엇이 있었나
//
// `explore_screen` 의 `_refreshMarkers` 가 장소마다 핀 그림을 새로 구웠다. 서울숲 주변
// 80곳에서 재 보니 **31.7초 중 31.5초(99%)** 가 그 시간이었다(한 개 약 393ms). 지도
// 타일은 6초에 왔는데 핀은 20초가 넘어서야 한꺼번에 나타났다.
//
// 그림은 **카테고리마다 다를 뿐**이다 — 색과 아이콘만 다르고 종류는 아홉(+기타)뿐이다.
// 80곳이면 같은 그림을 여러 번 굽는다. 바로 옆 `_prepareClusterIcon` 은 이미 한 번만
// 굽는다. 클러스터 핀에는 있던 규칙이 카테고리 핀에는 없었다.
//
// ## 왜 화면 밖에 있나
//
// 규칙이 화면 안에 있으면 **셀 수가 없다.** `NOverlayImage.fromWidget` 은 플러터 플러그인
// 이라 순수 테스트에서 못 부른다. 그래서 "굽는 일" 은 화면에 두고, **"몇 번 굽는가" 만**
// 여기로 뺐다. 그러면 `T` 를 문자열로 두고 세는 테스트가 그대로 돈다.
import 'dart:async';

import '../domain/pet.dart';

/// 카테고리 핀 그림을 기억한다. [T] 는 그림 타입이고 이 자리는 그것이 무엇인지 모른다 —
/// 화면은 `NOverlayImage`, 테스트는 문자열을 쓴다.
///
/// ```dart
/// late final _icons = MarkerIcons<NOverlayImage>(_drawIcon);
/// ...
/// final icon = await _icons.of(place.petCategory);
/// ```
class MarkerIcons<T> {
  MarkerIcons(this._draw);

  /// 실제로 굽는 일. 카테고리 하나에 그림 하나다.
  final Future<T> Function(PetCategory) _draw;

  /// **끝난 그림이 아니라 굽고 있는 것**을 담는다. 그래야 같은 카테고리를 동시에 물어도
  /// 한 번만 굽는다 — 담는 것이 결과라면 첫 번째가 끝나기 전에 온 두 번째가 또 굽는다.
  final Map<String, Future<T>> _baking = {};

  /// 카테고리의 키로 센다. [PetCategory] 는 `==` 를 안 만들어서 동일성 비교가 되는데,
  /// 그 전제(전부 `const` 인스턴스)가 깨지면 캐시가 조용히 빗나간다.
  Future<T> of(PetCategory cat) {
    final pending = _baking[cat.key];
    if (pending != null) return pending;

    final started = _draw(cat);
    _baking[cat.key] = started;
    // 못 구운 것은 안 남긴다 — 남기면 그 카테고리는 다음 기회에도 영영 핀이 없다.
    // 여기서 한 번 받아 두지 않으면 "처리 안 된 오류" 가 된다. `then<void>` 를 못 박는 이유는
    // 안 그러면 onError 의 반환형이 성공 쪽과 안 맞아 그 자리에서 형 오류가 나기 때문이다.
    unawaited(started.then<void>((_) {}, onError: (Object _) {
      _baking.remove(cat.key);
    }));
    return started;
  }

  /// 지금까지 구운(굽고 있는) 카테고리 수. 테스트가 읽는다.
  int get baked => _baking.length;
}
