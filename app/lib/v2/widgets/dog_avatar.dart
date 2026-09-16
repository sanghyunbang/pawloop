// 아이 아바타 — **사진 → 고른 얼굴 → 종류 기본 그림** 순서다 (이슈 #448 · #585).
//
// 홈 히어로 · 내 정보 · 아이 고르기 · 편집 화면이 전부 이 하나를 쓴다. 자리마다 원의 크기와 이모지의
// 크기가 다르므로 둘을 따로 받는다 — 사진은 원을 꽉 채우고(`ClipOval`, cover), 이모지는 가운데 작게.
// 사진을 못 불러오면 이모지로 돌아간다 — 깨진 그림 아이콘을 홈 한가운데에 띄우지 않는다.
//
// 뒤의 둘은 [DogProfile.avatarAsset] 이 이미 가른다. 여기서 가르는 것은 사진 하나뿐인데, 사진만
// URL 이라 그리는 방법이 아예 다르기 때문이다(`Image.network` · 원형 자르기).
import 'package:flutter/material.dart';

import '../domain/pet.dart';

class DogAvatar extends StatelessWidget {
  final DogProfile? dog;

  /// 사진이 채울 원의 지름.
  final double size;

  /// 사진이 없을 때 그리는 이모지의 한 변.
  final double emojiSize;

  const DogAvatar({super.key, required this.dog, required this.size, required this.emojiSize});

  @override
  Widget build(BuildContext context) {
    final url = dog?.photoUrl;
    final emoji = Image.asset(
      dog?.avatarAsset ?? 'assets/emoji/paw.png',
      width: emojiSize,
      height: emojiSize,
      gaplessPlayback: true,
    );
    if (url == null) return emoji;
    return ClipOval(
      key: const Key('dog-photo'),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Center(child: emoji),
        ),
      ),
    );
  }
}
