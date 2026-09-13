// 크루 만들기 시트 — 이슈 #417.
//
// ## 동네를 안 묻는다
//
// 이슈의 화면 표는 "이름 → 소개 → 동네(기본은 내 동네) → 공개 범위 → 정원" 이라고 적었다.
// 그중 **동네를 고르는 칸을 안 만든다** — 서버가 안 주면 내 동네를 쓰고, 내 동네를 고르는
// 화면은 이미 있다(`NeighborhoodPickerScreen`, #342). 여기에 고르는 칸을 또 만들면 같은
// 값을 정하는 자리가 둘이 되고, 두 값이 갈리는 날 사용자는 어느 쪽이 진짜인지 모른다.
//
// 대신 **내 동네를 한 줄로 보여 준다.** 안 골랐으면 그것을 말한다.
//
// ## 그런데 "안 골랐다" 를 막는 근거로는 안 쓴다
//
// 동네는 기기(`NeighborhoodStore`)에도, **계정**에도 있다. 앱은 기기에서만 읽으므로
// 재설치·새 기기에서는 계정에 동네가 있어도 기기가 비어 있다. 그때 버튼을 잠그면
// **만들 수 있는 사람이 못 만든다.** 그래서 공개 크루의 동네 판정은 계정을 아는 서버가
// 하고(400 과 그 문구), 화면은 무엇으로 만들어질지만 말한다.
import 'package:flutter/material.dart';

import '../data/crew_repository.dart';
import '../domain/crew.dart';
import '../domain/neighborhood.dart';
import '../theme/app_tokens.dart';
import 'form_kit.dart';

/// 만들기 시트를 띄운다.
///
/// @param myNeighborhood 내가 고른 동네. `null` 이면 안 골랐다는 뜻이라 공개를 막는다
/// @return 만들었으면 그 크루. 닫았으면 `null`
Future<Crew?> showCrewCreateSheet(
  BuildContext context, {
  required CrewRepository repository,
  Neighborhood? myNeighborhood,
}) {
  return showModalBottomSheet<Crew>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CrewCreateSheet(
      repository: repository,
      myNeighborhood: myNeighborhood,
    ),
  );
}

class _CrewCreateSheet extends StatefulWidget {
  final CrewRepository repository;
  final Neighborhood? myNeighborhood;

  const _CrewCreateSheet({required this.repository, this.myNeighborhood});

  @override
  State<_CrewCreateSheet> createState() => _CrewCreateSheetState();
}

