import 'package:flutter/material.dart';

/// 반려(강아지) 도메인 모델. 감정 도메인을 대체한다.
///
/// 지도/커뮤니티/필터에서 공유하는 장소 카테고리 SSOT.
/// - 동반가능 장소(카페·식당·공원)는 관광공사 반려동물 동반여행 API,
/// - 병원·펫샵은 공공데이터(인허가), 산책로는 두루누비(걷기여행길)로 채운다.
class PetCategory {
  final String key;
  final String label;
  final Color color;
  final IconData icon;
  const PetCategory(this.key, this.label, this.color, this.icon);
}

/// 관광공사 반려동물 동반여행(KTO) contenttypeid 기반 카테고리. key = contenttypeid.
const List<PetCategory> kPetCategories = [
  PetCategory('12', '여행지', Color(0xFF57C98A), Icons.park_rounded),
  PetCategory('39', '카페·식당', Color(0xFFFF7E6B), Icons.restaurant_rounded),
  PetCategory('28', '레포츠', Color(0xFF33BFA6), Icons.directions_walk_rounded),
  PetCategory('32', '숙박', Color(0xFF5B8DEF), Icons.hotel_rounded),
  PetCategory('38', '쇼핑', Color(0xFF9B7BFF), Icons.storefront_rounded),
  PetCategory('14', '문화', Color(0xFFEFA13C), Icons.museum_rounded),
];

/// contenttypeid → 카테고리. 미지정/기타는 여행지로.
PetCategory petCatByType(String? contentTypeId) => kPetCategories.firstWhere(
      (c) => c.key == contentTypeId,
      orElse: () => const PetCategory('0', '기타', Color(0xFF8E86A8), Icons.place_rounded),
    );

/// 견종 크기.
enum DogSize {
  small('소형견'),
  medium('중형견'),
  large('대형견');

  final String label;
  const DogSize(this.label);
}

/// 우리 아이 프로필.
class DogProfile {
  final String name;
  final String breed;
  final DogSize size;
  final int ageMonths;
  final bool neutered;
  final String avatarAsset;

  const DogProfile({
    required this.name,
    required this.breed,
    required this.size,
    required this.ageMonths,
    this.neutered = false,
    this.avatarAsset = 'assets/emoji/dog.png',
  });

  String get ageLabel => ageMonths >= 12 ? '${ageMonths ~/ 12}살' : '${ageMonths}개월';

  DogProfile copyWith({String? name, String? breed, DogSize? size, int? ageMonths, bool? neutered}) =>
      DogProfile(
        name: name ?? this.name,
        breed: breed ?? this.breed,
        size: size ?? this.size,
        ageMonths: ageMonths ?? this.ageMonths,
        neutered: neutered ?? this.neutered,
        avatarAsset: avatarAsset,
      );
}

/// 현재 반려견(전역). 추후 백엔드/프로필 편집과 연결.
final ValueNotifier<DogProfile> kMyDog = ValueNotifier<DogProfile>(
  const DogProfile(name: '보리', breed: '믹스견', size: DogSize.small, ageMonths: 30, neutered: true),
);

/// 오늘 산책 요약(0부터 시작 — 실제 기록 연동 전). 거리 km, 횟수.
class WalkToday {
  final int count;
  final double km;
  final int minutes;
  const WalkToday({this.count = 0, this.km = 0, this.minutes = 0});
}
