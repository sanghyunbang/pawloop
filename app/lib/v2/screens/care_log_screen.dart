// 케어 기록 — 날짜별로 본다. 이슈 #737.
//
// ## 무엇을 위한 화면인가
//
// 홈의 "오늘의 케어" 는 **오늘**만 말한다 — 칸은 마지막 하나, "오늘 한 일" 은 오늘 것 세 줄.
// 가족이 "어제 약은 줬나", "이번 주 산책은 누가 몇 번" 을 물으면 답할 자리가 없었다(
// 2026-09-20: "하루를 기준으로 로그가 정리돼서 볼 수 있게, 기록도 남기고"). 이 화면이 그 자리다 —
// **하루 한 장**, 아이별로 묶어, 시각 순으로, 누가 · 무엇.
//
// ## 서버는 이미 날짜를 받는다
//
// `GET /api/groups/{id}/care-logs?date=YYYY-MM-DD` 가 있다(#209). 새 API 없이 날짜만 넘긴다.
// 지운 기록은 서버에 없으니 여기도 없다 — "기록도 남기고" 는 지우지 않는 한 남는다는 뜻이다.
// 아이로 거르지 않는다 — 가족의 하루를 보는 자리라, 어느 아이 것이든 다 온다.
//
// ## 순서는 이른 것부터
//
// 홈 카드는 최근 순이다(세 줄만 보여서 방금 누른 것이 보여야 한다). 여기는 하루 전체를 펴므로
// **아침부터 밤으로** 읽는 것이 일기처럼 자연스럽다.
import 'package:flutter/material.dart';

import '../data/family_repository.dart';
import '../domain/pet.dart' show kMyPets;
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/care_log_line.dart';

class CareLogScreen extends StatefulWidget {
  final int groupId;

  /// 테스트가 갈아 끼운다.
  final FamilyRepository? repository;

  /// 테스트가 고정하는 "오늘". 없으면 기기 시계.
  final DateTime? today;

  const CareLogScreen({super.key, required this.groupId, this.repository, this.today});

  @override
  State<CareLogScreen> createState() => _CareLogScreenState();
}

/// 아이 하나의 하루 — 화면이 묶은 단위.
class _DogGroup {
  final int? dogId;
  final String title;
  final List<CareLogEntry> logs;

  const _DogGroup(this.dogId, this.title, this.logs);
}

class _CareLogScreenState extends State<CareLogScreen> {
  late final FamilyRepository _repo = widget.repository ?? FamilyRepository();

  late DateTime _day = _today;
  List<CareLogEntry> _logs = const [];

  /// 그 집의 칸 목록 — 기록의 이름을 붙이려고 한 번만 읽는다. 못 읽으면 종류 이름으로 적는다.
  List<CareItemEntry> _items = const [];
  bool _itemsLoaded = false;

  bool _loading = true;
  bool _failed = false;

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  DateTime get _today => _dateOnly(widget.today ?? DateTime.now());

