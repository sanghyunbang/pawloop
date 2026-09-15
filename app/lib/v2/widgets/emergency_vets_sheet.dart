// 급할 때 — 가까운 동물병원 셋과 전화 버튼 (#337).
//
// 페르소나 P1 의 실패비용이 "아플 때 근처 병원을 못 찾음" 이다. 밤 11시에 토하는 아이를
// 안고 있는 사람에게 필요한 것은 목록도 지도도 아니고 **전화**다. 그래서 이 시트는
// 이름 · 거리 · 전화 버튼 셋뿐이고, 홈에서 두 번 만에 닿는다.
//
// 좌표는 기기를 떠나지 않는다 — [PetPlacesRepository.fetchNearby] 가 정책(#235)이 꺼져
// 있으면 전국 카탈로그를 받아 두고 거리를 기기에서 잰다. 진료 여부는 전화로 확인한다.
import 'package:flutter/material.dart';

import '../data/external_maps.dart';
import '../data/location_service.dart';
import '../data/pet_places_repository.dart';
import '../domain/vet_hours.dart';
import '../theme/app_tokens.dart';
import 'vet_badge.dart';

/// 위치 하나로 가까운 병원을 받아 오는 함수. 테스트가 갈아 끼운다.
typedef VetLoader = Future<List<PetPlace>> Function(double lat, double lng);

class EmergencyVets {
  const EmergencyVets._();

  /// 시트를 연다. [load]·[locate] 는 테스트가 꽂는 자리다.
  static Future<void> open(
    BuildContext context, {
    VetLoader? load,
    Future<({double lat, double lng})?> Function()? locate,
  }) async {
    final where = await (locate ?? _locate)();
    if (!context.mounted) return;
    var places = const <PetPlace>[];
    var failed = false;
    if (where != null) {
      try {
        places = await (load ?? _load)(where.lat, where.lng);
      } on PlaceFailure {
        // **급할 때 "못 찾았어요" 는 거짓말이다**(#515). 못 받은 것과 없는 것은 다르고,
        // 여기서 그 둘을 뭉치면 사람이 병원이 없다고 믿고 다른 길을 찾는다.
        failed = true;
      }
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) =>
          EmergencyVetsSheet(picks: nearestVets(places), located: where != null, failed: failed),
    );
  }

  static Future<List<PetPlace>> _load(double lat, double lng) =>
      PetPlacesRepository().fetchNearby(lat: lat, lng: lng, contentTypeId: 'vet', numOfRows: 30);

  static Future<({double lat, double lng})?> _locate() async {
    final p = await LocationService.current();
    if (p == null) return null;
    return (lat: p.latitude, lng: p.longitude);
  }
}

/// 시트의 몸통. 위젯 테스트가 이것만 따로 띄울 수 있게 열어 둔다.
class EmergencyVetsSheet extends StatelessWidget {
  const EmergencyVetsSheet({
    super.key,
    required this.picks,
    required this.located,
    this.failed = false,
  });

  final List<PetPlace> picks;

  /// 위치를 알았는가. 모르면 목록 대신 켜 달라고 말한다.
  final bool located;

  /// 목록을 **못 받았는가**. 없는 것과 다르다 — 급할 때 그 둘을 뭉치면 사람이 병원이
  /// 없다고 믿는다(#515).
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: T.surfaceBright,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + MediaQuery.of(context).padding.bottom),
      // 작은 화면에서도 세 곳이 다 보이게 스크롤을 둔다 — 급할 때 잘리면 안 된다.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0x2E281E30),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '가까운 동물병원',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              located ? '거리는 기기 안에서 잽니다. 진료 중인지는 전화로 확인해 주세요.' : '위치를 켜면 가까운 곳부터 찾아 드려요.',
              style: const TextStyle(fontSize: 13, color: T.textSecondary),
            ),
            const SizedBox(height: 16),
            if (picks.isEmpty)
              Text(
                key: const Key('emergency-vets-empty'),
                failed
                    ? '목록을 못 받았어요 · 연결을 확인하고 다시 열어 주세요. 지도 탭의 동물병원 칩에서도 찾을 수 있어요.'
                    : located
                        ? '가까운 병원을 못 찾았어요. 지도 탭의 동물병원 칩에서 찾아보세요.'
                        : '지도 탭의 동물병원 칩에서도 찾을 수 있어요.',
                style: const TextStyle(fontSize: 13, color: T.textMuted),
              )
            else
              for (final p in picks) ...[_row(p, messenger), const SizedBox(height: 10)],
          ],
        ),
      ),
    );
  }

  Widget _row(PetPlace p, ScaffoldMessengerState messenger) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary),
                    ),
                  ),
                  if (isTwentyFourHourByName(p.title)) ...[
                    const SizedBox(width: 6),
                    const VetTwentyFourBadge(),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                p.distLabel.isEmpty ? p.addr : '${p.distLabel} · ${p.addr}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: T.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (p.tel.isNotEmpty)
          GestureDetector(
            onTap: () async {
              if (!await ExternalMaps.call(p.tel)) {
                messenger.showSnackBar(const SnackBar(content: Text('전화 앱을 열 수 없어요')));
              }
            },
            child: Container(
              width: 44,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFD7263D),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.call_rounded, size: 18, color: Colors.white),
            ),
          ),
      ],
    ),
  );
}
