// 홈의 산책 안전 지수 카드 — 하드코딩 날씨 카드가 있던 자리 (#326 → #336).
//
// 없으면 없는 대로 둔다: 키가 없거나, 게스트라 위치 동의가 없거나, 못 받았으면 **카드가 없다.**
// "맑음 · 24°C" 를 새벽에도 보여 주던 자리에 다시 가짜를 놓지 않는다.
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../data/location_service.dart';
import '../data/walk_safety.dart';
import '../data/walk_safety_repository.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';
import 'aurora.dart';

class WalkSafetyCard extends StatefulWidget {
  const WalkSafetyCard({super.key, this.repository, this.locate, this.now, this.onAskLocation});

  /// 테스트가 꽂는 자리. 운영에서는 `Env` 의 키로 만든 저장소와 [LocationService] 다.
  final WalkSafetyRepository? repository;

  /// 위치를 잡는 손 — 좌표가 아니라 **[LocationFix]** 다. 이 카드는 "왜 없는지" 까지
  /// 말해야 하기 때문이다(#517): 권한이 없어서면 안내 줄을 그리고, 동의 전이거나 실내라
  /// 못 잡은 것이면 조용히 비운다.
  final Future<LocationFix> Function()? locate;
  final DateTime Function()? now;

  /// "허용" 을 눌렀을 때 — 설명 시트를 띄우고 **그 다음에** OS 에 묻는다. 쓸 수 있게 됐으면 `true`.
  ///
  /// 위젯이 화면(`location_priming_sheet`)을 import 하지 않으므로 홈이 꽂는다 —
  /// `TodayCourseCard.onStart` 와 같은 이유다. 안 꽂으면 안내 줄도 안 그린다(#517).
  final Future<bool> Function(BuildContext context)? onAskLocation;

  @override
  State<WalkSafetyCard> createState() => _WalkSafetyCardState();
}

