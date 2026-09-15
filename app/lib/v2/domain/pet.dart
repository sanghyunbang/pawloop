import 'package:flutter/material.dart';

/// 반려(강아지) 도메인 모델. 감정 도메인을 대체한다.
///
/// 지도/커뮤니티/필터에서 공유하는 장소 카테고리 SSOT.
/// - 동반가능 장소(카페·식당·공원)는 관광공사 반려동물 동반여행 API 로 채운다.
/// - 병원·펫샵·산책로는 #282 에서 가짜와 함께 내렸다가 #291 에서 **실데이터로** 돌아왔다 —
///   행정안전부 인허가(전국)와 두루누비 걷기여행길이다. 서버가 카탈로그 한 벌에 이어 붙여
///   준다(`source`=`vet`·`shop`·`trail`). 계약의 `PlaceCategory` 와 같은 키다.
class PetCategory {
  final String key;
  final String label;
  final Color color;
  final IconData icon;
  const PetCategory(this.key, this.label, this.color, this.icon);
}

/// 지도 카테고리. 숫자 key 는 KTO(관광공사) 반려동반의 contenttypeid, 문자 key 는
/// 공공데이터 레이어(`kLayerKeys`)다 — 계약의 `PlaceCategory` 와 같은 아홉이다.
const List<PetCategory> kPetCategories = [
  PetCategory('12', '여행지', Color(0xFF3DBE6C), Icons.park_rounded),
  PetCategory('39', '카페·식당', Color(0xFFFF6B6B), Icons.restaurant_rounded),
  PetCategory('28', '레포츠', Color(0xFFF5A623), Icons.directions_walk_rounded),
  PetCategory('32', '숙박', Color(0xFF3B82F6), Icons.hotel_rounded),
  PetCategory('38', '쇼핑', Color(0xFF8B5CF6), Icons.storefront_rounded),
  PetCategory('14', '문화', Color(0xFF9C6644), Icons.museum_rounded),
  // 공공데이터 레이어 (#291). 색은 design-system.md 의 카테고리 팔레트다.
  // 아홉 색은 서로 RGB 거리 80 이상이어야 한다(`pet_category_colors_test`, #328) — 예전엔
  // 여행지·레포츠·산책로가 모두 초록, 쇼핑·펫샵이 모두 보라라 핀을 가를 수 없었다.
  PetCategory('vet', '동물병원', Color(0xFFD7263D), Icons.local_hospital_rounded),
  PetCategory('shop', '펫샵', Color(0xFFD946EF), Icons.shopping_bag_rounded),
  PetCategory('trail', '산책로', Color(0xFF0B7A75), Icons.route_rounded),
  // 반려견 놀이터 (#346). 목줄을 풀 수 있는 울타리 안이라 아이콘이 울타리다.
  // 라임은 아홉 색 중 가장 가까운 여행지(#3DBE6C)와도 RGB 거리 128 이다.
  PetCategory('playground', '놀이터', Color(0xFF80D000), Icons.fence_rounded),
];

/// KTO 가 아닌 출처의 키 — 서버의 `PlaceDto.LAYER_SOURCES` 와 같은 셋.
const Set<String> kLayerKeys = {'vet', 'shop', 'trail', 'playground'};

/// 산책로 칩이 반경 밖까지 훑을 때 주는 코스 수 — 2026-09-06 결정(#291), #346 에서 좁혔다.
///
/// **예전에는 반경을 아예 안 봤다.** 코리아둘레길(해파랑·남파랑·서해랑·DMZ)은 해안·접경에만
/// 있어 도심에서 8km 안이 늘 비었기 때문이다 — 서울숲에서 가장 가까운 코스가 19.7km 밖
/// DMZ 18km 코스였다(#328).
///
/// #346 이 동네 길 1,302개를 넣으면서 그 전제가 사라졌다. 이제 도심에서는 8km 안이 찬다.
/// 그래서 **다른 칩과 같이 반경을 먼저 본다.** 반경 안이 비었을 때만 이만큼을 가까운 순으로
/// 주고, 화면이 "8km 안에는 없어서" 라고 말한다 — 40km 밖 코스를 "가까운 산책로" 라고
/// 부르지 않는다.
///
/// 서버의 `PlaceQueryService.TRAIL_NEAREST_LIMIT` 과 같은 수다 — 기기 안 계산(A안)과
/// 서버 계산(B안)이 같은 답을 내야 한다.
const int kTrailNearestLimit = 20;

