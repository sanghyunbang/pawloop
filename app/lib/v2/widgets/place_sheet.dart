// 장소 상세 시트 — 지도 탭과 "급할 때 · 가까운 동물병원" 이 **같은 것**을 쓴다 (#328 · #664).
//
// ## 왜 위젯으로 꺼냈나
//
// 이 시트는 지도 화면(`explore_screen.dart`)의 State 안에 있었다. 그래서 다른 데서 부를 수
// 없었고, 급할 때 시트의 병원 카드는 **눌러도 아무 일도 안 났다** — 오른쪽 전화 버튼만
// 눌렸다. 같은 모양을 한 벌 더 적을 수도 있었지만, 그러면 둘이 따로 늙는다. 사진 자리를
// 더한 #449 도, 버튼 두 줄을 만든 #619 도 한쪽에만 들어갔을 것이다.
//
// ## 화면에 묶인 동작은 밖에 둔다
//
// "여기서 산책 시작"·"지도에서 보기" 는 지도 화면의 상태(뷰 전환·선 그리기)를 만진다.
// 그래서 여기 있는 것은 **어디서나 뜻이 같은 둘**뿐이다 — 전화, 길찾기. 나머지는 부르는
// 쪽이 [PlaceSheet.actions] 로 끼워 넣는다. 순서까지 부르는 쪽이 정하는 이유는, 지도 탭이
// `산책 시작 · 전화 · 지도에서 보기 · 길찾기` 라는 순서를 이미 갖고 있기 때문이다.
import 'package:flutter/material.dart';

import '../data/external_maps.dart';
import '../data/pet_places_repository.dart';
import '../domain/pet.dart';
import '../domain/vet_hours.dart';
import '../theme/app_tokens.dart';
import 'vet_badge.dart';

/// 시트의 주 동작 하나 — 칸 하나가 된다.
class PlaceSheetAction {
  const PlaceSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  /// 따뜻한 그라데이션으로 칠할 것인가. 한 시트에 여럿이어도 된다.
  final bool primary;
}

/// 어디서나 뜻이 같은 동작 둘. 두 시트가 이것을 쓴다.
class PlaceActions {
  const PlaceActions._();

  /// 전화. 번호가 없으면 부르는 쪽이 아예 안 넣는다.
  static PlaceSheetAction call(
    PetPlace place,
    ScaffoldMessengerState messenger, {
    bool primary = true,
  }) =>
      PlaceSheetAction(
        icon: Icons.call_rounded,
        label: '전화',
        primary: primary,
        onTap: () async {
          if (!await ExternalMaps.call(place.tel)) {
            messenger.showSnackBar(const SnackBar(content: Text('전화 앱을 열 수 없어요')));
          }
        },
      );

  /// 길찾기 — 네이버 지도 앱 → 아무 지도 앱 → 웹 순서로 시도한다([ExternalMaps.directions]).
  ///
  /// 넘기는 좌표는 **카탈로그의 것**이지 사용자 위치가 아니다. 목적지만 건네고 출발지는
  /// 지도 앱이 스스로 잡는다 (A안 #235).
  static PlaceSheetAction directions(
    PetPlace place,
    ScaffoldMessengerState messenger, {
    bool primary = false,
  }) =>
      PlaceSheetAction(
        icon: Icons.directions_walk_rounded,
        label: '길찾기',
        primary: primary,
        onTap: () async {
          if (!await ExternalMaps.directions(
              lat: place.lat, lng: place.lng, name: place.title)) {
            messenger.showSnackBar(const SnackBar(content: Text('지도 앱을 열 수 없어요')));
          }
        },
      );
}

/// 장소 하나의 상세 — 사진, 이름, 분류, 거리, 주소, 전화번호, 출처, 동작.
class PlaceSheet extends StatelessWidget {
  const PlaceSheet({
    super.key,
    required this.place,
    this.actions,
    this.beforeActions,
    this.afterActions,
    this.footer,
  });

  final PetPlace place;

  /// 이 시트의 동작들. 안 주면 **전화(번호가 있으면) · 길찾기** 둘이다.
  ///
  /// 함수인 이유: 동작이 시트를 닫거나([Navigator.pop]) 실패를 알려야 해서
  /// 시트의 context 와 messenger 가 필요하다.
  final List<PlaceSheetAction> Function(
      BuildContext sheetContext, ScaffoldMessengerState messenger)? actions;

  /// 동작 위에 끼우는 것 — 지도 탭의 "선이 없다" 안내(#619).
  final Widget? beforeActions;

  /// 동작 아래에 끼우는 것 — 지도 탭의 경유지 목록. **누를 것을 먼저, 읽을 것을 나중에**(#619).
  final Widget? afterActions;

  /// 맨 아래 두 번째 동작 — 지도 탭의 "이 장소로 글쓰기".
  final Widget? footer;