class _WalkSafetyCardState extends State<WalkSafetyCard> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    kMyDog.addListener(_refresh);
    // 첫 시도는 실패하기 쉽다 — 동의 값이 아직 안 읽혔거나(라우터가 비동기로 쓴다) 실내라
    // 좌표가 안 잡힌 때다. 그때 한 번 실패하고 마는 카드는 앱을 껐다 켤 때까지 없다.
    LocationService.consented.addListener(_retry);
    // 다른 자리(산책 시작 · 지도)에서 권한을 허용하고 돌아왔을 수 있다.
    LocationService.permissionRev.addListener(_retry);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    kMyDog.removeListener(_refresh);
    LocationService.consented.removeListener(_retry);
    LocationService.permissionRev.removeListener(_retry);
    super.dispose();
  }

  /// 앱으로 돌아올 때 한 번 더 — 위치를 못 잡았던 자리에서 나갔다 온 것일 수 있다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retry();
  }

  /// 아직 판정이 없을 때만 다시 부른다. 판정이 있으면 30분 TTL 에 맡긴다 —
  /// 홈으로 돌아올 때마다 위치를 잡으면 배터리만 쓴다.
  void _retry() {
    if (WalkSafetyStore.latest.value == null) _refresh();
  }

  Future<void> _refresh() => WalkSafetyStore.refresh(
        repository: widget.repository ?? WalkSafetyRepository(),
        locate: _position,
        dog: kMyDog.value,
        now: widget.now,
        // 아이가 바뀌면 같은 관측값으로 다시 판정해야 한다 — 단두종 보정이 다르다.
        force: WalkSafetyStore.reading != null,
      );

  /// 위치를 못 쓴 이유. **권한 문제일 때만** 안내 줄을 그린다 — 동의 전(동의 화면이 받는다)
  /// 이나 사용자가 스스로 켠 중단(프로필의 토글)에 안내를 띄우면 그건 잔소리다.
  LocationDenial? _denial;

  bool get _needsPermission =>
      _denial == LocationDenial.denied || _denial == LocationDenial.deniedForever;

  /// 권한이 없으면 **묻지 않는다.** 화면이 뜨자마자 왜 묻는지 모르는 대화상자를 만나면
  /// 사람은 일단 거부하고, 안드로이드는 두 번째 거부에서 영구 거부로 굳는다 — 그 뒤로는
  /// 앱이 다시 물을 수도 없다(#517). 대신 [_permissionRow] 가 설명을 먼저 보여 준다.
  Future<({double lat, double lng})?> _position() async {
    final fix = await (widget.locate ?? _locate)();
    final p = fix.position;
    if (p == null) {
      // 카드가 없는 이유를 말없이 삼키지 않는다 — 동의 전인지, 실내라 못 잡은 것인지.
      if (kDebugMode) debugPrint('[WalkSafety] 위치 없음: ${fix.denial}');
      if (mounted) setState(() => _denial = fix.denial);
      return null;
    }
    if (mounted) setState(() => _denial = null);
    return (lat: p.latitude, lng: p.longitude);
  }

  static Future<LocationFix> _locate() => LocationService.locate(prompt: false);

  Future<void> _ask() async {
    final ask = widget.onAskLocation;
    if (ask == null) return;
    final ok = await ask(context);
    if (!mounted || !ok) return;
    setState(() => _denial = null);
    await _refresh();
  }

  /// 위치를 켜면 무엇이 좋아지는지 한 줄. 누르면 설명 시트가 먼저 뜬다.
  Widget _permissionRow() => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: GlassCard(
          key: const Key('walk-safety-ask-location'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            const Icon(Icons.near_me_outlined, size: 20, color: T.warmText),
            const SizedBox(width: 10),
              // 짧게 고쳤다 (#658). 예전 문구는 360dp 폰에서 마지막 '요' 한 글자만 다음 줄로
              // 떨어져 카드가 어색했다.
              //
              // 길이는 재서 정했다. 진짜 Pretendard 를 물리고, 홈 화면과 같은 좌우 여백(22)
              // 안에서 360dp 로 그려 한 줄에 드는 것을 골랐다. 테스트 폰트로 재거나 여백 없이
              // 재면 실제와 다른 답이 나온다 — 둘 다 한 번씩 틀렸다.
              //
              // '위치를 켜면' 을 뺀 자리는 옆의 '허용' 버튼이 메운다. 무엇을 허용하는지는
              // 그 버튼을 누르면 뜨는 설명 시트가 말한다.
            const Expanded(
              child: Text('지금 산책하기 좋은지 알려드려요',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
            ),
            TextButton(
              onPressed: _ask,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('허용',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: T.warmText)),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<WalkSafetyVerdict?>(
        valueListenable: WalkSafetyStore.latest,
        builder: (context, verdict, _) {
          if (verdict == null) {
            // 왜 카드가 없는지 말하고 길을 준다. 권한 문제가 아니면 예전처럼 조용히 비운다.
            return _needsPermission && widget.onAskLocation != null
                ? _permissionRow()
                : const SizedBox.shrink();
          }
          final look = _lookOf(verdict.level);
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GestureDetector(
              onTap: () => _showDetail(context, verdict),
              behavior: HitTestBehavior.opaque,
              child: GlassCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: look.color.withValues(alpha: 0.16)),
                    child: Icon(look.icon, size: 22, color: look.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(verdict.headline,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
                      const SizedBox(height: 3),
                      Text(verdict.reasons.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: T.textMuted)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: T.textFaint),
                ]),
              ),
            ),
          );
        },
      );

  static ({IconData icon, Color color}) _lookOf(WalkSafetyLevel level) => switch (level) {
        WalkSafetyLevel.good => (icon: Icons.wb_sunny_rounded, color: const Color(0xFF3DBE6C)),
        WalkSafetyLevel.short => (icon: Icons.timer_outlined, color: const Color(0xFFF5A623)),
        WalkSafetyLevel.avoid => (icon: Icons.local_fire_department_rounded, color: const Color(0xFFFF6B6B)),
        WalkSafetyLevel.cold => (icon: Icons.ac_unit_rounded, color: const Color(0xFF3B82F6)),
      };

  void _showDetail(BuildContext context, WalkSafetyVerdict verdict) {
    final reading = WalkSafetyStore.reading;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: T.surfaceBright,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 18),
          Text(verdict.headline,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 6),
          Text(verdict.reasons.join(' · '), style: const TextStyle(fontSize: 13, color: T.textSecondary)),
          if (reading?.humidity != null) ...[
            const SizedBox(height: 2),
            Text('습도 ${reading!.humidity}%', style: const TextStyle(fontSize: 13, color: T.textSecondary)),
          ],
          const SizedBox(height: 16),
          const _Line(Icons.back_hand_outlined, '손등을 바닥에 7초 못 대면 발바닥도 못 견뎌요. 아스팔트는 기온보다 최대 33°C 뜨거워요'),
          const _Line(Icons.schedule_rounded, '더운 날은 오전 10시 전 · 오후 7시 뒤가 안전해요'),
          const _Line(Icons.pets_rounded, '단두종·노령견·대형견은 더위에 더 약해요 — 한 단계 보수적으로 봐요'),
          const SizedBox(height: 10),
          const Text(
            '기상청 초단기실황 · 에어코리아 측정소 값으로 계산한 참고 기준이에요. 수의사 자문 전이니 아이 상태를 먼저 봐 주세요.',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: T.textMuted),
          ),
        ]),
      ),
    );
  }
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
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textSecondary))),
        ]),
      );
}
