// lib/v2/widgets/walk_dog_picker.dart
//
// "누구랑 나가요?" — 이슈 #343.
//
// ## 한 마리면 안 묻는다
//
// 대부분의 사용자는 한 마리다. 그 사람에게 매번 시트를 한 장 더 띄우면 산책 시작이
// 두 번 누르는 일이 된다. **두 마리 이상일 때만** 뜬다 — [WalkDogPicker.needed] 가 그
// 판단 한 곳이다.
//
// ## 기본은 전부 고름
//
// 두 마리를 키우는 사람은 대개 둘을 함께 데리고 나간다. 아무것도 안 고른 채로 열면
// 매번 체크를 하게 되고, 그러면 시트가 방해가 된다.
//
// ## 서버에 없는 아이는 목록에 없다
//
// `serverId` 가 없는 프로필은 아직 서버에 안 올라간 것이라 산책을 그 아이에게 달 수
// 없다(`POST /api/walks` 의 `dogIds` 는 서버 id 다). 목록에 넣어 놓고 조용히 빼면
// 사용자는 두 마리를 골랐는데 한 마리만 남은 것을 모른다.
import 'package:flutter/material.dart';

import '../domain/pet.dart';
import '../theme/app_tokens.dart';

class WalkDogPicker extends StatefulWidget {
  /// 고를 수 있는 아이들. **서버 id 가 있는 것만** 온다.
  final List<DogProfile> pets;

  const WalkDogPicker({super.key, required this.pets});

  /// 물어봐야 하는가. 서버에 올라간 아이가 둘 이상일 때만이다.
  static bool needed(List<DogProfile> pets) => _sendable(pets).length >= 2;

  static List<DogProfile> _sendable(List<DogProfile> pets) =>
      pets.where((p) => p.serverId != null).toList();

  /// 시트를 띄우고 고른 아이들의 **서버 id** 를 준다.
  ///
  /// 사용자가 닫으면 `null` 이다 — 빈 목록과 다르다. 빈 목록은 "아무도 안 골랐다" 이고
  /// 그건 [WalkDogPicker] 가 만들지 않는다(시작 버튼이 잠긴다).
  static Future<List<int>?> ask(BuildContext context, List<DogProfile> pets) {
    final sendable = _sendable(pets);
    return showModalBottomSheet<List<int>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => WalkDogPicker(pets: sendable),
    );
  }

  @override
  State<WalkDogPicker> createState() => _WalkDogPickerState();
}

class _WalkDogPickerState extends State<WalkDogPicker> {
  late final Set<int> _picked = {
    for (final p in widget.pets)
      if (p.serverId != null) p.serverId!,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: T.surfaceBright,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0x22463C64),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text('누구랑 나가요?',
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 6),
          const Text('함께 나간 아이들 모두에게 이 산책이 기록돼요',
              style: TextStyle(fontSize: 13, color: T.textMuted)),
          const SizedBox(height: 14),
          // 아이가 많아도 시트가 화면을 넘지 않는다 — 목록만 스크롤한다.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [for (final pet in widget.pets) _row(pet)],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              // 아무도 안 고르면 시작할 수 없다. 그 산책은 누구 것도 아니다.
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.pop(context, _picked.toList()),
              style: FilledButton.styleFrom(
                backgroundColor: T.warmText,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: Text(
                _picked.isEmpty ? '한 마리는 골라 주세요' : '${_picked.length}마리와 시작하기',
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(DogProfile pet) {
    final id = pet.serverId!;
    final on = _picked.contains(id);
    return InkWell(
      onTap: () => setState(() => on ? _picked.remove(id) : _picked.add(id)),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(children: [
          Image.asset(pet.avatarAsset, width: 34, height: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pet.name,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
              Text(pet.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: T.textMuted)),
            ]),
          ),
          Icon(
            on ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 24,
            color: on ? T.warmText : const Color(0x33463C64),
          ),
        ]),
      ),
    );
  }
}