/// 카테고리 키(`PetPlace.categoryKey`) → 카테고리. 미지정/기타는 "기타" 로.
PetCategory petCatByType(String? contentTypeId) => kPetCategories.firstWhere(
  (c) => c.key == contentTypeId,
  orElse: () =>
      const PetCategory('0', '기타', Color(0xFF8E86A8), Icons.place_rounded),
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
  /// 서버의 `dog.id`. **아직 서버에 없으면 `null`** 이다.
  ///
  /// 산책을 저장하려면 이 값이 필요하다 — 계약의 `WalkInput.dogId` 가 필수다.
  /// 이 값이 `null` 인 프로필로는 산책을 올릴 수 없고, 그래서 등록 시트가 뜬다.
  final int? serverId;

  final String name;
  final String breed;
  final PetSpecies species;
  final DogSize size;
  final int ageMonths;
  final bool neutered;

  /// 프로필 사진의 공개 URL (#448). 없으면 `null` — 화면은 [avatarAsset] 의 종 이모지로 돌아간다.
  final String? photoUrl;

  const DogProfile({
    this.serverId,
    required this.name,
    required this.breed,
    this.species = PetSpecies.dog,
    required this.size,
    required this.ageMonths,
    this.neutered = false,
    this.photoUrl,
  });

  String get ageLabel =>
      ageMonths >= 12 ? '${ageMonths ~/ 12}살' : '$ageMonths개월';

  /// 화면 부제 — "고양이 · 코숏 · 3살 · 소형견".
  ///
  /// **모르는 것은 안 그린다.** 품종을 안 받았으면 구분점만 남아 "고양이 · · 0개월" 이
  /// 되고, 나이를 모르는데 `ageMonths` 가 0 이면 **"0개월"** 이 되어 갓 태어났다고 말한다.
  /// **앱의 등록 시트가** 아직 생일을 안 받으므로(#159 범위 밖) 지금은 나이가 항상 모르는
  /// 값이다. 서버와 계약은 `birth` 를 받고 `ageMonths` 를 파생한다 — 생일 입력을 붙이려는
  /// 사람이 서버부터 고치러 가지 않도록 적어 둔다.
  String get subtitle => [
        species.label,
        if (breed.isNotEmpty) breed,
        if (ageMonths > 0) ageLabel,
        size.label,
      ].join(' · ');

  /// 종류별 아바타(Fluent Emoji).
  String get avatarAsset => switch (species) {
    PetSpecies.dog => 'assets/emoji/dog.png',
    PetSpecies.cat => 'assets/emoji/cat.png',
    PetSpecies.other => 'assets/emoji/paw.png',
  };

  DogProfile copyWith({
    int? serverId,
    String? name,
    String? breed,
    PetSpecies? species,
    DogSize? size,
    int? ageMonths,
    bool? neutered,
    String? photoUrl,
    bool clearPhoto = false,
  }) => DogProfile(
    serverId: serverId ?? this.serverId,
    name: name ?? this.name,
    breed: breed ?? this.breed,
    species: species ?? this.species,
    size: size ?? this.size,
    ageMonths: ageMonths ?? this.ageMonths,
    neutered: neutered ?? this.neutered,
    photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
  );
}

