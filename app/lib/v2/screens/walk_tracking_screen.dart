import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_tokens.dart';
import '../data/location_service.dart';
import 'create_screen.dart';

/// 실시간 산책 트래킹 (더미 시뮬레이션).
/// 실제 배포에선 geolocator 위치 스트림 → walk.path(LINESTRING)로 저장.
class WalkTrackingScreen extends StatefulWidget {
  const WalkTrackingScreen({super.key});
  @override
  State<WalkTrackingScreen> createState() => _WalkTrackingScreenState();
}

class _WalkTrackingScreenState extends State<WalkTrackingScreen> {
  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1), end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  NaverMapController? _ctrl;
  Timer? _timer;
  StreamSubscription<Position>? _posSub;
  bool _paused = false;
  bool _real = false; // true = 실제 GPS, false = 시뮬(위치 불가 시 폴백)
  int _seconds = 0;
  double _km = 0;

  // 더미 경로(서울숲 근처 루프) — 위치 불가 시 시뮬레이션으로 한 점씩 그린다.
  late final List<NLatLng> _route = _makeRoute();
  final List<NLatLng> _path = [];
  int _idx = 0;

  static List<NLatLng> _makeRoute() {
    const lat0 = 37.5445, lng0 = 127.0374;
    final pts = <NLatLng>[];
    for (int i = 0; i < 40; i++) {
      final t = i / 40 * 2 * math.pi;
      final r = 0.0016 + 0.0006 * math.sin(t * 3);
      pts.add(NLatLng(lat0 + r * math.sin(t), lng0 + r * math.cos(t) * 1.25));
    }
    return pts;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    // 경과 시간 초시계(실제/시뮬 공통).
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || !mounted) return;
      setState(() => _seconds++);
      if (!_real) _advanceSim();
    });
    // 실제 위치 시도 → 되면 GPS 스트림, 안 되면 시뮬.
    final pos = await LocationService.current();
    if (!mounted) return;
    if (pos != null) {
      _real = true;
      _path.add(NLatLng(pos.latitude, pos.longitude));
      await _ctrl?.updateCamera(NCameraUpdate.withParams(target: _path.last, zoom: 16));
      await _drawPath();
      _posSub = LocationService.stream().listen((p) {
        if (_paused || !mounted) return;
        final cur = NLatLng(p.latitude, p.longitude);
        setState(() {
          if (_path.isNotEmpty) _km += _dist(_path.last, cur);
          _path.add(cur);
        });
        _drawPath();
        _ctrl?.updateCamera(NCameraUpdate.withParams(target: cur));
      });
    } else {
      _path.add(_route[0]); // 시뮬 시작점
    }
  }

  // 시뮬 모드: 더미 경로를 한 점씩 진행.
  void _advanceSim() {
    if (_idx >= _route.length - 1) return;
    setState(() {
      _idx++;
      _km += _dist(_route[_idx - 1], _route[_idx]);
      _path.add(_route[_idx]);
    });
    _drawPath();
    _ctrl?.updateCamera(NCameraUpdate.withParams(target: _path.last));
  }

  double _dist(NLatLng a, NLatLng b) {
    const R = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return R * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _rad(double d) => d * math.pi / 180;

  Future<void> _drawPath() async {
    final c = _ctrl;
    if (c == null || _path.length < 2) return;
    await c.addOverlay(NPolylineOverlay(
      id: 'walk-path',
      coords: _path,
      color: const Color(0xFFFF7E8A),
      width: 7,
    ));
    await c.addOverlay(NMarker(id: 'walk-head', position: _path.last, iconTintColor: const Color(0xFFFF7E8A)));
  }

  String get _timeLabel {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _pace {
    if (_km < 0.01 || _seconds == 0) return "-'--\"";
    final secPerKm = _seconds / _km;
    final m = (secPerKm ~/ 60), s = (secPerKm % 60).round();
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  void _finish() {
    _timer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('산책 완료! 🐾', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _sumCell(_timeLabel, '시간'),
            _sumCell('${_km.toStringAsFixed(2)}km', '거리'),
            _sumCell(_pace, '페이스'),
          ]),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Navigator.pop(sheetCtx); // sheet
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CreateScreen(prefillPlace: '오늘 산책')));
            },
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: _warm, borderRadius: BorderRadius.circular(15)),
              child: const Text('기록 저장하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () { Navigator.pop(sheetCtx); Navigator.pop(context); }, child: const Text('저장 안 함', style: TextStyle(color: T.textMuted))),
        ]),
      ),
    );
  }

  Widget _sumCell(String v, String label) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0x9E463C64))),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(target: _route[0], zoom: 16),
              locale: const Locale('ko'),
              scaleBarEnable: false,
            ),
            onMapReady: (c) {
              _ctrl = c;
              _start();
            },
          ),
        ),
        // 상단 뒤로
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.topLeft,
              child: GestureDetector(
                onTap: () { _timer?.cancel(); Navigator.pop(context); },
                child: Container(
                  width: 42, height: 42, alignment: Alignment.center,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white,
                      boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 3))]),
                  child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
                ),
              ),
            ),
          ),
        ),
        // 하단 라이브 패널
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: EdgeInsets.fromLTRB(14, 0, 14, MediaQuery.of(context).padding.bottom + 16),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [BoxShadow(color: Color(0x2E5A4690), blurRadius: 26, offset: Offset(0, 10))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _paused ? const Color(0xFFBBB3CC) : const Color(0xFFFF7E8A))),
                const SizedBox(width: 6),
                Text(_paused ? '일시정지됨' : '산책 기록 중',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _paused ? T.textMuted : const Color(0xFFE07A4E))),
                const Spacer(),
                const Text('실시간 GPS', style: TextStyle(fontSize: 11, color: T.textMuted)),
              ]),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat('${_km.toStringAsFixed(2)}', 'km'),
                _stat(_timeLabel, '시간'),
                _stat(_pace, '페이스'),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _paused = !_paused),
                    child: Container(
                      height: 52, alignment: Alignment.center,
                      decoration: BoxDecoration(color: const Color(0xFFF1ECF7), borderRadius: BorderRadius.circular(15)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 22, color: T.textSecondary),
                        const SizedBox(width: 6),
                        Text(_paused ? '재개' : '일시정지', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: T.textSecondary)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: GestureDetector(
                    onTap: _finish,
                    child: Container(
                      height: 52, alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: _warm, borderRadius: BorderRadius.circular(15)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.stop_rounded, size: 22, color: Colors.white),
                        SizedBox(width: 6),
                        Text('종료', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String v, String label) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0x9E463C64))),
      ]);
}
