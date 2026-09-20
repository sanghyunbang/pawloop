// 코스가 **멀 때** 보여 주는 한 장 — 이슈 #623 → #724.
//
// ## 왜 있는가
//
// 예전에는 안 물었다. 홈의 "오늘의 코스" 가 `등나무근린공원 · 450m 거리` 를 보여 주고
// "여기서 산책 시작" 을 누르면, **지금 서 있는 자리에서** 추적이 시작됐다. 코스 이름은
// 기록에 붙는 꼬리표였을 뿐이다(`WalkPlaceRef`, #338). 목표 1.0km 에 가는 450m 가 먹히고,
// 거기 안 갔어도 기록에는 그 이름이 남았다.
//
// #623 은 "어디서 시작할까요?" 를 물었다 — **길 안내** 아니면 **지금 여기서**. 그런데 거리는
// 보여 주기만 하고 분기에 안 썼다. 추천 코스가 부산이고 내가 서울이어도 "지금 여기서" 를
// 고르면 서울에서 걷는 산책에 부산 장소가 붙었다. 2026-09-20 사장님 결정:
// **"여기서" 는 없앤다.** 멀면 "N km 떨어져 있어요 — 도착하면 홈에서 시작해 주세요" 다.
//
// ## 지금의 규칙 — 거리로 가른다
//
// 가르는 자리는 `startWalk` 한 곳이고, 기준은 `WalkDestination.nearM`(300m) 이다.
//
//   - 기준 안 → 이 장은 **안 뜬다.** 바로 추적을 시작하고 장소를 기록에 붙인다
//   - 기준 밖 · 거리를 모름 → 이 장이 뜬다. 시작은 **없다.** 지도 앱으로 길 안내만
//
// ## 길 안내는 API 가 아니다
//
// `ExternalMaps.directions` 는 `nmap://route/walk` 로 **지도 앱을 여는 것**이다. 키도,
// 신청도, 호출 한도도 없다. 우리가 보내는 것은 목적지 좌표뿐이고 출발지(현위치)는 그 앱이
// 스스로 잡는다 — 우리 서버로 나가는 것이 없다(A안 #235). 산책 경로를 **우리가** 추천하는
// 일은 #725 다 — 이 장은 그 자리가 아니다.
import 'package:flutter/material.dart';

import '../domain/walk_destination.dart';
import '../theme/app_tokens.dart';

/// 시트의 답. 닫았으면 `null` 이다 — 그때는 **아무것도 시작하지 않는다.**
///
/// 값이 하나뿐인 이유: "지금 여기서" 는 #724 에서 지웠다. 멀리 있는 코스를 지금 자리에서
/// 시작하는 길이 **타입에 없어야** 다음 사람이 되살리지 않는다.
enum WalkStartChoice {
  /// 지도 앱으로 길 안내. 도착해서 홈에서 시작하면 된다.
  directions,
}

/// 멀리 있는 코스에 대해 "N km 떨어져 있어요" 를 말하고 길 안내만 내민다.
///
/// 닫으면 `null` 이고 **산책은 시작되지 않는다.** 실수로 눌렀을 때 30분짜리 기록이
/// 시작되는 것보다, 아무 일도 안 나는 쪽이 낫다.
class WalkStartPointSheet {
  WalkStartPointSheet._();

  /// 테스트가 갈아 끼우는 자리. 평소에는 [show] 다.
  static Future<WalkStartChoice?> Function(
      BuildContext context, String title, WalkDestination destination) ask = show;

  static void resetForTest() => ask = show;

  static Future<WalkStartChoice?> show(
      BuildContext context, String title, WalkDestination destination) {
    final far = destination.label;
    // 거리를 모르면 숫자를 지어내지 않는다 — "0m" 이나 "알 수 없음" 은 거리 대신 불안을 준다.
    final headline = far == null ? '거리를 알 수 없어요' : '$far 떨어져 있어요';
    final body = far == null
        ? '위치를 켜면 $title까지의 거리를 재요. 도착하면 홈에서 산책을 시작해 주세요'
        : '$title에 도착하면 홈에서 산책을 시작해 주세요';
    return showModalBottomSheet<WalkStartChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: T.surfaceBright,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 42,
            height: 5,
            decoration:
                BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(height: 18),
          Text(headline,
              key: const Key('walk-start-point-title'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 8),
          Text(body,
              key: const Key('walk-start-point-distance'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: T.textSecondary)),
          const SizedBox(height: 18),
          _button(
            key: const Key('walk-start-directions'),
            label: '지도 앱으로 길 안내',
            icon: Icons.turn_right_rounded,
            primary: true,
            onTap: () => Navigator.of(sheetCtx).pop(WalkStartChoice.directions),
          ),
          const SizedBox(height: 8),
          _button(
            key: const Key('walk-start-close'),
            label: '닫기',
            icon: Icons.close_rounded,
            primary: false,
            onTap: () => Navigator.of(sheetCtx).pop(),
          ),
          const SizedBox(height: 12),
          const Text('산책 기록은 도착한 뒤 홈에서 시작해야 남아요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: T.textMuted)),
        ]),
      ),
    );
  }

  static Widget _button({
    required Key key,
    required String label,
    required IconData icon,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: primary ? 15 : 13),
        decoration: BoxDecoration(
          gradient: primary
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [T.warmStart, T.warmEnd],
                )
              : null,
          color: primary ? null : T.surface,
          borderRadius: BorderRadius.circular(15),
          border: primary ? null : Border.all(color: T.line),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: primary ? 18 : 16, color: primary ? Colors.white : T.textSecondary),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: primary ? 15 : 14,
                  fontWeight: FontWeight.w800,
                  color: primary ? Colors.white : T.textSecondary)),
        ]),
      ),
    );
  }
}
