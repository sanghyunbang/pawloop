// 할 일 고치기 — 이슈 #560 조각 3.
//
// 그 집이 챙기는 일의 목록을 만들고 고치고 접고 끌어서 옮긴다. 홈 카드는 이 순서 그대로
// 그린다(조각 4).
//
// **접힌 것도 한 목록에 있다.** 따로 빼면 "다시 켜기" 를 그릴 자리가 사라진다 — 카드만
// `archived` 로 거른다.
import 'package:flutter/material.dart';

import '../data/family_repository.dart';
import '../domain/care_icons.dart';
import '../domain/pet.dart' show kCareRev;
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 카드가 바뀌었음을 알리는 축 — 홈 카드가 이 값을 보고 다시 읽는다(조각 4).
///
/// `kCareRev` 를 그대로 쓰는 이유는, 항목이 바뀌면 카드도 바뀌어야 하는데 그 둘이 서로
/// 다른 축을 보면 목록을 고친 뒤 홈으로 돌아가도 칸이 그대로 남기 때문이다.
class CareItemsScreen extends StatefulWidget {
  final int groupId;

  /// 테스트가 가짜를 물리는 자리 — 다른 화면과 같은 규약이다(`FamilyScreen`·`TodayCareCard`).
  final FamilyRepository? repository;

  const CareItemsScreen({super.key, required this.groupId, this.repository});

  @override
  State<CareItemsScreen> createState() => _CareItemsScreenState();
}

class _CareItemsScreenState extends State<CareItemsScreen> {
  late final FamilyRepository _repo = widget.repository ?? FamilyRepository();

  List<CareItemEntry> _items = const [];
  bool _loading = true;
  String? _failure;

