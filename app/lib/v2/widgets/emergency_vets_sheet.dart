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
import 'place_sheet.dart';
import 'vet_badge.dart';

/// 위치 하나로 가까운 병원을 받아 오는 함수. 테스트가 갈아 끼운다.
typedef VetLoader = Future<List<PetPlace>> Function(double lat, double lng);

class EmergencyVets {
  const EmergencyVets._();

  /// 지금 떠 있는 시트의 라우트. 자물쇠를 <b>이것으로</b> 본다 — 아래 [_alreadyOpen] 참조.
  static Route<dynamic>? _route;

  /// 라우트를 손에 넣기 **전**에 걸리는 자물쇠. 같은 틱의 두 번째 탭을 막는다.
  static bool _locked = false;

  /// 이미 떠 있는가.
  ///
  /// <b>불리언 하나로 들지 않는 이유</b>: 시트가 우리 모르게 사라질 수 있다(화면이 통째로
  /// 버려지는 경우). 그러면 [showModalBottomSheet] 의 future 가 안 끝나고 `finally` 도 안 돌아서
  /// 자물쇠가 잠긴 채 남는다 — 그 뒤로 이 시트는 <b>영영 안 열린다.</b> 실제로 위젯 테스트에서
  /// 그 일이 났다: 첫 테스트가 시트를 열어 둔 채 끝나자 나머지 테스트가 전부 빈 화면을 봤다.
  ///
  /// 그래서 라우트가 <b>살아 있는지</b>를 함께 본다. 시트가 없으면 자물쇠도 없다.
  static bool get _alreadyOpen {
    if (!_locked) return false;
    final route = _route;
    // 라우트를 아직 못 잡았다(같은 틱의 두 번째 탭) — 그때는 불리언이 유일한 근거다.
    if (route == null) return true;
    if (route.isActive) return true;
    _locked = false;
    _route = null;
    return false;
  }

  /// 시트를 연다. **기다리지 않고 바로 연다.**
  ///
  /// 예전에는 위치를 잡고 목록을 받은 **뒤에** 열었다(#663). 그 사이 몇 초 동안 화면에
  /// 아무 변화가 없어서 사람이 다시 누르고, 누른 만큼 시트가 겹쳤다 — 쓸어내려 닫으려면
  /// 누른 횟수만큼 닫아야 했다.
  ///
  /// 그래서 두 겹으로 고친다.
  ///
  ///  1. **시트를 먼저 연다.** 찾는 일은 시트 안에서 한다([EmergencyVetsSheet.searching]).
  ///     급할 때 필요한 것은 "지금 찾고 있다" 는 신호다.
  ///  2. **떠 있는 동안 두 번째 탭은 아무 일도 안 한다.** 1번만으로는 아주 빠른 연타에
  ///     두 장이 뜰 수 있다 — 첫 탭의 시트가 첫 프레임에 그려지기 전에 두 번째 탭이 들어오면
  ///     그렇다.
  ///
  /// [load]·[locate] 는 테스트가 꽂는 자리다.
  static Future<void> open(
    BuildContext context, {
    VetLoader? load,
    Future<({double lat, double lng})?> Function()? locate,
  }) async {
    if (_alreadyOpen) return;
    _locked = true;
    _route = null;
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          // 라우트는 여기서만 손에 넣을 수 있다. 푸시는 이미 끝났고 이 빌더는 그 다음
          // 빌드에서 돈다 — 그래서 같은 틱의 연타는 위의 불리언이 받는다.
          _route = ModalRoute.of(sheetCtx);
          return EmergencyVetsFinder(load: load ?? _load, locate: locate ?? _locate);
        },
      );
    } finally {
      _locked = false;
      _route = null;
    }
  }

  static Future<List<PetPlace>> _load(double lat, double lng) =>
      PetPlacesRepository().fetchNearby(lat: lat, lng: lng, contentTypeId: 'vet', numOfRows: 30);

  static Future<({double lat, double lng})?> _locate() async {
    final p = await LocationService.current();
    if (p == null) return null;
    return (lat: p.latitude, lng: p.longitude);
  }
}

/// 시트 안에서 위치와 목록을 찾는다 — 찾는 동안에도 시트는 이미 떠 있다 (#663).
///
/// 몸통([EmergencyVetsSheet])과 나눠 둔 이유: 몸통은 **받은 값을 그리기만** 해서 위젯
/// 테스트가 상태마다 따로 띄울 수 있다. 찾는 일을 몸통에 섞으면 그 테스트마다 가짜 저장소가
/// 필요해진다.
class EmergencyVetsFinder extends StatefulWidget {
  const EmergencyVetsFinder({super.key, required this.load, required this.locate});

