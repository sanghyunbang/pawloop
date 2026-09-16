// lib/v2/widgets/pet_character_picker.dart
//
// 사진이 없을 때의 얼굴 고르기 줄 — 이슈 #585.
//
// ## 왜 한 곳인가
//
// 고르는 자리가 둘이다 — 등록 시트와 편집 화면. 둘이 각자 그리면 목록이 갈라지고, 새 얼굴을
// 더한 날 한쪽에만 나온다. 케어 항목의 그림 고르기(`care_items_screen.dart`)와 같은 판단이다.
//
// ## 맨 앞은 "기본" 이다
//
// 고른 얼굴을 **도로 물릴 수 있어야** 한다 — 서버의 부분 수정이 `null` 로 그것을 받는다
// (#586). 지우기 버튼을 따로 두는 대신 줄의 맨 앞에 "기본" 칸을 둔다: 거기에는 그 아이의
// **종류 기본 그림**이 뜨므로, 고르기 전으로 돌아간 화면이 미리 보인다.
//
// ## 고른 칸이 화면 밖이면 아무것도 안 고른 것처럼 보인다
//
// 열넷은 한 화면에 안 들어간다(390dp 에 여섯). 고슴도치를 고른 아이의 편집 화면을 열면 왼쪽
// 여섯 칸이 전부 흐리게 보인다 — 케어 항목에서 에뮬레이터로 찾은 것과 같은 실패다(#560).
// 첫 그림 뒤에 **안 보일 때만** 굴린다: 이미 보이는 것을 굴리면 맨 앞의 "기본" 칸이 밀려난다.
library;

import 'package:flutter/material.dart';

import '../domain/pet.dart';
import '../domain/pet_characters.dart';
import '../theme/app_tokens.dart';

class PetCharacterPicker extends StatefulWidget {
  /// 고른 열쇠말. **`null` 은 "안 골랐다"** — 맨 앞 "기본" 칸이 켜진다.
  final String? selected;

  /// "기본" 칸에 그릴 그림을 정한다 — 그 아이의 종류다.
  final PetSpecies species;

  /// 고른 값. "기본" 을 누르면 `null` 이 온다.
  final ValueChanged<String?> onPick;

  const PetCharacterPicker({
    super.key,
    required this.selected,
    required this.species,
    required this.onPick,
  });

  @override
  State<PetCharacterPicker> createState() => _PetCharacterPickerState();
}

class _PetCharacterPickerState extends State<PetCharacterPicker> {
  final ScrollController _row = ScrollController();

  /// 칸 하나의 폭 + 사이 간격. 자리를 셈으로 찾는 데 쓴다.
  static const double _stride = _cell + 8;
  static const double _cell = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  /// 고른 칸을 **보이게** 한다 — 굴리는 것이 목적이 아니다.
  ///
  /// 처음엔 고른 자리로 무조건 굴렸는데, 앞쪽 얼굴(푸들은 셋째)을 고른 화면에서 맨 앞의
  /// **"기본" 칸이 왼쪽 밖으로 밀려났다.** 고른 얼굴을 도로 물릴 길이 그 칸뿐이라, 이미
  /// 보이는 것을 보이게 하려고 되돌리기를 숨긴 셈이다.
  void _scrollToSelected() {
    if (!mounted || !_row.hasClients) return;
    final key = widget.selected;
    if (key == null) return; // "기본" 은 맨 앞이라 굴릴 것이 없다
    final index = kPetCharacterKeys.indexOf(key);
    if (index < 0) return;

    // 맨 앞의 "기본" 칸 때문에 한 칸 밀린다.
    final position = _row.position;
    final left = (index + 1) * _stride;
    final visible = left >= position.pixels &&
        left + _cell <= position.pixels + position.viewportDimension;
    if (visible) return;

    // 왼쪽 끝에 딱 붙이지 않고 한 칸을 남겨, 앞에도 더 있다는 것이 보이게 한다.
    _row.jumpTo((left - _stride).clamp(0, position.maxScrollExtent));
  }

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        key: const Key('pet-character-row'),
        controller: _row,
        scrollDirection: Axis.horizontal,
        itemCount: kPetCharacterKeys.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => i == 0
            ? _chip(
                key: 'pet-character-default',
                asset: petSpeciesAsset(widget.species),
                label: '기본',
                chosen: widget.selected == null,
                onTap: () => widget.onPick(null),
              )
            : _keyChip(kPetCharacterKeys[i - 1]),
      ),
    );
  }

  Widget _keyChip(String key) => _chip(
        key: 'pet-character-$key',
        // 목록에서 온 열쇠말이라 여기서는 `null` 이 안 나온다. 그래도 `!` 를 안 쓰는 것은,
        // 목록과 파일이 어긋난 날 화면이 죽는 대신 발바닥으로 서게 하려는 것이다.
        asset: petCharacterAsset(key) ?? 'assets/emoji/paw.png',
        label: petCharacterLabel(key),
        chosen: widget.selected == key,
        onTap: () => widget.onPick(key),
      );

  Widget _chip({
    required String key,
    required String asset,
    required String label,
    required bool chosen,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: Key(key),
      onTap: onTap,
      child: Container(
        width: _cell,
        decoration: BoxDecoration(
          color: chosen ? T.accentSoft : T.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: chosen ? T.accent : T.cardBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(asset, width: 30, height: 30, gaplessPlayback: true),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
                color: chosen ? T.accent : T.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
