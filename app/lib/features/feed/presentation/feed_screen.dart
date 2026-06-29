import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:heat_trip_flutter/core/events/diary_events.dart';
import 'package:heat_trip_flutter/features/journey/data/journey_api.dart';
import 'package:heat_trip_flutter/features/journey/domain/models.dart';
import 'package:heat_trip_flutter/features/journey/presentation/screens/diary_edit_screen.dart';
import 'package:heat_trip_flutter/features/journey/presentation/widgets/diary_list.dart';
import 'package:heat_trip_flutter/features/journey/presentation/widgets/emotion_calendar_card.dart';
import 'package:heat_trip_flutter/features/social/data/social_repository.dart';
import 'package:heat_trip_flutter/features/social/presentation/together_feed.dart';

/// 피드 — [내 기록]: 감정 캘린더 + 기록 / [함께]: 공유된 감정 카드 + 리액션.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const _accent = Color(0xFFFB6A3E);
  final JourneyApi _api = RealJourneyApi();
  final SocialRepository _social = SocialRepository();
  final GlobalKey<TogetherFeedState> _togetherKey =
      GlobalKey<TogetherFeedState>();

  late Future<List<DiaryEntry>> _diariesF = _api.fetchDiaries();
  int _tab = 0; // 0=내 기록, 1=함께

  @override
  void initState() {
    super.initState();
    diaryRevision.addListener(_onDiaryChanged); // 기록 추가/수정/삭제 시 자동 갱신
  }

  @override
  void dispose() {
    diaryRevision.removeListener(_onDiaryChanged);
    super.dispose();
  }

  void _onDiaryChanged() {
    if (mounted) _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _diariesF = _api.fetchDiaries();
    });
    await _diariesF;
  }

  Future<void> _handleDelete(DiaryEntry e) async {
    if (e.id == null) return;
    try {
      await _api.deleteDiary(e.id!);
      notifyDiaryChanged(); // 피드/나 자동 갱신
      _toast('다이어리를 삭제했어요.');
    } catch (err) {
      _toast('삭제 실패: $err');
    }
  }

  Future<void> _handleEdit(DiaryEntry e) async {
    final updated = await Navigator.push<DiaryEntry>(
      context,
      MaterialPageRoute(builder: (_) => DiaryEditScreen(entry: e)),
    );
    if (updated != null) notifyDiaryChanged();
  }

  void _openDetail(DiaryEntry e) {
    context.pushNamed(
      'diaryDetail',
      pathParameters: {
        'id': (e.scheduleId ?? 0).toString(),
        'entryId': (e.id ?? 0).toString(),
      },
      extra: e,
    );
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _shareDiary(DiaryEntry e) async {
    final handleCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('감정 카드로 공유',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('이 기록을 "함께" 피드에 나눠요. 위치는 동 단위로만 표시돼요.',
                style: TextStyle(color: Color(0xFF7B6E67), fontSize: 12.5)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e.moodLabel} · ${e.title}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(e.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF555555), fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: handleCtrl,
              decoration: InputDecoration(
                hintText: '표시 이름 (비우면 익명)',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('공유하기',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final handle = handleCtrl.text.trim();
      await _social.share(
        moodKey: e.moodLabel,
        body: e.body.isEmpty ? e.title : e.body,
        placeName: (e.location.isNotEmpty && e.location != '—') ? e.location : null,
        placeId: e.placeId,
        handle: handle.isEmpty ? null : handle,
      );
      _toast('함께 피드에 공유했어요.');
      setState(() => _tab = 1);
      _togetherKey.currentState?.reload();
    } catch (err) {
      _toast('공유 실패: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAF8),
      appBar: AppBar(
        elevation: 0.6,
        backgroundColor: Colors.white,
        title: const Text('피드', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          _tabToggle(),
          Expanded(
            child: _tab == 0
                ? _myRecords()
                : TogetherFeed(key: _togetherKey),
          ),
        ],
      ),
    );
  }

  Widget _tabToggle() {
    Widget seg(int i, String label) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          child: Container(
            height: 38,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: on ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : const Color(0xFF8A8A92),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [seg(0, '내 기록'), seg(1, '함께')]),
      ),
    );
  }

  Widget _myRecords() {
    return FutureBuilder<List<DiaryEntry>>(
      future: _diariesF,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data ?? const <DiaryEntry>[];
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 28),
            children: [
              EmotionCalendarCard(entries: entries),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('내 기록',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 28, 16, 28),
                  child: Center(
                    child: Text(
                      '아직 기록이 없어요.\n가운데 + 버튼으로 오늘의 마음을 남겨보세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF7B6E67), height: 1.5),
                    ),
                  ),
                )
              else
                DiaryList(
                  entries: entries,
                  embedded: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  onEdit: _handleEdit,
                  onDelete: _handleDelete,
                  onShare: _shareDiary,
                  onTap: _openDetail,
                ),
            ],
          ),
        );
      },
    );
  }
}