  bool get _isToday => _day == _today;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final day = _day;
    if (!_itemsLoaded) {
      try {
        _items = await _repo.careItems(widget.groupId);
      } on FamilyFailure {
        _items = const [];
      }
      _itemsLoaded = true;
    }
    try {
      final logs = await _repo.careLogs(widget.groupId, date: day);
      // 기다리는 사이 다른 날로 갔으면 그 답은 버린다 — 늦게 온 어제가 오늘을 덮으면 안 된다.
      if (!mounted || day != _day) return;
      setState(() {
        _logs = logs;
        _loading = false;
      });
    } on FamilyFailure {
      if (!mounted || day != _day) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _go(int days) {
    setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));
    _load();
  }

  Future<void> _pickDay() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() => _day = _dateOnly(picked));
    _load();
  }

  // ─────────────────────── 그리기 ───────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      appBar: AppBar(
        title: const Text('케어 기록'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: T.textPrimary,
      ),
      body: AuroraBackground(
        child: SafeArea(
          top: false,
          child: Column(children: [
            _dayBar(),
            Expanded(child: _body()),
          ]),
        ),
      ),
    );
  }

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  /// "오늘 · 9월 20일 (일)" — 가까운 날은 말로 먼저. 달력 숫자보다 "어제" 가 빨리 읽힌다.
  String _dayLabel(DateTime d) {
    final base = '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';
    final diff = _today.difference(d).inDays;
    if (diff == 0) return '오늘 · $base';
    if (diff == 1) return '어제 · $base';
    if (diff == 2) return '그저께 · $base';
    return base;
  }

  Widget _dayBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(children: [
          IconButton(
            key: const Key('care-log-prev'),
            tooltip: '전날',
            onPressed: () => _go(-1),
            icon: const Icon(Icons.chevron_left_rounded),
            color: T.textSecondary,
          ),
          Expanded(
            child: GestureDetector(
              key: const Key('care-log-day'),
              behavior: HitTestBehavior.opaque,
              onTap: _pickDay,
              child: Text(_dayLabel(_day),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
            ),
          ),
          // 오늘을 넘지 않는다 — 내일의 기록은 없고, 있는 것처럼 보이면 "안 했다" 로 읽힌다.
          IconButton(
            key: const Key('care-log-next'),
            tooltip: '다음 날',
            onPressed: _isToday ? null : () => _go(1),
            icon: const Icon(Icons.chevron_right_rounded),
            color: T.textSecondary,
          ),
        ]),
      );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: T.accent));
    }
    if (_failed) {
      // 빈 화면으로 그리면 "아무도 아무것도 안 했다" 로 읽힌다 — 카드와 같은 이유(#76).
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('연결이 불안정해요',
              style: TextStyle(fontSize: 14, color: T.textSecondary)),
          TextButton(
            key: const Key('care-log-retry'),
            onPressed: _load,
            child: const Text('다시 시도'),
          ),
        ]),
      );
    }
    if (_logs.isEmpty) {
      return const Center(
        child: Text('이날은 기록이 없어요',
            key: Key('care-log-empty'),
            style: TextStyle(fontSize: 14, color: T.textSecondary)),
      );
    }

    final groups = _byDog(_logs);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(_summary(),
            key: const Key('care-log-summary'),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: T.textMuted)),
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(g.title,
                key: Key('care-log-dog-${g.dogId ?? 'none'}'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: T.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: T.cardBorder),
            ),
            child: Column(children: [
              for (final (i, log) in g.logs.indexed) ...[
                if (i > 0) const SizedBox(height: 6),
                CareLogLine(
                    key: Key('care-log-line-${log.id}'), log: log, name: log.nameAmong(_items)),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  /// 아이별로 묶는다 — 내 아이 순서(홈과 같은 순서)로, 목록에 없는 아이는 그 뒤에, 아이가
  /// 안 적힌 기록은 맨 끝에. 묶음 안은 이른 것부터.
  List<_DogGroup> _byDog(List<CareLogEntry> logs) {
    final sorted = logs.toList()..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final byId = <int?, List<CareLogEntry>>{};
    for (final log in sorted) {
      (byId[log.dogId] ??= []).add(log);
    }
    final out = <_DogGroup>[];
    for (final pet in kMyPets.value) {
      final id = pet.serverId;
      final mine = id == null ? null : byId.remove(id);
      if (mine != null) out.add(_DogGroup(id, pet.name, mine));
    }
    for (final id in byId.keys.whereType<int>().toList()) {
      out.add(_DogGroup(id, '아이 #$id', byId.remove(id)!));
    }
    final rest = byId[null];
    if (rest != null) out.add(_DogGroup(null, '아이 안 정함', rest));
    return out;
  }

  /// "4건 · 물 2 · 밥 1 · 병원 1" — 항목 순서는 그 집이 카드에 늘어놓은 순서, 짝 없는 것은
  /// 그 뒤에 **처음 한 시각 순**으로. 서버가 준 순서에 기대지 않는다(묶음과 같은 이유).
  String _summary() {
    final sorted = _logs.toList()..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final counts = <String, int>{};
    for (final log in sorted) {
      counts.update(log.nameAmong(_items), (n) => n + 1, ifAbsent: () => 1);
    }
    final inOrder = _items.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final names = <String>[
      for (final item in inOrder)
        if (counts.containsKey(item.name)) item.name,
    ];
    for (final name in counts.keys) {
      if (!names.contains(name)) names.add(name);
    }
    return ['${_logs.length}건', for (final n in names) '$n ${counts[n]}'].join(' · ');
  }
}