/// 우리 아이들(전역, 여러 마리). 서버의 `GET /api/dogs` 가 채운다 — `data/pet_sync.dart`.
///
/// **빈 목록으로 시작한다.** 예전에는 '보리'·'치즈' 두 마리가 하드코딩돼 있었는데,
/// 그 상태에서는 서버에 0마리인 사용자에게도 화면이 "우리 아이 2마리" 를 보여 줬다.
/// 그러고는 산책을 저장할 때 "반려동물을 등록하면 올릴게요" 라고 말했다 — 화면과 안내가
/// 서로 다른 말을 한 것이다 (#159).
final ValueNotifier<List<DogProfile>> kMyPets =
    ValueNotifier<List<DogProfile>>(const []);

/// 현재 선택된 아이 인덱스.
final ValueNotifier<int> kSelectedPetIdx = ValueNotifier<int>(0);

/// 현재 선택된 아이(전역) — 홈 히어로/프로필이 구독.
///
/// **`null` 일 수 있다.** 로그인 전이거나, 아직 한 마리도 등록하지 않았거나, 서버를 못
/// 불렀을 때다. 화면은 그때 **빈 상태**를 그려야 한다 — 지어낸 '보리' 를 보여 주면
/// 사용자는 등록이 끝난 줄 안다.
final ValueNotifier<DogProfile?> kMyDog = ValueNotifier<DogProfile?>(null);

/// 아이 선택.
void selectPet(int i) {
  if (i < 0 || i >= kMyPets.value.length) return;
  kSelectedPetIdx.value = i;
  kMyDog.value = kMyPets.value[i];
}

