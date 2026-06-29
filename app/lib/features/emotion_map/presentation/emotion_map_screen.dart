import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:go_router/go_router.dart';

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/mood/mood.dart';
import 'package:heat_trip_flutter/core/mood/mood_color.dart';
import 'package:heat_trip_flutter/features/foryou_v2/state/location_service.dart';
import '../data/emotion_map_repository.dart';
import '../domain/emotion_map_place.dart';

/// 감정 지도 단독 화면 (직접 라우트용). 본체는 [EmotionMapView].
class EmotionMapScreen extends StatelessWidget {
  const EmotionMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0.6,
        backgroundColor: Colors.white,
        title:
            const Text('감정 지도', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: const EmotionMapView(),
    );
  }
}

/// 감정 지도 본체 (스캐폴드 없음) — 탐색 화면의 '지도' 탭에서도 재사용. (F2-1)
class EmotionMapView extends StatefulWidget {
  const EmotionMapView({super.key});

  @override
  State<EmotionMapView> createState() => _EmotionMapViewState();
}

class _EmotionMapViewState extends State<EmotionMapView> {
  static const _seoul = NLatLng(37.5666, 126.979);

  final _repo = EmotionMapRepository();
  final _loc = LocationService();

  NaverMapController? _controller;
  NLatLng _center = _seoul;
  bool _locResolved = false;
  bool _loading = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  Future<void> _resolveLocation() async {
    try {
      final (lat, lng) = await _loc.getCurrentLatLng();
      if (lat != null && lng != null) _center = NLatLng(lat, lng);
    } catch (_) {/* 기본 서울 */}
    if (mounted) setState(() => _locResolved = true);
  }

  Future<void> _loadPlaces(NLatLng center) async {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _loading = true;
      _banner = null;
    });
    try {
      final places = await _repo.fetchNearby(
        lat: center.latitude,
        lng: center.longitude,
        radiusKm: 8,
      );
      await c.clearOverlays();
      final markers = <NAddableOverlay>{};
      for (final p in places) {
        if (p.dominantEmotion == null) continue;
        // 클러스터러블 마커 → 겹치면 개수 버블, 줌인하면 색 핀으로 분리
        final marker = NClusterableMarker(
          id: 'p${p.placeId}',
          position: NLatLng(p.lat, p.lng),
          iconTintColor: moodColor(p.dominantEmotion),
        );
        marker.setOnTapListener((_) => _showPlaceSheet(p));
        markers.add(marker);
      }
      if (markers.isNotEmpty) await c.addOverlayAll(markers);
      if (mounted) {
        setState(() {
          _loading = false;
          _banner = places.isEmpty
              ? '이 지역엔 아직 감정 데이터가 없어요. 기록이 쌓이면 색이 채워져요.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _banner = '감정 데이터를 불러오지 못했어요. (서버 연결을 확인해 주세요)';
        });
      }
    }
  }

  Future<void> _refreshHere() async {
    final c = _controller;
    if (c == null) return;
    final pos = await c.getCameraPosition();
    await _loadPlaces(pos.target);
  }

  Future<void> _zoom(double delta) async {
    await _controller?.updateCamera(NCameraUpdate.zoomBy(delta));
  }

  void _showPlaceSheet(EmotionMapPlace p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: moodColor(p.dominantEmotion),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p.exposable
                  ? '이곳에서 사람들은 주로 "${p.dominantEmotion}"을(를) 느꼈어요 · ${p.ugcCount}명 기준'
                  : '예상 감정: "${p.dominantEmotion}" (공공데이터 기반, 기록이 5건 이상 쌓이면 실제 감정으로 바뀌어요)',
              style: const TextStyle(
                  fontSize: 13.5, color: Color(0xFF6B6B73), height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFB6A3E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.pushNamed(
                    'newDiary',
                    extra: {'placeId': p.placeId, 'placeName': p.name},
                  );
                },
                icon: const Icon(Icons.edit_note),
                label: const Text(
                  '다녀왔어요 · 기록하기',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Env.naverMapClientId.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '지도 Client ID가 설정되지 않았어요.\n.env의 NAVER_MAP_CLIENT_ID를 확인해 주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF7B6E67)),
          ),
        ),
      );
    }
    if (!_locResolved) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        NaverMap(
          options: NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(target: _center, zoom: 12),
            locationButtonEnable: true,
            locale: const Locale('ko'),
            minZoom: 6,
            maxZoom: 18,
          ),
          onMapReady: (controller) {
            _controller = controller;
            _loadPlaces(_center);
          },
        ),
        if (_banner != null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _Banner(text: _banner!),
          ),
        const Positioned(left: 12, bottom: 12, child: _Legend()),
        Positioned(
          right: 14,
          bottom: 88,
          child: Material(
            color: Colors.white,
            elevation: 4,
            borderRadius: BorderRadius.circular(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapIconBtn(icon: Icons.add, onTap: () => _zoom(1)),
                const Divider(height: 1, thickness: 1, color: Color(0xFFEDEDF1)),
                _MapIconBtn(icon: Icons.remove, onTap: () => _zoom(-1)),
              ],
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'refreshHere',
            backgroundColor: const Color(0xFFFB6A3E),
            foregroundColor: Colors.white,
            elevation: 4,
            onPressed: _loading ? null : _refreshHere,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            label: const Text(
              '이 지역 다시 검색',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, size: 22, color: const Color(0xFF1A1A1A)),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner({required this.text});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEAD7CE)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B6B73)),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 12, 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E3EA)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '감정 색',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8A8A92),
                ),
              ),
            ),
            for (final m in Moods.all)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: moodColor(m.key),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(m.key, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