class _CrewCreateSheetState extends State<_CrewCreateSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _intro = TextEditingController();

  CrewVisibility _visibility = CrewVisibility.invite;
  int _capacity = CrewRepository.defaultCapacity;

  bool _sending = false;

  /// 못 만든 이유. **빈 채로 닫지 않는다** — 왜 안 됐는지 모른 채로 시트가 사라지면
  /// 사용자는 같은 것을 다시 적는다.
  String? _error;

  @override
  void initState() {
    super.initState();
    // 글자 수 표시와 버튼 활성화가 타이핑을 따라가야 한다.
    _name.addListener(_onTyped);
  }

  void _onTyped() => setState(() {});

  @override
  void dispose() {
    _name.removeListener(_onTyped);
    _name.dispose();
    _intro.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_sending && _name.text.trim().isNotEmpty;

  /// 기기가 아는 내 동네가 없고 공개를 골랐다. **막는 값이 아니라 알려 주는 값이다** —
  /// 파일 머리말 참조.
  bool get _publicWithoutKnownNeighborhood =>
      _visibility.isPublic && widget.myNeighborhood == null;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final crew = await widget.repository.create(
        name: _name.text.trim(),
        intro: _intro.text.trim(),
        visibility: _visibility,
        capacity: _capacity,
      );
      if (!mounted) return;
      Navigator.of(context).pop(crew);
    } on CrewFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message ?? _reason(e.kind);
      });
    }
  }

  static String _reason(CrewFailureKind kind) => switch (kind) {
        CrewFailureKind.forbidden => '만 14세 미만은 크루를 만들 수 없어요.',
        CrewFailureKind.network => '연결이 끊겼어요. 잠시 뒤 다시 눌러 주세요.',
        _ => '크루를 만들지 못했어요.',
      };

  @override
  Widget build(BuildContext context) {
    // 틀·입력칸·버튼은 폼 부품이다(#445).
    return SheetFrame(
      title: '크루 만들기',
      subtitle: '만들면 대화방이 함께 생기고 내가 방장이 됩니다',
      children: [
              _field(
                controller: _name,
                hint: '성수동 아침 산책',
                label: '이름',
                maxLength: CrewRepository.maxNameLength,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _intro,
                hint: '천천히 걷습니다. 소형견 위주예요',
                label: '소개 (없어도 돼요)',
                maxLength: CrewRepository.maxIntroLength,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              _neighborhoodLine(),
              const SizedBox(height: 14),
              _visibilityPicker(),
              const SizedBox(height: 14),
              _capacityPicker(),
              if (_error case final message?) ...[
                const SizedBox(height: 12),
                Text(message,
                    key: const Key('crew-create-error'),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD2604F))),
              ],
              const SizedBox(height: 18),
              PrimaryButton(
                buttonKey: const Key('crew-create-submit'),
                label: _sending ? '만드는 중…' : '만들기',
                onPressed: _canSubmit ? _submit : null,
              ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int maxLength,
    int maxLines = 1,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FormLabel(label),
      GlassField(
        controller: controller,
        hint: hint,
        maxLength: maxLength,
        maxLines: maxLines,
      ),
    ]);
  }

  /// 내 동네 한 줄. **고르는 칸이 아니다** — 파일 머리말 참조.
  Widget _neighborhoodLine() {
    final mine = widget.myNeighborhood;
    return Row(children: [
      Icon(Icons.place_outlined,
          size: 16, color: mine == null ? T.textMuted : T.textSecondary),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          mine == null
              ? '내가 고른 동네로 만들어져요'
              : '${mine.label} 크루로 만들어져요',
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: mine == null ? T.textMuted : T.textSecondary),
        ),
      ),
    ]);
  }

  Widget _visibilityPicker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('공개 범위',
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
      const SizedBox(height: 6),
      Row(children: [
        for (final v in CrewVisibility.values) ...[
          Expanded(
            child: GestureDetector(
              key: Key('crew-visibility-${v.wire}'),
              onTap: () => setState(() => _visibility = v),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _visibility == v
                      ? T.accentLine
                      : Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _visibility == v ? T.accent : Colors.transparent),
                ),
                child: Center(
                  child: Text(v.label,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: _visibility == v ? T.textPrimary : T.textMuted)),
                ),
              ),
            ),
          ),
          if (v != CrewVisibility.values.last) const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 6),
      Text(
        _publicWithoutKnownNeighborhood
            ? '공개 크루는 동네가 있어야 해요 — 아직 안 골랐다면 먼저 골라 주세요'
            : _visibility.hint,
        key: const Key('crew-visibility-hint'),
        style: TextStyle(
            fontSize: 12,
            color:
                _publicWithoutKnownNeighborhood ? const Color(0xFFD2604F) : T.textMuted),
      ),
    ]);
  }

  Widget _capacityPicker() {
    return Row(children: [
      const Text('정원',
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
      const Spacer(),
      _stepButton(
        stepKey: const Key('crew-capacity-minus'),
        icon: Icons.remove_rounded,
        semantic: '정원 줄이기',
        onTap: _capacity > CrewRepository.minCapacity
            ? () => setState(() => _capacity--)
            : null,
      ),
      SizedBox(
        width: 56,
        child: Center(
          child: Text('$_capacity명',
              key: const Key('crew-capacity'),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ),
      ),
      _stepButton(
        stepKey: const Key('crew-capacity-plus'),
        icon: Icons.add_rounded,
        semantic: '정원 늘리기',
        onTap: _capacity < CrewRepository.maxCapacity
            ? () => setState(() => _capacity++)
            : null,
      ),
    ]);
  }

  Widget _stepButton({
    required Key stepKey,
    required IconData icon,
    required String semantic,
    VoidCallback? onTap,
  }) {
    return IconButton(
      key: stepKey,
      onPressed: onTap,
      tooltip: semantic,
      icon: Icon(icon, size: 20, color: onTap == null ? T.textFaint : T.textSecondary),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.7),
        shape: const CircleBorder(),
      ),
    );
  }
}
