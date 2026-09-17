// 홈의 산책 안전 지수 카드 — 하드코딩 날씨 카드가 있던 자리 (#326 → #336).
//
// 없으면 없는 대로 둔다: 키가 없거나, 서버가 못 줬으면 **카드가 없다.**
// "맑음 · 24°C" 를 새벽에도 보여 주던 자리에 다시 가짜를 놓지 않는다.
//
// ## 이 카드는 위치를 안 쓴다 (#682)
//
// 예전에는 `LocationService.locate()` 로 좌표를 잡아 그것으로 기상청 5km 격자 번호를
// 만들었다. 격자만 나가고 위경도는 안 나갔지만, 그 격자는 **단말이 잰 값에서 뽑은 것**이라
// 원스토어 '수집정보' 의 "대략적인 위치 정보(3㎢ 이상 영역)" 에 그대로 들어맞는다. 그렇게
// 선언하면 위치기반서비스 사업 신고필증을 요구받는데, 우리는 위치정보법 제9조제1항 괄호
// ("개인위치정보를 대상으로 하지 아니하는")에 해당해 신고 대상이 아니고 그 서류가 없다.
//
// 지금은 **내가 고른 동네의 중심**에서 격자를 뽑는다. `neighborhood.dart` 머리에 적힌
// 그대로다 — 사용자가 스스로 고른 행정동은 단말이 잰 값이 아니라 사람이 목록에서 고른
// 텍스트이므로 위치정보가 아니다. 그래서 이 카드에는 위치 권한이 필요 없고,
// `location_service.dart` 를 import 하지도 않는다. 그 사실을
// `walk_safety_card_has_no_location_test.dart` 가 소스로 센다.
import 'package:flutter/material.dart';

import '../data/neighborhood_store.dart';
import '../data/walk_advice.dart';
import '../data/walk_safety.dart';
import '../data/walk_safety_repository.dart';
import '../domain/neighborhood.dart';
import '../domain/pet.dart';
import '../screens/neighborhood_picker_screen.dart';
import '../theme/app_tokens.dart';
import 'aurora.dart';

class WalkSafetyCard extends StatefulWidget {
  const WalkSafetyCard({super.key, this.repository, this.neighborhoods, this.now, this.onPick});

  /// 테스트가 꽂는 자리. 운영에서는 `Env` 의 키로 만든 저장소다.
  final WalkSafetyRepository? repository;

  /// 내가 고른 동네를 읽는 자리. 여기서 **중심 좌표**를 얻어 격자를 만든다 —
  /// 예전에 `locate` 가 있던 자리이고, 그 자리에 다시 GPS 를 꽂으면 안 된다(#682).
  final NeighborhoodStore? neighborhoods;

  final DateTime Function()? now;

  /// 동네 고르기 화면을 여는 자리. 테스트가 가짜 화면을 준다 — `NeighborhoodTile.onPick`
  /// 과 같은 모양이다.
  final Future<void> Function(BuildContext context)? onPick;

  @override
  State<WalkSafetyCard> createState() => _WalkSafetyCardState();
}

class _WalkSafetyCardState extends State<WalkSafetyCard> with WidgetsBindingObserver {
  late final NeighborhoodStore _hood = widget.neighborhoods ?? NeighborhoodStore();

  /// 고른 동네. 읽기 전에는 [_loaded] 가 `false` 라 안내 줄도 안 그린다 —
  /// 동네가 있는 사람에게 한 프레임 동안 "동네를 고르세요" 가 번쩍이면 안 된다.
  Neighborhood? _mine;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    kMyDog.addListener(_refresh);
    // 동네를 바꾸면 격자가 달라진다 — 아이가 바뀔 때와 같은 배선이다. 고르기 화면이
    // 저장하면서 이 값을 올리므로(`NeighborhoodStore.save`), 설정에서 바꾸고 와도 잡힌다.
    kNeighborhoodRev.addListener(_refresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    kMyDog.removeListener(_refresh);
    kNeighborhoodRev.removeListener(_refresh);
    super.dispose();
  }

