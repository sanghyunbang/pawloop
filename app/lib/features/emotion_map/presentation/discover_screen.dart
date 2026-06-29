import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:heat_trip_flutter/core/mood/mood.dart';
import 'package:heat_trip_flutter/core/mood/mood_color.dart';
import 'package:heat_trip_flutter/features/foryou_v2/state/location_service.dart';
import '../data/emotion_map_repository.dart';
import '../domain/emotion_map_place.dart';
import 'emotion_map_screen.dart';

/// 탐색 — 감정 칩 + 키워드로 장소 검색 (목록/지도 토글). (탐색/검색 복원)
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const _accent = Color(0xFFFB6A3E);

  final _repo = EmotionMapRepository();
  final _loc = LocationService();
  final _kw = TextEditingController();

  Mood? _mood;
  int _view = 0; // 0=목록, 1=지도
  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<EmotionMapPlace> _results = const [];
  double? _lat, _lng;

  @override
  void initState() {
    super.initState();
    _resolveLoc();
  }

  Future<void> _resolveLoc() async {
    try {
      final (la, ln) = await _loc.getCurrentLatLng();
      _lat = la;
      _lng = ln;
    } catch (_) {/* 위치 없으면 거리 미표시 */}
  }

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    if (_mood == null && _kw.text.trim().isEmpty) {
      setState(() {
        _searched = true;
        _error = '감정을 고르거나 키워드를 입력해 주세요.';
        _results = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
      _view = 0;
    });
    try {
      final r = await _repo.search(
        mood: _mood?.key,
        q: _kw.text,
        lat: _lat,
        lng: _lng,
      );
      if (mounted) {
        setState(() {
          _results = r;
          _loading = false;
          _error = r.isEmpty ? '결과가 없어요. 다른 감정/키워드로 찾아보세요.' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '검색에 실패했어요. (서버 연결을 확인해 주세요)';
        });
      }
    }
  }

  void _record(EmotionMapPlace p) {
    context.pushNamed('newDiary', extra: {'placeId': p.placeId, 'placeName': p.name});
  }

  void _openDetail(EmotionMapPlace p) {
    context.pushNamed(
      'explore_detail',
      pathParameters: {
        'contentId': '${p.placeId}',
        'contentTypeId': '12', // 기본 관광지
      },
      extra: p.firstImageUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAF8),
      appBar: AppBar(
        elevation: 0.6,
        backgroundColor: Colors.white,
        title: const Text('탐색', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          _searchBar(),
          _toggle(),
          Expanded(
            child: _view == 0 ? _listView() : const EmotionMapView(),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final m in Moods.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${m.emoji} ${m.key}'),
                      selected: _mood?.key == m.key,
                      onSelected: (s) => setState(() => _mood = s ? m : null),
                      selectedColor: const Color(0xFFFFE7E0),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _mood?.key == m.key
                            ? _accent
                            : const Color(0xFF555555),
                      ),
                      side: BorderSide(
                        color: _mood?.key == m.key
                            ? _accent
                            : const Color(0xFFE3D7D0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kw,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: '키워드 (예: 카페, 공원, 산책)',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
                onPressed: _loading ? null : _search,
                child: const Text('검색',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      alignment: Alignment.centerLeft,
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('목록'), icon: Icon(Icons.list)),
          ButtonSegment(value: 1, label: Text('지도'), icon: Icon(Icons.map_outlined)),
        ],
        selected: {_view},
        onSelectionChanged: (s) => setState(() => _view = s.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? _accent : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }

  Widget _listView() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_searched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '지금 기분에 맞는 장소를 찾아보세요.\n감정을 고르고 키워드로 검색해요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF7B6E67), height: 1.5),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF7B6E67), height: 1.5),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _PlaceCard(
        place: _results[i],
        onRecord: () => _record(_results[i]),
        onTap: () => _openDetail(_results[i]),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final EmotionMapPlace place;
  final VoidCallback onRecord;
  final VoidCallback onTap;
  const _PlaceCard(
      {required this.place, required this.onRecord, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dist = place.distanceKm != null
        ? '${place.distanceKm!.toStringAsFixed(1)}km'
        : null;
    final sub = [
      if (place.dominantEmotion != null) '주로 ${place.dominantEmotion}',
      if (dist != null) dist,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEAD7CE)),
        ),
        child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: moodColor(place.dominantEmotion),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8A8A92),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onRecord,
            icon: const Icon(Icons.edit_note, size: 18, color: Color(0xFFFB6A3E)),
            label: const Text(
              '기록',
              style: TextStyle(
                color: Color(0xFFFB6A3E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
