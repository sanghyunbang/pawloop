// 부탁 올리기 시트 — 이슈 #417. 서버는 PR #428.
//
// ## 시간대에 기본값이 없다
//
// 날짜는 오늘이 기본이지만 시간대는 비워 둔다. 셋 중 하나를 미리 골라 두면 그것을 안 바꾼 채
// 올리는 사람이 생기고, 그 부탁은 시간대가 틀린 채로 달력에 남는다. 한 번 누르는 값이라
// 기본값이 아끼는 것이 거의 없다. 날짜는 다르다 — 버튼에 "오늘 · 9월 13일 (일)" 이 크게
// 보이고, 오늘 저녁에 급히 맡길 사람이 실제로 있다.
//
// ## 아이는 내 아이 중에서만
//
// 서버는 남의 아이를 404 로 거절한다. 여기서는 `kMyPets` 중 **서버 id 가 있는** 아이만
// 고르게 한다 — 서버에 없는 아이는 보낼 id 가 없다(`WalkDogPicker` 와 같은 판단). 한 마리면
// 미리 골라져 있고, 한 마리도 없으면 아이 칸 자체가 없다 — 아이를 아직 등록 안 한 사람도
// 부탁할 수 있다.
//
// ## 돈 이야기가 없다
//
// 금액 칸이 없고 한 줄만 있다. 시각·장소도 안 받는다 — 둘이 대화방에서 정한다. 이슈가 그은
// 선이고(결제·평점·보증·중개는 안 한다), 시트가 그 선을 첫 줄에서 말한다.
import 'package:flutter/material.dart';

import '../data/crew_repository.dart';
import '../domain/crew_favor.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';

/// 부탁 올리기 시트를 띄운다.
///
/// @param pets 고를 수 있는 아이들. 안 주면 [kMyPets] 다 — 테스트가 갈아 끼운다
/// @param today "오늘". 안 주면 기기 시계다 — 테스트가 고정한다
/// @return 올렸으면 그 부탁. 닫았으면 `null`
Future<CrewFavor?> showCrewFavorSheet(
  BuildContext context, {
  required CrewRepository repository,
  required int crewId,
  List<DogProfile>? pets,
  DateTime? today,
}) {
  return showModalBottomSheet<CrewFavor>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CrewFavorSheet(
      repository: repository,
      crewId: crewId,
      pets: pets ?? kMyPets.value,
      today: today ?? DateTime.now(),
    ),
  );
}

class CrewFavorSheet extends StatefulWidget {
  final CrewRepository repository;
  final int crewId;
  final List<DogProfile> pets;
  final DateTime today;

  const CrewFavorSheet({
    super.key,
    required this.repository,
    required this.crewId,
    required this.pets,
    required this.today,
  });

  /// 얼마나 앞까지 고를 수 있나. 서버에는 상한이 없지만 달력 고르기에는 끝이 있어야 한다.
  static const Duration horizon = Duration(days: 365);

  @override
  State<CrewFavorSheet> createState() => _CrewFavorSheetState();
}

class _CrewFavorSheetState extends State<CrewFavorSheet> {
  final TextEditingController _note = TextEditingController();

  late final DateTime _today =
      DateTime(widget.today.year, widget.today.month, widget.today.day);
  late DateTime _date = _today;

  /// 비워 둔다 — 파일 머리말 참조.
  CrewFavorSlot? _slot;

  late final List<DogProfile> _sendable =
      widget.pets.where((p) => p.serverId != null).toList();

  /// 고른 아이의 서버 id. `null` 이면 "아이 없이" 다.
  late int? _dogId = _sendable.isEmpty ? null : _sendable.first.serverId;

  bool _sending = false;

  /// 못 올린 이유. **빈 채로 닫지 않는다** — 왜 안 됐는지 모른 채로 시트가 사라지면
  /// 사용자는 같은 것을 다시 적는다.
  String? _error;

