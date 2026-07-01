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

// ─────────────────────── 산책 기록 ───────────────────────

/// 산책 로그 1건. (추후 GPS 경로/사진 연동)
class WalkLog {
  final String date; // 표시용 '6월 30일 (월)'
  final String place;
  final double km;
  final int minutes;
  final String memo;
  const WalkLog({
    required this.date,
    required this.place,
    required this.km,
    required this.minutes,
    this.memo = '',
  });

  String get pace => minutes == 0 ? '-' : '${(minutes / (km == 0 ? 1 : km)).round()}분/km';
}

/// 샘플 산책 기록.
const List<WalkLog> kWalks = [
  WalkLog(date: '6월 30일 (월)', place: '서울숲', km: 2.4, minutes: 38, memo: '아침 공기가 좋아 한 바퀴 더 돌았다. 보리도 신났음.'),
  WalkLog(date: '6월 28일 (토)', place: '남산 둘레길', km: 3.1, minutes: 52, memo: '사람이 많아 리드줄은 짧게. 그래도 잘 걸었다.'),
  WalkLog(date: '6월 27일 (금)', place: '한강공원(뚝섬)', km: 1.8, minutes: 29, memo: '저녁 산책. 물냄새 맡느라 바빴다.'),
  WalkLog(date: '6월 25일 (수)', place: '동네 한 바퀴', km: 1.2, minutes: 20, memo: ''),
  WalkLog(date: '6월 24일 (화)', place: '올림픽공원', km: 2.9, minutes: 46, memo: '잔디밭에서 한참 뛰어놀았다.'),
];

/// 주간 산책 거리(월~일, km). 통계 차트용.
const List<double> kWeekKm = [2.1, 2.9, 1.2, 0, 1.8, 3.1, 2.4];
const List<String> kWeekDayLabels = ['월', '화', '수', '목', '금', '토', '일'];
const int kWalkTodayIdx = 6; // 오늘 = 일

// ─────────────────────── 반려 커뮤니티 ───────────────────────

/// 커뮤니티 카테고리.
const List<String> kPetBoards = ['전체', '산책로 후기', '동반장소', '건강·병원', '자유', '자랑'];

/// 반응 3종.
const List<String> kPetReactions = ['도움돼요', '귀여워요', '공감'];

/// 커뮤니티 글 1건.
class PetPost {
  final String nick;
  final String board;
  final String? loc;
  final String date;
  final String title;
  final String body;
  final int commentCount;
  final List<int> reactions; // kPetReactions와 동일 순서
  const PetPost({
    required this.nick,
    required this.board,
    this.loc,
    required this.date,
    required this.title,
    required this.body,
    this.commentCount = 0,
    this.reactions = const [0, 0, 0],
  });
}

const List<PetPost> kPetPosts = [
  PetPost(
    nick: '보리아빠', board: '산책로 후기', loc: '서울숲', date: '2026.06.30',
    title: '서울숲 아침 산책 코스 추천',
    body: '이른 아침엔 사람이 적어서 대형견도 편해요. 잔디마당 쪽은 목줄 필수! 배변봉투통도 곳곳에 있어서 편했습니다.',
    commentCount: 4, reactions: [7, 3, 2],
  ),
  PetPost(
    nick: '초코맘', board: '동반장소', loc: '성수동', date: '2026.06.29',
    title: '성수동 반려동반 카페 다녀왔어요',
    body: '실내 동반 가능하고 물그릇도 챙겨주세요. 소형견 위주지만 얌전하면 중형견도 괜찮대요. 사진 명당 많음 🐶',
    commentCount: 6, reactions: [5, 8, 1],
  ),
  PetPost(
    nick: '몽이누나', board: '건강·병원', loc: null, date: '2026.06.29',
    title: '슬개골 탈구, 어느 동물병원 다니세요?',
    body: '작은 아이라 슬개골이 걱정이에요. 강남 쪽에 정형외과 잘 보는 병원 추천 받습니다. 수술까진 아니고 관리 상담이요.',
    commentCount: 9, reactions: [11, 0, 4],
  ),
  PetPost(
    nick: '워킹독', board: '자랑', loc: '올림픽공원', date: '2026.06.28',
    title: '오늘 3km 완주한 우리 아이 🐾',
    body: '평소 1km도 힘들어했는데 오늘은 신나서 3km를 걸었어요. 날이 선선해서 그런가 봐요. 다들 무더위 조심하세요!',
    commentCount: 3, reactions: [4, 12, 5],
  ),
];