  final VetLoader load;
  final Future<({double lat, double lng})?> Function() locate;

  @override
  State<EmergencyVetsFinder> createState() => _EmergencyVetsFinderState();
}

class _EmergencyVetsFinderState extends State<EmergencyVetsFinder> {
  bool _searching = true;
  List<PetPlace> _picks = const [];
  bool _located = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    final where = await widget.locate();
    var places = const <PetPlace>[];
    var failed = false;
    if (where != null) {
      try {
        places = await widget.load(where.lat, where.lng);
      } on PlaceFailure {
        // **급할 때 "못 찾았어요" 는 거짓말이다**(#515). 못 받은 것과 없는 것은 다르고,
        // 여기서 그 둘을 뭉치면 사람이 병원이 없다고 믿고 다른 길을 찾는다.
        failed = true;
      }
    }
    // 찾는 동안 사람이 시트를 내렸을 수 있다.
    if (!mounted) return;
    setState(() {
      _searching = false;
      _picks = nearestVets(places);
      _located = where != null;
      _failed = failed;
    });
  }

  @override
  Widget build(BuildContext context) => EmergencyVetsSheet(
        picks: _picks,
        located: _located,
        failed: _failed,
        searching: _searching,
      );
}

/// 시트의 몸통. 위젯 테스트가 이것만 따로 띄울 수 있게 열어 둔다.
class EmergencyVetsSheet extends StatelessWidget {
  const EmergencyVetsSheet({
    super.key,
    required this.picks,
    required this.located,
    this.failed = false,
    this.searching = false,
  });

  final List<PetPlace> picks;

  /// 위치를 알았는가. 모르면 목록 대신 켜 달라고 말한다.
  final bool located;

  /// 목록을 **못 받았는가**. 없는 것과 다르다 — 급할 때 그 둘을 뭉치면 사람이 병원이
  /// 없다고 믿는다(#515).
  final bool failed;

  /// <b>아직 찾는 중인가</b> (#663). 이 상태에서는 [picks]·[located]·[failed] 가 아직
  /// 아무 뜻이 없다 — 빈 목록을 "없어요" 로 말하면 안 된다. 그 셋을 보기 전에 이것을 먼저 본다.
  final bool searching;

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
              searching
                  ? '가까운 곳부터 찾고 있어요.'
                  : located
                      ? '거리는 기기 안에서 잽니다. 진료 중인지는 전화로 확인해 주세요.'
                      : '위치를 켜면 가까운 곳부터 찾아 드려요.',
              style: const TextStyle(fontSize: 13, color: T.textSecondary),
            ),
            const SizedBox(height: 16),
            // 찾는 중이 **맨 앞**이다. 아래 세 갈래는 찾기가 끝난 뒤의 이야기라, 이것을
            // 뒤에 두면 아직 안 찾아본 상태가 "못 찾았어요" 로 나간다.
            if (searching)
              const _Searching()
            else if (picks.isEmpty)
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
              for (final p in picks) ...[_row(context, p, messenger), const SizedBox(height: 10)],
          ],
        ),
      ),
    );
  }

  /// 병원 한 곳.
  ///
  /// <b>카드 전체가 눌린다</b>(#664) — 누르면 지도 탭과 <b>같은</b> 상세 시트가 열린다
  /// ({@link PlaceSheet}). 예전에는 오른쪽 전화 버튼만 눌렸고, 이름을 눌러도 아무 일도
  /// 안 났다. 주소를 확인하거나 길을 찾을 방법이 여기서는 없었다.
  ///
  /// <b>전화 버튼은 상세를 거치지 않는다.</b> 이 시트의 요점이 "홈에서 두 번 만에 전화"(#337)
  /// 라서, 그 사이에 한 단계를 끼우면 기능이 달라진다.
  Widget _row(BuildContext context, PetPlace p, ScaffoldMessengerState messenger) => GestureDetector(
    key: Key('emergency-vet-${p.contentId}'),
    onTap: () => PlaceSheet.show(context, p),
    behavior: HitTestBehavior.opaque,
    child: Container(
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
  ),
  );
}

/// 찾는 동안 보여 주는 한 줄 (#663).
///
/// 병원 카드 자리를 **비워 두지 않는 것**이 요점이다. 비워 두면 시트가 떠 있어도 "아무 일도
/// 안 일어난다" 로 보이고, 그게 이 이슈의 증상이었다.
class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('emergency-vets-searching'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFFD7263D)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '위치를 확인하고 가까운 병원을 찾는 중이에요',
                style: TextStyle(fontSize: 13, color: T.textSecondary),
              ),
            ),
          ],
        ),
      );
}
