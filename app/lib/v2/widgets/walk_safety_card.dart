// 홈의 산책 안전 지수 카드 — 하드코딩 날씨 카드가 있던 자리 (#326 → #336).
//
// 없으면 없는 대로 둔다: 키가 없거나, 게스트라 위치 동의가 없거나, 못 받았으면 **카드가 없다.**
// "맑음 · 24°C" 를 새벽에도 보여 주던 자리에 다시 가짜를 놓지 않는다.
import 'package:flutter/material.dart';

import '../data/location_service.dart';
import '../data/walk_safety.dart';
import '../data/walk_safety_repository.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';
import 'aurora.dart';

class WalkSafetyCard extends StatefulWidget {
  const WalkSafetyCard({super.key, this.repository, this.locate, this.now});

  /// 테스트가 꽂는 자리. 운영에서는 `Env` 의 키로 만든 저장소와 [LocationService] 다.
  final WalkSafetyRepository? repository;
  final Future<({double lat, double lng})?> Function()? locate;
  final DateTime Function()? now;

  @override
  State<WalkSafetyCard> createState() => _WalkSafetyCardState();
}

class _WalkSafetyCardState extends State<WalkSafetyCard> {
  @override
  void initState() {
    super.initState();
    _refresh();
    kMyDog.addListener(_refresh);
  }

  @override
  void dispose() {
    kMyDog.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() => WalkSafetyStore.refresh(
        repository: widget.repository ?? WalkSafetyRepository(),
        locate: widget.locate ?? _locate,
        dog: kMyDog.value,
        now: widget.now,
        // 아이가 바뀌면 같은 관측값으로 다시 판정해야 한다 — 단두종 보정이 다르다.
        force: WalkSafetyStore.reading != null,
      );

  static Future<({double lat, double lng})?> _locate() async {
    final p = await LocationService.current();
    if (p == null) return null;
    return (lat: p.latitude, lng: p.longitude);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<WalkSafetyVerdict?>(
        valueListenable: WalkSafetyStore.latest,
        builder: (context, verdict, _) {
          if (verdict == null) return const SizedBox.shrink();
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
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBB3CC)),
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
          color: Color(0xFAFCFAFF),
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
          Icon(icon, size: 18, color: const Color(0xFFE07A4E)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textSecondary))),
        ]),
      );
}
