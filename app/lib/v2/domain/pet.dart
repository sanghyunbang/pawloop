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

/// 지도 카테고리. KTO(관광공사) 반려동반은 contenttypeid(숫자 key),
/// 병원/펫샵/산책로는 별도 공공데이터 레이어(문자 key — 현재 더미).
const List<PetCategory> kPetCategories = [
  PetCategory('12', '여행지', Color(0xFF57C98A), Icons.park_rounded),
  PetCategory('39', '카페·식당', Color(0xFFFF7E6B), Icons.restaurant_rounded),
  PetCategory('28', '레포츠', Color(0xFF33BFA6), Icons.directions_walk_rounded),
  PetCategory('32', '숙박', Color(0xFF5B8DEF), Icons.hotel_rounded),
  PetCategory('38', '쇼핑', Color(0xFF9B7BFF), Icons.storefront_rounded),
  PetCategory('14', '문화', Color(0xFFEFA13C), Icons.museum_rounded),
  PetCategory('vet', '병원', Color(0xFF4C9AFF), Icons.local_hospital_rounded),
  PetCategory('shop', '펫샵', Color(0xFFB07BFF), Icons.pets_rounded),
  PetCategory('trail', '산책로', Color(0xFF2FB89B), Icons.route_rounded),
];

/// KTO 외 별도 레이어(공공데이터 예정) key.
const Set<String> kLayerKeys = {'vet', 'shop', 'trail'};

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

/// 반려동물 종류. (다견·다묘 가정 지원)
enum PetSpecies {
  dog('강아지'),
  cat('고양이'),
  other('기타');

  final String label;
  const PetSpecies(this.label);
}

/// 우리 아이 프로필. (강아지/고양이 등 여러 마리 지원)
class DogProfile {
  final String name;
  final String breed;
  final PetSpecies species;
  final DogSize size;
  final int ageMonths;
  final bool neutered;

  const DogProfile({
    required this.name,
    required this.breed,
    this.species = PetSpecies.dog,
    required this.size,
    required this.ageMonths,
    this.neutered = false,
  });

  String get ageLabel => ageMonths >= 12 ? '${ageMonths ~/ 12}살' : '${ageMonths}개월';

  /// 종류별 아바타(Fluent Emoji).
  String get avatarAsset => switch (species) {
        PetSpecies.dog => 'assets/emoji/dog.png',
        PetSpecies.cat => 'assets/emoji/cat.png',
        PetSpecies.other => 'assets/emoji/paw.png',
      };

  DogProfile copyWith({String? name, String? breed, PetSpecies? species, DogSize? size, int? ageMonths, bool? neutered}) =>
      DogProfile(
        name: name ?? this.name,
        breed: breed ?? this.breed,
        species: species ?? this.species,
        size: size ?? this.size,
        ageMonths: ageMonths ?? this.ageMonths,
        neutered: neutered ?? this.neutered,
      );
}

/// 우리 아이들(전역, 여러 마리). 추후 백엔드 dog 테이블과 연결.
final ValueNotifier<List<DogProfile>> kMyPets = ValueNotifier<List<DogProfile>>([
  const DogProfile(name: '보리', breed: '믹스견', species: PetSpecies.dog, size: DogSize.small, ageMonths: 30, neutered: true),
  const DogProfile(name: '치즈', breed: '코리안숏헤어', species: PetSpecies.cat, size: DogSize.small, ageMonths: 22),
]);

/// 현재 선택된 아이 인덱스.
final ValueNotifier<int> kSelectedPetIdx = ValueNotifier<int>(0);

/// 현재 선택된 아이(전역) — 홈 히어로/프로필이 구독.
final ValueNotifier<DogProfile> kMyDog = ValueNotifier<DogProfile>(kMyPets.value.first);

/// 아이 선택.
void selectPet(int i) {
  if (i < 0 || i >= kMyPets.value.length) return;
  kSelectedPetIdx.value = i;
  kMyDog.value = kMyPets.value[i];
}

/// 선택된 아이 프로필 갱신(편집 저장).
void updateSelectedPet(DogProfile p) {
  final list = [...kMyPets.value];
  list[kSelectedPetIdx.value] = p;
  kMyPets.value = list;
  kMyDog.value = p;
}

/// 새 아이 추가 후 선택.
void addPet(DogProfile p) {
  kMyPets.value = [...kMyPets.value, p];
  selectPet(kMyPets.value.length - 1);
}

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

// ─────────────────────── 가족 케어 (물·밥·산책 공유) ───────────────────────

/// 케어 항목 종류. (가족이 자유롭게 항목 추가 가능)
enum CareType {
  water('물'),
  meal('밥'),
  walk('산책'),
  med('투약'),
  snack('간식'),
  etc('기타');

  final String label;
  const CareType(this.label);
}

IconData careIcon(CareType t) => switch (t) {
      CareType.water => Icons.water_drop_rounded,
      CareType.meal => Icons.restaurant_rounded,
      CareType.walk => Icons.pets_rounded,
      CareType.med => Icons.medication_rounded,
      CareType.snack => Icons.cookie_rounded,
      CareType.etc => Icons.favorite_rounded,
    };

Color careColor(CareType t) => switch (t) {
      CareType.water => const Color(0xFF5B8DEF),
      CareType.meal => const Color(0xFFFF8F63),
      CareType.walk => const Color(0xFF57C98A),
      CareType.med => const Color(0xFF9B7BFF),
      CareType.snack => const Color(0xFFEFA13C),
      CareType.etc => const Color(0xFFFF7E8A),
    };

/// 케어 목록 변경 알림(추가/삭제/토글) — 홈 카드 등 다른 화면 동기화용.
final ValueNotifier<int> kCareRev = ValueNotifier<int>(0);