  bool get _isToday => _date == _today;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // 지난 날짜는 서버가 400 이다 — 고르지도 못하게 한다.
      firstDate: _today,
      lastDate: _today.add(CrewFavorSheet.horizon),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _submit() async {
    final slot = _slot;
    if (slot == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final favor = await widget.repository.postFavor(
        widget.crewId,
        onDate: _date,
        slot: slot,
        dogId: _dogId,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(favor);
    } on CrewFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _reason(e);
      });
    }
  }

  static String _reason(CrewFailure e) => switch (e.kind) {
        CrewFailureKind.network => '연결이 끊겼어요. 잠시 뒤 다시 시도해 주세요.',
        // 크루에서 나갔거나 아이를 지웠거나 — 서버 문구가 어느 쪽인지 말한다.
        CrewFailureKind.notFound => e.message ?? '크루를 찾을 수 없어요.',
        _ => e.message ?? '올리지 못했어요.',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: T.lilacTop,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('부탁 올리기',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const SizedBox(height: 4),
              const Text('시각과 장소는 대화방에서 정해요 · 돈이 오가는 약속은 여기서 안 해요',
                  style: TextStyle(fontSize: 12.5, color: T.textMuted, height: 1.35)),
              const SizedBox(height: 14),
              _label('언제'),
              const SizedBox(height: 6),
              GestureDetector(
                key: const Key('crew-favor-date'),
                onTap: _sending ? null : _pickDate,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded, size: 16, color: T.textMuted),
                    const SizedBox(width: 10),
                    Text(
                      _isToday
                          ? '오늘 · ${CrewFavor.dayLabel(_date)}'
                          : CrewFavor.dayLabel(_date),
                      key: const Key('crew-favor-date-label'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                for (final slot in CrewFavorSlot.values) ...[
                  Expanded(
                    child: _chip(
                      key: Key('crew-favor-slot-${slot.wire}'),
                      label: slot.label,
                      on: _slot == slot,
                      onTap: () => setState(() => _slot = slot),
                    ),
                  ),
                  if (slot != CrewFavorSlot.values.last) const SizedBox(width: 8),
                ],
              ]),
              if (_sendable.isNotEmpty) ...[
                const SizedBox(height: 14),
                _label('누구를'),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final pet in _sendable)
                    _chip(
                      key: Key('crew-favor-dog-${pet.serverId}'),
                      label: pet.name,
                      on: _dogId == pet.serverId,
                      onTap: () => setState(() => _dogId = pet.serverId),
                      tight: true,
                    ),
                  _chip(
                    key: const Key('crew-favor-dog-none'),
                    label: '아이 없이',
                    on: _dogId == null,
                    onTap: () => setState(() => _dogId = null),
                    tight: true,
                  ),
                ]),
              ],
              const SizedBox(height: 14),
              _label('한 줄'),
              const SizedBox(height: 6),
              TextField(
                key: const Key('crew-favor-note'),
                controller: _note,
                enabled: !_sending,
                maxLength: CrewRepository.maxFavorNoteLength,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: '예: 두 시간만 부탁드려요',
                  hintStyle: const TextStyle(fontSize: 13.5, color: T.textFaint),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.75),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              if (_error case final message?) ...[
                const SizedBox(height: 10),
                Text(message,
                    key: const Key('crew-favor-error'),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD2604F))),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('crew-favor-submit'),
                  // 시간대를 안 골랐으면 잠긴다 — 그리고 버튼이 그 이유를 말한다.
                  onPressed: _slot == null || _sending ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: T.sigEnd,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _sending
                        ? '올리는 중…'
                        : (_slot == null ? '시간대를 골라 주세요' : '부탁 올리기'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary));

  Widget _chip({
    required Key key,
    required String label,
    required bool on,
    required VoidCallback onTap,
    bool tight = false,
  }) {
    return GestureDetector(
      key: key,
      onTap: _sending ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: tight
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
            : const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: on ? T.sigEnd.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? T.sigEnd : Colors.transparent),
        ),
        child: Center(
          widthFactor: tight ? 1 : null,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: on ? T.textPrimary : T.textMuted)),
        ),
      ),
    );
  }
}