  /// 서버에 순서를 보내는 동안 목록을 다시 읽지 않는다 — 끌어 놓은 자리가 되돌아간다.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final items = await _repo.careItems(widget.groupId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure = e.message;
      });
    }
  }

  // ─────────────────────────── 쓰기 ───────────────────────────

  /// 끌어 놓기. **화면을 먼저 바꾸고 서버에 보낸다** — 손을 뗀 자리에서 칸이 튀면 안 된다.
  ///
  /// 실패하면 되읽어서 서버의 순서로 되돌린다. 빠뜨린 항목이 있으면 서버가 거절하는데
  /// (400), 그때 화면만 바뀐 채로 두면 다음에 들어올 때 순서가 달라져 있다.
  ///
  /// `onReorderItem` 을 쓴다(`onReorder` 는 deprecated). 둘의 차이는 **한 칸**이다 —
  /// 옛 콜백의 `newIndex` 는 "빼기 전" 기준이라 아래로 옮길 때 1 을 빼야 했고, 이건 이미
  /// 조정된 값이다. 잘못 쓰면 한 칸씩 어긋나므로 위젯 테스트가 결과 순서를 잰다.
  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_saving) return;
    final moved = [..._items];
    moved.insert(newIndex, moved.removeAt(oldIndex));

    setState(() {
      _items = moved;
      _saving = true;
    });
    try {
      await _repo.reorderCareItems(widget.groupId, moved.map((i) => i.id).toList());
      kCareRev.value++;
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      _message(e.message);
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleArchive(CareItemEntry item) async {
    try {
      if (item.archived) {
        await _repo.replaceCareItem(
          widget.groupId,
          item.id,
          name: item.name,
          icon: item.icon,
          dogId: item.dogId,
          dailyTarget: item.dailyTarget,
          archived: false,
        );
      } else {
        await _repo.archiveCareItem(widget.groupId, item.id);
      }
      kCareRev.value++;
      await _load();
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      _message(e.message);
    }
  }

  Future<void> _openEditor({CareItemEntry? item}) async {
    final draft = await showModalBottomSheet<_Draft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemEditorSheet(item: item),
    );
    if (draft == null) return;

    try {
      if (item == null) {
        await _repo.createCareItem(
          widget.groupId,
          name: draft.name,
          icon: draft.icon,
          dailyTarget: draft.dailyTarget,
        );
      } else {
        await _repo.replaceCareItem(
          widget.groupId,
          item.id,
          name: draft.name,
          icon: draft.icon,
          dogId: item.dogId,
          dailyTarget: draft.dailyTarget,
          archived: item.archived,
        );
      }
      kCareRev.value++;
      await _load();
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      _message(e.message);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        // 버튼을 달지 않는다 — 플러터 3.32 는 action 이 있으면 duration 을 무시해서
        // 말풍선이 탭 바를 덮은 채로 안 사라진다(#531).
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─────────────────────────── 화면 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('care-items-back'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: T.textPrimary),
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '할 일 고치기',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: T.textPrimary,
                            ),
                          ),
                          Text(
                            '끌어서 순서 · 눌러서 고치기 · 접으면 카드에서 사라져요',
                            style: TextStyle(fontSize: 12.5, color: T.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
      floatingActionButton: _loading || _failure != null
          ? null
          : FloatingActionButton.extended(
              key: const Key('care-item-add'),
              onPressed: () => _openEditor(),
              backgroundColor: T.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('추가'),
            ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final failure = _failure;
    if (failure != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              failure,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: T.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(
              key: const Key('care-items-retry'),
              onPressed: _load,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    // 목록이 빈 경우는 정상 경로에 없다 — 가족을 만들면 기본 일곱이 들어간다. 그래도
    // 비어 보이는 순간이 있으면 "추가" 를 찾을 수 있게 한 줄 적는다.
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          '아직 챙길 일이 없어요.\n아래 + 로 하나 만들어 보세요.',
          key: Key('care-items-empty'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: T.textMuted),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: _items.length,
      onReorderItem: _reorder,
      // 기본 손잡이를 끈다. 켜 두면 **줄 전체를 길게 눌러야** 끌 수 있는데, 이 줄은 눌러서
      // 고치기로도 들어가므로 "길게 누르면 끌기 · 짧게 누르면 고치기" 가 한 손가락에
      // 겹친다. 오른쪽 손잡이만 끌게 하면 무엇을 하는지가 보인다.
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) => _row(_items[index], index),
    );
  }

  Widget _row(CareItemEntry item, int index) {
    final dim = item.archived;
    // Material 로 감싼다(Container + decoration 이 아니라). 불투명한 배경을 가진
    // DecoratedBox 가 ListTile 과 Material 사이에 끼면, 누를 때 번지는 잉크가 그 상자 뒤로
    // 가려 아무 반응이 없어 보인다 — 플러터가 테스트에서 그것을 예외로 알려 준다.
    return Padding(
      key: Key('care-item-${item.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: T.cardBg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: T.cardBorder),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          leading: Icon(careItemIcon(item.icon), color: dim ? T.textFaint : T.accent, size: 22),
          title: Text(
            item.name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: dim ? T.textMuted : T.textPrimary,
              decoration: dim ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Text(_subtitle(item), style: const TextStyle(fontSize: 12, color: T.textMuted)),
          onTap: () => _openEditor(item: item),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('care-item-archive-${item.id}'),
                tooltip: dim ? '다시 켜기' : '접기',
                onPressed: () => _toggleArchive(item),
                icon: Icon(
                  dim ? Icons.undo_rounded : Icons.visibility_off_rounded,
                  size: 20,
                  color: T.textMuted,
                ),
              ),
              ReorderableDragStartListener(
            key: Key('care-item-drag-${item.id}'),
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Icon(Icons.drag_handle_rounded, size: 22, color: T.textFaint),
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }

  /// 한 줄 설명 — 접힘 · 하루 목표 · 기본 항목 표시를 한 자리에서 만든다.
  static String _subtitle(CareItemEntry item) {
    final parts = <String>[
      if (item.archived) '접힘 · 카드에 안 보여요',
      if (item.dailyTarget != null) '하루 ${item.dailyTarget}번',
      // 기본 항목이라고 못 고치는 것은 아니다 — 종류만 안 바뀐다. 그 사실을 적어 두면
      // "왜 이것만 다르지" 를 묻지 않아도 된다.
      if (item.isSystem) '기본 항목',
    ];
    return parts.isEmpty ? '눌러서 이름과 그림을 고쳐요' : parts.join(' · ');
  }
}

/// 시트가 돌려주는 값. 화면이 서버에 보낼 것만 든다.
class _Draft {
  final String name;
  final String icon;
  final int? dailyTarget;

  const _Draft({required this.name, required this.icon, this.dailyTarget});
}

/// 만들기 · 고치기 시트. [item] 이 있으면 고치기다.
class _ItemEditorSheet extends StatefulWidget {
  final CareItemEntry? item;

  const _ItemEditorSheet({this.item});

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.item?.name ?? '');
  late String _icon = widget.item?.icon ?? 'etc';
  late int? _target = widget.item?.dailyTarget;

  /// 이름 길이 상한. 서버도 같은 수로 거절한다 — 여기서 먼저 막는 이유는 왕복 한 번을
  /// 아끼려는 것이지 서버 검증을 대신하려는 것이 아니다.
  static const int _maxName = 20;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: T.surfaceBright,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: T.line, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                editing ? '할 일 고치기' : '할 일 추가',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: T.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('care-item-name'),
              controller: _name,
              maxLength: _maxName,
              autofocus: !editing,
              decoration: const InputDecoration(
                labelText: '이름',
                hintText: '양치 · 심장사상충 약',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '그림',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kCareIconKeys.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _iconChip(kCareIconKeys[i]),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text(
                  '하루 목표',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: T.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      children: [
                        _targetChip(null, '없음'),
                        for (final n in [1, 2, 3, 4]) _targetChip(n, '$n번'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '비워 두면 횟수만 세고, 정하면 카드에 1/2 로 보여요.',
                style: TextStyle(fontSize: 11.5, color: T.textMuted),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('care-item-save'),
                style: FilledButton.styleFrom(backgroundColor: T.accent),
                onPressed: _save,
                child: Text(editing ? '고치기' : '추가'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconChip(String key) {
    final chosen = key == _icon;
    return GestureDetector(
      key: Key('care-icon-$key'),
      onTap: () => setState(() => _icon = key),
      child: Container(
        width: 56,
        decoration: BoxDecoration(
          color: chosen ? T.accentSoft : T.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: chosen ? T.accent : T.cardBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(careItemIcon(key), size: 20, color: chosen ? T.accent : T.textSecondary),
            const SizedBox(height: 2),
            Text(
              careIconLabel(key),
              style: TextStyle(fontSize: 10, color: chosen ? T.accent : T.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetChip(int? value, String label) {
    final chosen = value == _target;
    return ChoiceChip(
      key: Key('care-target-${value ?? 'none'}'),
      label: Text(label),
      selected: chosen,
      onSelected: (_) => setState(() => _target = value),
      selectedColor: T.accentSoft,
      labelStyle: TextStyle(fontSize: 12, color: chosen ? T.accent : T.textSecondary),
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      // 서버도 거절하지만, 빈 이름으로 왕복을 돌면 사용자는 "왜 안 되지" 를 기다린다.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이름을 적어 주세요'), duration: Duration(seconds: 2)));
      return;
    }
    Navigator.of(context).pop(_Draft(name: name, icon: _icon, dailyTarget: _target));
  }
}
