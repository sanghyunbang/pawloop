// 첫 산책 시작 앞의 위치 사전 안내 한 장 (#325).
//
// OS 권한 대화상자는 "왜 · 언제 · 어디서 끄나" 를 말해 주지 않는다. 동의 화면의 한 줄이
// 전부인데 그건 몇 화면 전이다. 앱이 먼저 한 장으로 말하고, "허용하기" 를 눌렀을 때만 OS
// 대화상자를 부른다(NN/g 맥락 도움말 · 권한 프라이밍). 한 번 거부한 뒤에는 "설정에서 켜기"
// 길을 함께 보여 준다 — OS 가 다시 묻지 못하게 한 상태(deniedForever)면 그 길뿐이다.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_tokens.dart';

/// 시트가 말하는 상태.
enum LocationPrimingState {
  /// 아직 물어본 적 없다 — 왜 필요한지 말하고 허용하기.
  first,

  /// 전에 한 번 거부했다. 앱이 다시 물을 수는 있다 — 허용하기 + 설정에서 켜기.
  deniedBefore,

  /// OS 가 다시 묻지 못하게 했다 — 설정에서 켜기만.
  deniedForever,
}

/// 시트의 답.
enum LocationPrimingAnswer { allow, openSettings, later }

/// OS 권한 상태를 읽고, "물어본 적 있음" 을 기억한다. 테스트가 갈아 끼우는 자리가 둘이다.
class LocationPriming {
  LocationPriming._();

  static const String askedKey = 'location_priming_asked_v1';

  static Future<LocationPermission> Function() checkPermission = Geolocator.checkPermission;
  static Future<bool> Function() openSettings = Geolocator.openAppSettings;

  static void resetForTest() {
    checkPermission = Geolocator.checkPermission;
    openSettings = Geolocator.openAppSettings;
  }

  /// 권한이 이미 있으면 `null`(시트 없이 바로 간다), 아니면 보여 줄 시트의 상태.
  ///
  /// Android 의 `checkPermission()` 은 `denied` 와 `deniedForever` 를 구분하지 못한다 — 그것은
  /// `requestPermission()` 의 답에서만 온다. 그래서 한 번 거부한 뒤에는 [LocationPrimingState.deniedBefore]
  /// 로 "허용하기" 와 "설정에서 켜기" 를 함께 보여 준다: OS 가 다시 물을 수 있으면 대화상자가 뜨고,
  /// 아니면 추적 화면이 "앱 설정 열기" 로 받는다(에뮬레이터에서 실측). iOS 는 `deniedForever` 를
  /// 바로 주므로 설정 길만 보인다.
  static Future<LocationPrimingState?> stateFor() async {
    final perm = await checkPermission();
    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return null;
      case LocationPermission.deniedForever:
        return LocationPrimingState.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        final prefs = await SharedPreferences.getInstance();
        return (prefs.getBool(askedKey) ?? false)
            ? LocationPrimingState.deniedBefore
            : LocationPrimingState.first;
    }
  }

  /// "허용하기" 를 눌러 OS 대화상자를 부른 적이 있다 — 다음에 또 거부 상태면 설정 길을 보여 준다.
  static Future<void> markAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(askedKey, true);
  }
}

class LocationPrimingSheet extends StatelessWidget {
  const LocationPrimingSheet({super.key, required this.state});

  final LocationPrimingState state;

  static Future<LocationPrimingAnswer> show(BuildContext context, LocationPrimingState state) async {
    final answer = await showModalBottomSheet<LocationPrimingAnswer>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => LocationPrimingSheet(state: state),
    );
    return answer ?? LocationPrimingAnswer.later;
  }

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  @override
  Widget build(BuildContext context) {
    final forever = state == LocationPrimingState.deniedForever;
    final deniedBefore = state == LocationPrimingState.deniedBefore;

    return Container(
      decoration: const BoxDecoration(
        color: T.surfaceBright,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + MediaQuery.of(context).padding.bottom),
      // 작은 화면·가로 모드에서도 넘치지 않게 — 시트의 기본 최대 높이는 화면의 9/16 이다.
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          forever ? '위치 권한이 꺼져 있어요' : '산책 경로를 그리려면 위치가 필요해요',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        const SizedBox(height: 14),
        // 사실만 쓴다 — 지도도 현위치로 맞추므로 "산책하는 동안만" 이라고는 안 한다. 경로가 기기에만
        // 남는 것은 A안(#235, LocationUploadPolicy) 이 보장한다.
        const _Line(Icons.route_rounded, '산책 경로를 그리고, 지도를 내 주변으로 맞추는 데 써요'),
        const _Line(Icons.phone_android_rounded, '경로는 이 기기에만 남고 서버로 올라가지 않아요'),
        const _Line(Icons.toggle_off_rounded, '프로필에서 언제든 끌 수 있어요'),
        const _Line(Icons.notifications_none_rounded, '기록하는 동안 알림 한 줄이 떠요 — 화면을 꺼도 이어져요'),
        if (forever) ...[
          const SizedBox(height: 4),
          const Text(
            '앱에서는 다시 여쭤볼 수 없어요. 설정 > 앱 > 권한에서 위치를 켜 주세요.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: T.textSecondary),
          ),
        ],
        const SizedBox(height: 18),
        if (forever)
          _primary(context, '설정에서 켜기', LocationPrimingAnswer.openSettings)
        else
          _primary(context, '허용하기', LocationPrimingAnswer.allow),
        if (deniedBefore) ...[
          const SizedBox(height: 8),
          _secondary(context, '설정에서 켜기', LocationPrimingAnswer.openSettings),
        ],
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(LocationPrimingAnswer.later),
            child: const Text('나중에', style: TextStyle(fontSize: 13.5, color: T.textMuted)),
          ),
        ),
        ]),
      ),
    );
  }

  Widget _primary(BuildContext context, String label, LocationPrimingAnswer answer) => GestureDetector(
        onTap: () => Navigator.of(context).pop(answer),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(gradient: _warm, borderRadius: BorderRadius.circular(15)),
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      );

  Widget _secondary(BuildContext context, String label, LocationPrimingAnswer answer) => GestureDetector(
        onTap: () => Navigator.of(context).pop(answer),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: T.line),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textSecondary)),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: T.warmText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textSecondary)),
          ),
        ]),
      );
}
