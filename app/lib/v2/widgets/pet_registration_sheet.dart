// lib/v2/widgets/pet_registration_sheet.dart
//
// 반려동물을 서버에 등록하는 **유일한 폼** — 이슈 #159.
//
// ## 왜 한 곳인가
//
// 등록이 필요한 자리가 셋이다.
//
//   1. 온보딩 — 처음 들어온 사람에게 권한다
//   2. 산책 저장 — 온보딩을 건너뛴 사람이 저장하려는 순간. **여기가 사용자가 "왜
//      필요한지" 아는 유일한 시점이다**
//   3. 프로필 '추가' — 두 번째 아이
//
// 셋이 각자 폼을 그리면 필드가 갈라지고, 한 곳만 고쳐지는 날이 온다.
//
// ## 등록을 강제하지 않는다
//
// 로그인 화면에 "그냥 둘러보기" 가 있다. 온보딩에서 등록을 필수로 만들면 구경만 하려는
// 사람도 폼을 채워야 한다. 그래서 권하되 건너뛸 수 있게 하고, **산책을 저장하려는
// 순간에 잡는다** — 그때는 이유가 분명하다.
library;

import 'package:flutter/material.dart';

import '../data/pet_sync.dart';
import '../data/walk_repository.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';

/// 등록 시트를 띄운다.
///
/// @param reason 왜 지금 등록을 권하는지. 산책 저장에서 부를 때는 그 이유를 준다 —
///               맥락 없이 폼만 뜨면 사용자는 왜 막혔는지 모른다
/// @return 등록했으면 그 프로필. 닫았으면 `null`
Future<DogProfile?> showPetRegistrationSheet(
  BuildContext context, {
  String? reason,
}) {
  return showModalBottomSheet<DogProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PetRegistrationSheet(reason: reason),
  );
}

class _PetRegistrationSheet extends StatefulWidget {
  final String? reason;

  const _PetRegistrationSheet({this.reason});

  @override
  State<_PetRegistrationSheet> createState() => _PetRegistrationSheetState();
}

class _PetRegistrationSheetState extends State<_PetRegistrationSheet> {
  final _name = TextEditingController();
  final _breed = TextEditingController();

  PetSpecies _species = PetSpecies.dog;
  DogSize _size = DogSize.small;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '이름을 입력해 주세요.');
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final saved = await PetSync().register(
        name: name,
        species: _species,
        size: _size,
        breed: _breed.text.trim(),
      );
      notifyPetsChanged();
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on WalkFailure catch (e) {
      // 실패를 삼키지 않는다. 사용자는 왜 안 됐는지 알아야 다시 시도할지 정한다.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '등록하지 못했어요 · 잠시 후 다시 시도해 주세요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          18 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '우리 아이를 등록해 주세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: T.textPrimary,
              ),
            ),
            if (widget.reason != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.reason!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: T.textSecondary),
              ),
            ],
            const SizedBox(height: 18),

            _label('이름'),
            TextField(
              controller: _name,
              maxLength: 50,
              autofocus: true,
              decoration: _decoration('예) 보리'),
            ),
            const SizedBox(height: 8),

            _label('종'),
            _chips<PetSpecies>(
              values: PetSpecies.values,
              selected: _species,
              labelOf: (v) => v.label,
              onTap: (v) => setState(() => _species = v),
            ),
            const SizedBox(height: 14),

            _label('몸집'),
            _chips<DogSize>(
              values: DogSize.values,
              selected: _size,
              labelOf: (v) => v.label,
              onTap: (v) => setState(() => _size = v),
            ),
            const SizedBox(height: 14),

            _label('품종 (선택)'),
            TextField(
              controller: _breed,
              maxLength: 50,
              decoration: _decoration('모르면 비워 두세요'),
            ),

            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFD9534F)),
              ),
            ],

            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Text(_saving ? '등록하는 중…' : '등록하기'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('나중에', style: TextStyle(color: T.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: T.textSecondary,
          ),
        ),
      );

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        counterText: '',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
      );

  Widget _chips<T2>({
    required List<T2> values,
    required T2 selected,
    required String Function(T2) labelOf,
    required void Function(T2) onTap,
  }) =>
      Row(
        children: [
          for (final v in values) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(v),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == selected
                        ? const Color(0x1AFF7E8A)
                        : const Color(0x0A463C64),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: v == selected
                          ? const Color(0xFFFF8F63)
                          : Colors.transparent,
                      width: 1.4,
                    ),
                  ),
                  child: Text(
                    labelOf(v),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          v == selected ? FontWeight.w800 : FontWeight.w600,
                      color: v == selected
                          ? const Color(0xFFE07A4E)
                          : T.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            if (v != values.last) const SizedBox(width: 8),
          ],
        ],
      );
}