  /// 이 시트를 모달로 연다.
  static Future<void> show(
    BuildContext context,
    PetPlace place, {
    List<PlaceSheetAction> Function(BuildContext, ScaffoldMessengerState)? actions,
    Widget? beforeActions,
    Widget? afterActions,
    Widget? footer,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => PlaceSheet(
          place: place,
          actions: actions,
          beforeActions: beforeActions,
          afterActions: afterActions,
          footer: footer,
        ),
      );

  @override
  Widget build(BuildContext sheetCtx) {
    final p = place;
    final cat = p.petCategory;
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 18 + MediaQuery.of(sheetCtx).padding.bottom),
      // 사진이 얹히면 작은 화면·큰 글자에서 시트가 화면보다 길 수 있다 — 넘치지 않고 스크롤한다.
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 사진이 맨 위, 시트 폭 (#449) — Apple 지도의 장소 시트처럼 사진이 먼저다.
              if (p.image.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    key: const Key('place-sheet-photo'),
                    aspectRatio: 16 / 9,
                    child: Image.network(p.image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => placePhotoFallback(cat, 'sheet-${p.contentId}')),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: cat.color, borderRadius: BorderRadius.circular(16), boxShadow: [
                    BoxShadow(
                        color: cat.color.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 5))
                  ]),
                  child: Icon(cat.icon, size: 28, color: Colors.white),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
                    const SizedBox(height: 4),
                    Row(children: [
                      placeCategoryTag(cat),
                      // 진료시간 데이터가 없어서 이름으로 짐작한다 — 배지가 그 사실을 함께 말한다(#337).
                      if (p.categoryKey == 'vet' && isTwentyFourHourByName(p.title)) ...[
                        const SizedBox(width: 7),
                        const VetTwentyFourBadge(),
                      ],
                      if (p.distLabel.isNotEmpty) ...[
                        const SizedBox(width: 7),
                        Text(p.distLabel,
                            style: const TextStyle(fontSize: 12, color: T.textMuted)),
                      ],
                    ]),
                  ]),
                ),
                GestureDetector(
                    onTap: () => Navigator.pop(sheetCtx),
                    child: const Icon(Icons.close, size: 22, color: T.textFaint)),
              ]),
              if (p.summary.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(children: [
                  Icon(cat.icon, size: 16, color: cat.color),
                  const SizedBox(width: 7),
                  Expanded(
                      child: Text(p.summary,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary))),
                ]),
              ],
              if (beforeActions != null) beforeActions!,
              if (p.addr.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 16, color: T.textMuted),
                  const SizedBox(width: 7),
                  Expanded(
                      child: Text(p.addr,
                          style: const TextStyle(fontSize: 13, color: T.textSecondary))),
                ]),
              ],
              if (p.tel.isNotEmpty) ...[
                const SizedBox(height: 9),
                Row(children: [
                  const Icon(Icons.call_outlined, size: 16, color: T.textMuted),
                  const SizedBox(width: 7),
                  Text(p.tel, style: const TextStyle(fontSize: 13, color: T.textSecondary)),
                ]),
              ],
              // **영업시간은 없다.** 우리가 가진 데이터에 진료시간이 없어서 위의 24시 배지도
              // 이름으로 짐작한 것이다(#337). 급할 때 틀린 영업시간은 없느니만 못하므로
              // 지어내지 않고, 전화로 확인하라고 말한다(#664).
              const SizedBox(height: 8),
              // 출처 배지 — 어디서 온 데이터인지 말한다 (#291). 가짜 레이어는 #282 로 사라졌다.
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.pets, size: 13, color: T.warmMid),
                const SizedBox(width: 5),
                Text(p.sourceLabel,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700, color: T.warmText)),
              ]),
              const SizedBox(height: 14),
              _Actions(actions: _resolve(sheetCtx)),
              // 누를 것을 먼저, 읽을 것을 나중에 (#619). 경유지가 열한 곳이면 버튼이 밀린다.
              if (afterActions != null) afterActions!,
              if (footer != null) ...[const SizedBox(height: 10), footer!],
            ]),
      ),
    );
  }

  List<PlaceSheetAction> _resolve(BuildContext sheetCtx) {
    final messenger = ScaffoldMessenger.of(sheetCtx);
    if (actions != null) return actions!(sheetCtx, messenger);
    return [
      if (place.tel.isNotEmpty) PlaceActions.call(place, messenger),
      PlaceActions.directions(place, messenger, primary: place.tel.isEmpty),
    ];
  }

}

/// 시트의 주 동작 줄 — 전화 · 지도에서 보기(산책로) · 길찾기. 글쓰기는 그 아래 두 번째다(#328).
///
/// ## 폭은 **글자가 차지할 만큼** 나눈다
///
/// 예전에는 셋이 `Expanded` 로 폭을 똑같이 나눴다. 그러면 `여기서 산책 시작` 은 좌우 여백이
/// 0 이 되어 글자가 모서리에 닿고, `전화` 는 양쪽이 텅 빈다 — 같은 줄인데 한 칸만 꽉 차
/// 보인다(#535). 그래서 **남는 자리만** 똑같이 나눠 준다. 여백이 세 칸 모두 같아진다.
class _Actions extends StatelessWidget {
  const _Actions({required this.actions});