  /// 앱으로 돌아올 때 한 번 더 — 아직 판정이 없으면 서버가 못 줬던 자리다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retry();
  }

  /// 아직 판정이 없을 때만 다시 부른다. 판정이 있으면 30분 TTL 에 맡긴다 —
  /// 홈으로 돌아올 때마다 서버를 부르면 남의 예산만 쓴다.
  void _retry() {
    if (WalkSafetyStore.latest.value == null) _refresh();
  }

  Future<void> _refresh() async {
    final mine = await _hood.read();
    if (!mounted) return;
    setState(() {
      _mine = mine;
      _loaded = true;
    });
    if (mine == null) {
      // 동네가 없으면 **요청을 아예 안 낸다.** 그리고 앞서 받아 둔 판정도 버린다 —
      // 동네를 지운 사람의 홈에 지운 동네의 지수가 남으면 안 된다(#513 과 같은 이유).
      WalkSafetyStore.clear();
      return;
    }
    await WalkSafetyStore.refresh(
      repository: widget.repository ?? WalkSafetyRepository(),
      // 단말이 잰 좌표가 아니라 **목록에서 고른 행정동의 중심**이다(#682).
      center: (lat: mine.lat, lng: mine.lng),
      dog: kMyDog.value,
      now: widget.now,
      // 아이가 바뀌면 같은 관측값으로 다시 판정해야 한다 — 단두종 보정이 다르다.
      // 동네가 바뀌었을 때도 이 자리가 TTL 을 건너뛰게 한다.
      force: WalkSafetyStore.reading != null,
    );
  }

  /// 고른 뒤의 일은 [kNeighborhoodRev] 가 받는다 — 고르기 화면이 저장하면서 그 값을 올리고,
  /// 위의 리스너가 다시 잰다. 여기서 결과를 또 보면 같은 요청이 두 번 나간다.
  void _pick() => (widget.onPick ?? _openPicker)(context);

  static Future<void> _openPicker(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NeighborhoodPickerScreen()));

  /// 동네를 고르면 무엇이 좋아지는지 한 줄. 누르면 고르기 화면으로 간다.
  ///
  /// **"할 수 있는 일이 있으면 말하고, 없으면 비운다"** 가 이 카드의 규칙이다(#517).
  /// 서버가 못 줬을 때 비우는 것과 여기서 말하는 것이 갈리는 이유가 그것이다 —
  /// 동네를 고르는 것은 사용자가 지금 할 수 있는 일이다.
  Widget _pickNeighborhoodRow() => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: GlassCard(
          key: const Key('walk-safety-pick-neighborhood'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            const Icon(Icons.home_work_outlined, size: 20, color: T.warmText),
            const SizedBox(width: 10),
              // 길이는 재서 정했다 (#658 에서 배운 자리다). 진짜 Pretendard 를 물리고, 홈 화면과
              // 같은 좌우 여백(22) 안에서 360dp 로 그려 한 줄에 드는 것을 골랐다. 테스트 폰트로
              // 재거나 여백 없이 재면 실제와 다른 답이 나온다 — 예전에 둘 다 한 번씩 틀렸다.
              //
              // '동네를 고르면' 을 문구에 안 넣는다. 옆의 버튼이 그 말을 하고 있어서,
              // 넣으면 같은 말이 두 번인 데다 360dp 에서 줄이 접힌다.
            const Expanded(
              child: Text('산책하기 좋은지 알려드려요',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
            ),
            TextButton(
              onPressed: _pick,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('동네 고르기',
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
            // 왜 카드가 없는지 말하고 길을 준다. 동네는 있는데 못 받은 것이면 예전처럼 조용히 비운다 —
            // 그때는 사용자가 할 수 있는 일이 없다.
            return _loaded && _mine == null ? _pickNeighborhoodRow() : const SizedBox.shrink();
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
    // 조언은 **오늘 이 값에서** 나온다 (#669). 판정과 같은 재료·같은 시각·같은 아이다 —
    // 예전에는 여기 세 줄이 `const` 라 22°C 가을에도 아스팔트가 뜨겁다고 했다.
    final advice = reading == null
        ? const <WalkAdviceLine>[]
        : WalkAdvice.pick(reading, hour: (widget.now ?? DateTime.now)().hour, dog: kMyDog.value);
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
          // 해당하는 조언이 없으면 이 자리는 **빈다.** 채우려고 아무 말이나 넣지 않는다.
          for (final a in advice) _Line(a.icon, a.text),
          if (advice.isNotEmpty) const SizedBox(height: 6),
          // 출처와 면책을 갈랐다 (#669). 한 문단에 붙어 있으면 "수의사 자문" 이 날씨 얘기처럼
          // 읽힌다 — 앞은 이 숫자가 어디서 왔는지, 뒤는 이 앱의 판정이 의학적 조언이 아니라는
          // 말이다. 면책은 지우지 않는다. 자리만 옮긴다.
          const Text(
            '기상청 초단기실황 · 에어코리아 측정소 값으로 계산했어요.',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: T.textMuted),
          ),
          const SizedBox(height: 10),
          Container(
            key: const Key('walk-safety-disclaimer'),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: T.surface, borderRadius: BorderRadius.circular(14)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 15, color: T.textFaint),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '수의사 자문을 거치지 않은 참고 기준이에요. 아이 상태를 먼저 봐 주세요.',
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: T.textMuted),
                ),
              ),
            ]),
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