/// 오늘의 케어 1건(가족 공유). 백엔드(care_log) 연동 전 로컬 상태.
/// [product]는 밥/간식 등에서 선택 입력하는 제품명(사료명) — 추후 소진 예측·제휴 추천의 재료.
class CareTask {
  final CareType type;
  final String label;
  bool done;
  String? by; // 완료한 가족
  String? time; // '08:30'
  String? product; // 제품명(선택) 예: '로얄캐닌 미니 어덜트'
  CareTask({required this.type, required this.label, this.done = false, this.by, this.time, this.product});
}

/// 오늘의 케어 목록(샘플).
final List<CareTask> kCareToday = [
  CareTask(type: CareType.water, label: '물 갈아주기', done: true, by: '엄마', time: '08:10'),
  CareTask(type: CareType.meal, label: '아침 밥', done: true, by: '나', time: '08:32', product: '로얄캐닌 미니 어덜트'),
  CareTask(type: CareType.walk, label: '저녁 산책', done: false),
];

/// 가족 구성원. [todayKm] = 오늘 걸은 거리(구성원이 공유에 동의한 경우만 서버가 제공 — 현재 더미).
class FamilyMember {
  final String name;
  final String role;
  final Color color;
  final double todayKm;
  const FamilyMember(this.name, this.role, this.color, {this.todayKm = 0});
}

const List<FamilyMember> kFamilyMembers = [
  FamilyMember('나', '보호자', Color(0xFFFF8F63), todayKm: 2.4),
  FamilyMember('엄마', '가족', Color(0xFF57C98A), todayKm: 1.1),
  FamilyMember('아빠', '가족', Color(0xFF5B8DEF), todayKm: 0),
];

/// 내 산책 거리 가족 공유 동의(위치정보법상 '개인위치정보 제3자 제공' 동의) 상태.
/// 켤 때 반드시 동의 시트를 거치고, 제공 시마다 알림 통지(법 제19조) — 푸시는 백엔드 연동 시.
final ValueNotifier<bool> kShareMyDistance = ValueNotifier<bool>(false);

/// 가족 초대 코드(더미 — 백엔드 그룹 연동 전).
const String kFamilyInviteCode = 'PAW-2481';

/// 산책 시 주의사항(가족 공유 메모). 가족 누구나 추가/삭제 가능.
final List<String> kWalkNotes = [
  '오른쪽 뒷다리 슬개골 — 계단·점프 피하기',
  '대형견 만나면 예민해요. 리드줄 짧게 잡기',
  '산책 후 발 닦고 물 충분히 주기',
];

/// 가족 채팅 메시지.
class ChatMessage {
  final String sender;
  final String text;
  final String time;
  final bool mine;
  const ChatMessage(this.sender, this.text, this.time, {this.mine = false});
}

final List<ChatMessage> kChatMessages = [
  const ChatMessage('엄마', '보리 아침에 물 갈아줬어~', '08:11'),
  const ChatMessage('나', '아침 밥도 줬어요! 사료 거의 다 떨어져가요', '08:33', mine: true),
  const ChatMessage('아빠', '퇴근길에 사료 사갈게', '09:02'),
  const ChatMessage('엄마', '저녁 산책 누가 갈 수 있어? 나 오늘 늦어', '15:40'),
  const ChatMessage('나', '제가 갈게요. 요즘 보리 슬개골 조심해야 하니까 공원 평지로만 돌게요', '15:52', mine: true),
];

/// 산책 크루(동호회) 방 메시지 — 방별 메시지 분리(더미).
final List<ChatMessage> kCrewChatMessages = [
  const ChatMessage('초코맘', '오늘 서울숲 사람 많던데 다들 산책 어떠셨어요?', '18:20'),
  const ChatMessage('워킹독', '저녁엔 한산했어요! 잔디마당 쪽 추천', '19:05'),
  const ChatMessage('나', '보리는 오늘 슬개골 때문에 평지만 돌았어요 🐾', '19:12', mine: true),
  const ChatMessage('몽이누나', '아이고 얼른 나아야 할 텐데… 몸조리 잘해요', '19:30'),
  const ChatMessage('초코맘', '내일 아침 7시 반 서울숲 정문 어때요?', '어제'),
];

/// 채팅방. '우리 가족'이 기본방(대부분 가족과 함께 키우므로),
/// 이후 친구·동호회(커뮤니티에서 만난 사람들) 방으로 확장.
class ChatRoom {
  final String name;
  final String tag; // '가족' | '산책 크루' 등
  final Color color;
  final IconData icon;
  final List<ChatMessage> messages; // 방별 메시지
  final int unread;
  final int memberCount;
  final bool isDefault; // 기본방(우리 가족)
  const ChatRoom({
    required this.name,
    required this.tag,
    required this.color,
    required this.icon,
    required this.messages,
    this.unread = 0,
    required this.memberCount,
    this.isDefault = false,
  });

  String get lastMessage => messages.isEmpty ? '' : messages.last.text;
  String get lastTime => messages.isEmpty ? '' : messages.last.time;
}

final List<ChatRoom> kChatRooms = [
  ChatRoom(
    name: '우리 가족',
    tag: '가족',
    color: const Color(0xFFFF8F63),
    icon: Icons.diversity_1_rounded,
    messages: kChatMessages,
    unread: 2,
    memberCount: kFamilyMembers.length,
    isDefault: true,
  ),
  ChatRoom(
    name: '서울숲 산책 크루',
    tag: '산책 크루',
    color: const Color(0xFF33BFA6),
    icon: Icons.directions_walk_rounded,
    messages: kCrewChatMessages,
    memberCount: 6,
  ),
];

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