  final List<PlaceSheetAction> actions;

  @override
  Widget build(BuildContext context) {
    final labelStyle = DefaultTextStyle.of(context)
        .style
        .merge(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800));

    final cells = [
      for (final a in actions)
        (
          // 아이콘(16) + 사이(6) + 글자. 여기에 여백을 더한 것이 이 칸의 폭이다.
          width: 22 + _labelWidth(context, a.label, labelStyle),
          child: _cell(a, labelStyle),
        ),
    ];

    const gap = 8.0;
    return LayoutBuilder(builder: (context, box) {
      final natural = cells.fold(0.0, (sum, a) => sum + a.width);
      final oneRow = box.maxWidth - gap * (cells.length - 1);

      // 한 줄에 다 못 서면 **두 줄로 나눈다** (#619 에서 동네 길에 버튼이 넷이 되며 생긴 자리).
      //
      // 예전에는 좁으면 같은 비율로 함께 줄였다. 그러면 393dp 에서 자연폭 합이 줄보다 넓어
      // 여백이 0 이 되고, "여기서 산책 시작" 의 글자가 칸 모서리에 닿는다 — #535 가 고친
      // 바로 그 현상이 넷째 버튼과 함께 돌아온 것이다. 줄을 하나 더 쓰는 쪽이 낫다.
      if (cells.length >= 4 && natural > oneRow) {
        final half = (cells.length / 2).ceil();
        return Column(children: [
          _row(cells.sublist(0, half), box.maxWidth, gap),
          const SizedBox(height: gap),
          _row(cells.sublist(half), box.maxWidth, gap),
        ]);
      }
      return _row(cells, box.maxWidth, gap);
    });
  }

  Widget _cell(PlaceSheetAction a, TextStyle labelStyle) => GestureDetector(
        key: Key('place-action-${a.label}'),
        onTap: a.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: a.primary
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [T.warmStart, T.warmEnd],
                  )
                : null,
            color: a.primary ? null : T.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          // 넷이 설 때가 있다 — 동네 길은 관리기관 전화번호가 있어서 "여기서 산책 시작 ·
          // 전화 · 길찾기" 셋에 하나가 더 붙는 화면이 나온다. 그때는 자연폭의 합이 이미
          // 줄보다 넓어 여백이 없다. 말줄임으로 자르면 무엇을 누르는지 알 수 없어
          // **줄여서 넣는다** — 버튼 이름은 짧고, 안 잘리는 쪽이 낫다.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(a.icon, size: 16, color: a.primary ? Colors.white : T.textSecondary),
              const SizedBox(width: 6),
              Text(a.label,
                  style: labelStyle.copyWith(color: a.primary ? Colors.white : T.textSecondary)),
            ]),
          ),
        ),
      );

  static Widget _row(
      List<({double width, Widget child})> row, double maxWidth, double gap) {
    final room = maxWidth - gap * (row.length - 1);
    final natural = row.fold(0.0, (sum, a) => sum + a.width);
    final slack = room - natural;
    double widthOf(int i) =>
        slack >= 0 ? row[i].width + slack / row.length : row[i].width * room / natural;

    return Row(children: [
      for (var i = 0; i < row.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        SizedBox(width: widthOf(i), child: row[i].child),
      ],
    ]);
  }

  /// 버튼 이름이 [style] 로 그려질 때의 폭. 글자 수로 어림하면 "전화" 와 "산책" 이 같은 폭이
  /// 되는데 실제로는 다르다 — 재서 나눈다.
  static double _labelWidth(BuildContext context, String label, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return tp.width;
  }
}

/// 사진을 못 받았을 때의 자리 — 카테고리색 바탕 + 아이콘.
///
/// 크기를 그대로 두어 사진이 늦게 실패해도 목록이 흔들리지 않는다. 시트와 카드 목록이
/// **같은 것**을 쓴다 — 한쪽만 고치면 같은 장소가 두 화면에서 다르게 보인다.
Widget placePhotoFallback(PetCategory cat, String id) => Container(
      key: Key('place-photo-fallback-$id'),
      color: cat.color.withValues(alpha: 0.14),
      alignment: Alignment.center,
      child: Icon(cat.icon, size: 34, color: cat.color),
    );

/// 분류 딱지. 색만으로 가르지 않는다 — 아이콘을 같이 그린다(#328).
Widget placeCategoryTag(PetCategory cat) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: cat.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(cat.icon, size: 12, color: cat.color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(cat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cat.color)),
        ),
      ]),
    );
