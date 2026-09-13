// lib/v2/widgets/map_unavailable.dart
//
// 지도를 못 그릴 때 그 자리에 놓는 것 — 이슈 #182.
//
// ## 무엇이 문제였나
//
// `NAVER_MAP_CLIENT_ID` 없이 빌드하면 `main.dart` 가 SDK 초기화를 건너뛴다(:52). 그런데
// 화면들은 그것과 무관하게 `NaverMap(` 을 그려서 이런 것이 사용자에게 그대로 보였다.
//
//     'package:flutter_naver_map/src/widget/map_widget.dart': Failed assertion:
//     line 123 pos 9: 'FlutterNaverMap.isInitialized || ...': is not true.
//
// `env.dart:54` 는 이 경우를 이미 알고 있었다 — "비어 있으면 지도 SDK 초기화를 건너뛰고
// 지도 탭이 안내문만 표시한다". **그 안내문이 없었다.** 의도만 적혀 있고 만들어지지
// 않은 자리였다.
//
// ## 릴리스에서는 안 보인다. 그래도 만든다
//
// 배포 빌드에는 키가 들어가므로 사용자는 이걸 볼 일이 거의 없다. 그래서 P3 다.
// 다만 저장소를 새로 받은 사람이 README 를 안 읽고 `flutter run` 하면 **원인을 모를
// 빨간 화면**을 만난다. 실제로 내가 그렇게 만났다.
library;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 지도 자리에 놓는 안내. 실패를 숨기지 않고 **무엇을 해야 하는지** 말한다.
class MapUnavailable extends StatelessWidget {
  /// 이 화면에서 지도가 무슨 일을 하는지. 문구가 화면마다 달라야 사용자가 무엇을
  /// 잃었는지 안다.
  final String what;

  const MapUnavailable({super.key, required this.what});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: T.bgTop,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x22FF8F63),
                ),
                child: const Icon(Icons.map_outlined,
                    size: 34, color: T.warmText),
              ),
              const SizedBox(height: 18),
              const Text('지도를 불러올 수 없어요',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: T.textPrimary)),
              const SizedBox(height: 8),
              Text(what,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.55, color: T.textSecondary)),
              const SizedBox(height: 14),
              // 개발자에게 하는 말이다. 사용자가 볼 일은 거의 없지만, 보게 된다면
              // 이 줄이 유일한 단서다.
              const Text('빌드에 지도 키가 들어가지 않았어요',
                  style: TextStyle(fontSize: 11.5, color: T.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