/// 서버가 준 목록으로 통째로 갈아 끼운다. **여기가 유일한 출처다.**
///
/// 빈 목록이면 선택도 비운다 — 지운 아이가 화면에 남아 있으면 안 된다.
void replacePets(List<DogProfile> pets) {
  kMyPets.value = pets;
  if (pets.isEmpty) {
    kSelectedPetIdx.value = 0;
    kMyDog.value = null;
    return;
  }
  final i = kSelectedPetIdx.value.clamp(0, pets.length - 1);
  kSelectedPetIdx.value = i;
  kMyDog.value = pets[i];
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

// ─────────────────────── 산책 기록 ───────────────────────
//
// **여기 있던 더미를 전부 지웠다 (이슈 #145).**
//
//   WalkToday · WalkLog · kWalks · kWeekKm · kWalkTodayIdx
//
// 산책은 이제 서버에 저장된다. 읽는 곳은 `data/walk_feed.dart` 하나이고, 화면들은
// `widgets/walk_feed_builder.dart` 를 지난다.
//
// kWalkTodayIdx 는 상수 6 이었다 — 무슨 요일이든 통계의 "오늘" 막대 강조가 **영원히
// 일요일**에 찍혔다. 지금은 `WalkFeedData.todayIndex` 가 실제 요일을 준다.
//
// 이 더미를 다시 넣지 마라. 화면이 서버를 못 불렀을 때 그릴 것은 **0 이 아니라
// "불러오지 못했어요"** 다 — 0 은 "산책을 한 번도 안 했다" 로 읽힌다.

/// 요일 이름. 통계 차트의 가로축이 쓴다.
///
/// 이것만 남긴 이유: **더미가 아니다.** 위에서 지운 것들은 지어낸 "기록" 이었고, 이건
/// 달력의 사실이다. 월요일이 0 이라는 것도 계약의 `WalkStats.weekKm` 과 같은 약속이다.
const List<String> kWeekDayLabels = ['월', '화', '수', '목', '금', '토', '일'];


// ─────────────────────── 반려 커뮤니티 ───────────────────────



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

// 케어 종류마다 다른 색이 여기 있었다 — 물 파랑 · 투약 라일락 · 기타 분홍(#546).
//
// 걷어낸 이유는 셋이다. (1) `app_tokens.dart` 머리말이 정한 예외는 **지도 카테고리색과
// 상태색뿐**이고 케어는 거기 없다. (2) 라일락은 사장님이 내리신 색이다. (3) "색은 토큰
// 파일에서만 정한다" 는 규칙을 이 파일이 어기고 있었다 — 인라인 `Color(0x…)` 여섯이었다.
//
// 지금 완료한 칸은 **코랄 하나**다. 칸마다 아이콘과 이름이 이미 있어 색으로 가를 필요가 없고,
// 색이 말하는 것은 종류가 아니라 **"했다"** 다.

/// 케어 목록 변경 알림(추가/삭제/토글) — 홈 카드 등 다른 화면 동기화용.
final ValueNotifier<int> kCareRev = ValueNotifier<int>(0);

/// 오늘의 케어 1건(가족 공유). 백엔드(care_log) 연동 전 로컬 상태.
/// [product]는 밥/간식 등에서 선택 입력하는 제품명(사료명) — 추후 소진 예측·제휴 추천의 재료.
/// [daily]=true(기본)면 루틴: 날이 바뀌어도 항목은 유지되고 체크만 리셋.
/// false면 일회성: 날이 바뀌면 자동으로 사라짐(예: '오늘 병원').
class CareTask {
  final CareType type;
  final String label;
  bool done;
  String? by; // 완료한 가족
  String? time; // '08:30'
  String? product; // 제품명(선택) 예: '로얄캐닌 미니 어덜트'
  final bool daily;
  CareTask({
    required this.type,
    required this.label,
    this.done = false,
    this.by,
    this.time,
    this.product,
    this.daily = true,
  });
}

DateTime _careDay = DateTime.now();

/// 날짜가 바뀌었으면: 반복(daily) 항목은 체크만 리셋, 일회성 항목은 제거.
/// 케어를 그리는 화면에서 호출(같은 날이면 아무 일 없음).
void ensureCareFreshForToday() {
  final now = DateTime.now();
  final same =
      now.year == _careDay.year &&
      now.month == _careDay.month &&
      now.day == _careDay.day;
  if (same) return;
  _careDay = now;
  kCareToday.removeWhere((t) => !t.daily);
  for (final t in kCareToday) {
    t.done = false;
    t.by = null;
    t.time = null;
  }
  kCareRev.value++;
}

/// 오늘의 케어 목록(샘플).
///
/// ⚠️ **화면은 더 이상 이것을 그리지 않는다** — 이슈 #76. 홈과 `family_screen` 의
/// "오늘의 케어" 는 `TodayCareCard` 가 `GET /api/groups/{id}/care-logs` 로 그린다.
/// 여기 남은 것은 `CareType`·`careIcon`(아이콘)을 쓰기 위해서다. 색은 `app_tokens.dart` 다.
///
/// 이 리스트로 돌아가면 안 되는 이유: 로컬 리스트는 **한 기기 안에서만** 산다.
/// 엄마가 밥을 줘도 아빠 화면에는 아무 일도 일어나지 않고, 그게 이 이슈가 막으려는
/// 이중 급여다. 자유 항목(`label`·`product`·`daily`)은 서버 모델(다섯 종류)에 없어
/// M4 로 미뤘다.
final List<CareTask> kCareToday = [
  CareTask(
    type: CareType.water,
    label: '물 갈아주기',
    done: true,
    by: '엄마',
    time: '08:10',
  ),
  CareTask(
    type: CareType.meal,
    label: '아침 밥',
    done: true,
    by: '나',
    time: '08:32',
    product: '로얄캐닌 미니 어덜트',
  ),
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

/// ⚠️ **가족 화면은 더 이상 이것을 그리지 않는다** — 이슈 #76 이 `GET /api/groups/me` 로
/// 바꿨다. 아직 남아 있는 것은 `family_chat_screen`(발신자 색 팔레트)과 `kChatRooms` 의
/// `memberCount` 뿐이고, 그 둘은 채팅 이슈(M2.6)가 서버로 옮긴다.
const List<FamilyMember> kFamilyMembers = [
  FamilyMember('나', '보호자', Color(0xFFFF8F63), todayKm: 2.4),
  FamilyMember('엄마', '가족', Color(0xFF57C98A), todayKm: 1.1),
  FamilyMember('아빠', '가족', Color(0xFF5B8DEF), todayKm: 0),
];

/// 가족 초대 코드(옛 더미).
///
/// ⚠️ **화면은 더 이상 이것을 보여주지 않는다** — 이슈 #76. 발급은
/// `POST /api/chat/rooms/{roomId}/invites` 이고 `family_screen` 이 그것을 부른다.
///
/// 이 문자열을 화면에 다시 띄우면 안 된다: **아무도 이 코드로 들어올 수 없다.**
/// 초대는 `chat_room_invite` 행이고 만료·사용횟수·회수를 가진다(ADR-0011). 진짜처럼
/// 보이는 코드를 가족에게 보내면 가족은 조용히 실패한다.
const String kFamilyInviteCode = 'PAW-2481';

/// 산책 시 주의사항(옛 더미).
///
/// ⚠️ **화면은 더 이상 이것을 그리지 않는다** — 이슈 #76. `family_screen` 은
/// `GET|PUT /api/groups/{id}/walk-notes` 를 쓴다. 서버가 아는 것은 **그룹당 메모 한 장**
/// 이고, 줄 단위 목록은 화면의 표현이다(`WalkNoteSheet.lines`).
final List<String> kWalkNotes = [
  '오른쪽 뒷다리 슬개골 — 계단·점프 피하기',
  '대형견 만나면 예민해요. 리드줄 짧게 잡기',
  '산책 후 발 닦고 물 충분히 주기',
];

/// 채팅 더미는 없다. **서버가 준다.** (이슈 #81)
///
/// 예전에는 여기 `ChatMessage` · `ChatRoom` · `kChatRooms` · `kChatMessages` ·
/// `kCrewChatMessages` 가 있었고 채팅 화면 둘이 그것을 그렸다. 지금은
/// `GET /api/chat/rooms` 와 `GET /api/chat/rooms/{id}/messages` 다 —
/// 모델은 `v2/data/chat_repository.dart` 의 [ChatRoomSummary] · [ChatMessageItem] 이다.
///
/// **여기에 채팅 더미를 다시 만들지 말 것.** 화면이 그것을 그리는 순간 서버가 무엇을 주는지
/// 아무도 확인하지 않게 된다 — 그 상태로 다섯 이슈를 지나온 적이 있다.

// **여기 있던 커뮤니티 더미를 전부 지웠다 (이슈 #171).**
//
//   kPetPosts · PetPost · kPetBoards · kPetReactions
//
// 커뮤니티는 이제 서버에 있다. 읽는 곳은 `data/community_repository.dart` 하나이고
// 모델은 그 파일의 CommunityPost · CommunityComment · ReactionSummary 다.
//
// kPetPosts 는 상수 4건이었다 — 누가 글을 써도 **아무에게도 안 보였고**, 반응은
// 화면 로컬 토글이라 앱을 껐다 켜면 사라졌다. 댓글도 같았다.
//
// kPetBoards 는 한글 문자열을 board **값**으로 들고 있었다. ADR-0016 이 그 값을
// ASCII 키(walk_review 등)로 정했고 한글은 화면 문구가 됐다 — 둘을 묶는 자리는
// CommunityBoard enum 하나다. 여기에 라벨 목록을 다시 만들면 그 짝이 두 벌이 된다.
//
// 이 더미를 다시 넣지 마라. 화면이 서버를 못 불렀을 때 그릴 것은 **빈 목록이 아니라
// "불러오지 못했어요"** 다 — 빈 목록은 "아직 글이 없다" 로 읽힌다.
