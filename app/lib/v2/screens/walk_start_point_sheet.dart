// 코스를 고르고 "산책 시작" 을 눌렀을 때 **어디서 시작할지** 묻는 한 장 — 이슈 #623.
//
// ## 왜 묻는가
//
// 예전에는 안 물었다. 홈의 "오늘의 코스" 가 `등나무근린공원 · 450m 거리` 를 보여 주고
// "여기서 산책 시작" 을 누르면, **지금 서 있는 자리에서** 추적이 시작됐다. 코스 이름은
// 기록에 붙는 꼬리표였을 뿐이다(`WalkPlaceRef`, #338).
//
// 그래서 이런 일이 벌어졌다.
//
//   - 목표가 1.0km 인데 **가는 450m 가 거기 먹힌다.** 왕복이면 공원에 닿기도 전에 목표가 찬다
//   - 기록에는 "등나무근린공원" 이 남는다 — 거기 안 갔어도
//
// **450m 라는 숫자를 카드가 직접 보여 주면서 그 거리를 없는 것처럼 다룬 것**이 문제였다.
// 2026-09-17 에 사장님이 "네이버 길찾기든 그런 걸로 가는 길을 보여줘야 하고 거기에서
// 시작버튼을 누르게 해야 하는데 구조가 잘못 짜여진 거 아니니" 라고 했다.
//
// ## 왜 거리로 안 가르나
//
// "150m 안이면 안 묻기" 같은 규칙을 먼저 넣고 싶어진다. 하지만 그 경계값에 근거가 없다 —
// 사람마다, 골목마다 다르다. **묻는 쪽을 먼저 만들고**, 나중에 "가까우면 안 묻기" 를 얹는
// 것이 순서다. 얹을 자리는 `startWalk` 한 곳뿐이다.
//
// ## 길 안내는 API 가 아니다
//
// `ExternalMaps.directions` 는 `nmap://route/walk` 로 **지도 앱을 여는 것**이다. 키도,
// 신청도, 호출 한도도 없다. 우리가 보내는 것은 목적지 좌표뿐이고 출발지(현위치)는 그 앱이
// 스스로 잡는다 — 우리 서버로 나가는 것이 없다(A안 #235).
import 'package:flutter/material.dart';

import '../domain/walk_destination.dart';
import '../theme/app_tokens.dart';

/// 시트의 답. 닫았으면 `null` 이다 — 그때는 **아무것도 시작하지 않는다.**
enum WalkStartChoice {
  /// 지도 앱으로 길 안내. 도착해서 다시 시작하면 된다.
  directions,

  /// 지금 서 있는 자리에서 시작. 예전의 유일한 동작이다.
  here,
}

/// 어디서 시작할지 한 장으로 묻는다.
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
          const Text('어디서 시작할까요?',
              key: Key('walk-start-point-title'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 8),
          // 거리를 모르면 안 적는다 — "0m" 이나 "알 수 없음" 은 거리 대신 불안을 준다.
          Text(far == null ? title : '$title까지 $far 예요',
              key: const Key('walk-start-point-distance'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: T.textSecondary)),
          const SizedBox(height: 18),
          _button(
            key: const Key('walk-start-directions'),
            label: '길 안내 받기',
            icon: Icons.turn_right_rounded,
            primary: true,
            onTap: () => Navigator.of(sheetCtx).pop(WalkStartChoice.directions),
          ),
          const SizedBox(height: 8),
          _button(
            key: const Key('walk-start-here'),
            label: '지금 여기서 시작',
            icon: Icons.directions_walk_rounded,
            primary: false,
            onTap: () => Navigator.of(sheetCtx).pop(WalkStartChoice.here),
          ),
          const SizedBox(height: 12),
          const Text('길 안내를 고르면 지도 앱이 열려요. 도착해서 다시 시작하면 돼요',
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
