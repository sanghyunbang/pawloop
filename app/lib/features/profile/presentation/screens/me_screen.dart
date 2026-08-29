import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:heat_trip_flutter/core/events/diary_events.dart';
import 'package:heat_trip_flutter/core/mood/mood.dart';
import 'package:heat_trip_flutter/core/mood/mood_color.dart';
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';
import 'package:heat_trip_flutter/features/auth/service/token_storage.dart';
import 'package:heat_trip_flutter/features/journey/data/journey_api.dart';
import 'package:heat_trip_flutter/features/journey/domain/models.dart';

/// "나" 탭 — 유저 정보 + 감정 통계 + 이번 달 감정 분포 + 메뉴.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  static const _accent = Color(0xFFFB6A3E);
  final _auth = AuthRepositoryImpl();
  final JourneyApi _api = RealJourneyApi();

  Map<String, dynamic>? _profile;
  List<DiaryEntry> _diaries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    diaryRevision.addListener(_onDiaryChanged); // 기록 변경 시 통계 갱신
  }

  @override
  void dispose() {
    diaryRevision.removeListener(_onDiaryChanged);
    super.dispose();
  }

  void _onDiaryChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    Map<String, dynamic>? profile;
    List<DiaryEntry> diaries = const [];
    try {
      final token = await TokenStorage.getToken();
      if (token != null) profile = await _auth.getMyProfile(token);
    } catch (_) {}
    try {
      diaries = await _api.fetchDiaries();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _profile = profile;
        _diaries = diaries;
        _loading = false;
      });
    }
  }

  static DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

  int get _streak {
    if (_diaries.isEmpty) return 0;
    final days = _diaries.map((e) => _d(e.date)).toSet();
    final today = _d(DateTime.now());
    var cursor = today;
    if (!days.contains(cursor)) {
      cursor = today.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }
    var c = 0;
    while (days.contains(cursor)) {
      c++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return c;
  }

  int get _thisMonth {
    final now = DateTime.now();
    return _diaries
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .length;
  }

  Map<String, int> get _moodCounts {
    final m = <String, int>{};
    for (final e in _diaries) {
      if (Moods.byKey(e.moodLabel) != null) {
        m[e.moodLabel] = (m[e.moodLabel] ?? 0) + 1;
      }
    }
    return m;
  }

  Future<void> _logout() async {
    await TokenStorage.clearToken();
    if (mounted) context.goNamed('login');
  }

  @override
  Widget build(BuildContext context) {
    final nickname =
        (_profile?['nickname'] ??
                _profile?['name'] ??
                _profile?['userNickname'] ??
                '여행자')
            .toString();
    final email = (_profile?['email'] ?? '').toString();
    final initial = nickname.isNotEmpty ? nickname.characters.first : 'M';

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAF8),
      appBar: AppBar(
        elevation: 0.6,
        backgroundColor: Colors.white,
        title: const Text('나', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: '프로필 편집',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final changed = await context.pushNamed('profileEdit');
              if (changed == true) _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _header(nickname, email, initial),
                  const SizedBox(height: 16),
                  _statsRow(),
                  const SizedBox(height: 16),
                  _moodSummary(),
                  const SizedBox(height: 16),
                  _menu(),
                ],
              ),
            ),
    );
  }

  Widget _header(String nickname, String email, String initial) {
    return Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: _accent.withValues(alpha: 0.15),
          child: Text(
            initial,
            style: const TextStyle(
              color: _accent,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nickname,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    color: Color(0xFF8A8A92),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statsRow() {
    Widget item(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF7B6E67)),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: Row(
        children: [
          item('${_diaries.length}', '총 기록'),
          _divider(),
          item('$_streak일', '연속 기록'),
          _divider(),
          item('$_thisMonth', '이번 달'),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 34, color: const Color(0xFFEDEDF1));

  Widget _moodSummary() {
    final counts = _moodCounts;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final top = counts.entries.isEmpty
        ? null
        : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '내 감정 분포',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (top != null)
                Text(
                  '가장 많이 · $top',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: moodColor(top),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (total == 0)
            const Text(
              '아직 기록이 없어요. 오늘의 마음을 남겨보세요.',
              style: TextStyle(color: Color(0xFF8A8A92), fontSize: 13),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  for (final m in Moods.all)
                    if ((counts[m.key] ?? 0) > 0)
                      Expanded(
                        flex: counts[m.key]!,
                        child: Container(height: 14, color: moodColor(m.key)),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (final m in Moods.all)
                  if ((counts[m.key] ?? 0) > 0)
                    Row(
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
                        const SizedBox(width: 5),
                        Text(
                          '${m.key} ${counts[m.key]}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _menu() {
    Widget tile(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color color = const Color(0xFF333333),
    }) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: color,
          fontSize: 14.5,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFB8B8C3)),
      onTap: onTap,
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: Column(
        children: [
          tile(Icons.edit_outlined, '프로필 편집', () async {
            final changed = await context.pushNamed('profileEdit');
            if (changed == true) _load();
          }),
          const Divider(height: 1, color: Color(0xFFEDEDF1)),
          tile(Icons.bookmark_border, '북마크', () {
            context.push('/bookmarks');
          }),
          const Divider(height: 1, color: Color(0xFFEDEDF1)),
          tile(Icons.logout, '로그아웃', _logout, color: const Color(0xFFE05A5A)),
        ],
      ),
    );
  }
}
