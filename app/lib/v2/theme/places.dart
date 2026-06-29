/// 탐색용 장소 데이터 (핸드오프 mapData).
/// from/to = 감정 인덱스(EMO), lift = 호전율%, n = 표본, x/y = 지도 좌표(%).
class Place {
  final int from;
  final int to;
  final int lift;
  final int n;
  final double x;
  final double y;
  final String name;
  final String cat;
  final String dist;
  final bool pet;
  final String line;
  final String about;
  final double lat; // 실제 지도용 위도
  final double lng; // 경도
  const Place({
    required this.from,
    required this.to,
    required this.lift,
    required this.n,
    required this.x,
    required this.y,
    required this.name,
    required this.cat,
    required this.dist,
    required this.pet,
    required this.line,
    required this.about,
    required this.lat,
    required this.lng,
  });
}

const List<Place> kPlaces = [
  Place(from: 2, to: 4, lift: 82, n: 240, x: 27, y: 46, lat: 37.5444, lng: 127.0374, name: '서울숲', cat: '공원 · 산책', dist: '1.8km', pet: true, line: '불안했던 마음이 천천히 가라앉는 호숫가 숲길', about: '넓은 숲과 호숫가 산책로가 이어져 생각을 비우기 좋아요. 사슴 방사장을 지나 갤러리 카페에서 천천히 시간을 보내면, 들끓던 마음이 차분히 가라앉아요. 혼자 걷기에도, 가볍게 머물기에도 좋은 곳.'),
  Place(from: 2, to: 4, lift: 80, n: 147, x: 57, y: 75, lat: 37.5512, lng: 126.9882, name: '남산 둘레길', cat: '숲길 · 전망', dist: '3.5km', pet: true, line: '숨을 고르며 마음을 정리하는 전망 길', about: '완만한 숲길과 도시 전망이 어우러진 길이에요. 숨을 고르며 천천히 걷다 보면 불안한 생각이 차분히 정리돼요. 머리가 복잡한 날 걷기를 추천해요.'),
  Place(from: 3, to: 4, lift: 77, n: 184, x: 40, y: 63, lat: 37.5305, lng: 127.0668, name: '한강 뚝섬', cat: '강변 · 노을', dist: '2.7km', pet: true, line: '들끓던 마음을 바람에 식히는 강변', about: '탁 트인 강과 노을이 펼쳐지는 곳. 자전거를 타거나 돗자리를 펴고 바람을 맞으면 들끓던 마음이 한결 식어요. 해 질 무렵에 가면 더 좋아요.'),
  Place(from: 1, to: 0, lift: 74, n: 156, x: 46, y: 31, lat: 37.5447, lng: 127.0557, name: '성수 연무장길', cat: '카페 거리', dist: '1.1km', pet: true, line: '가라앉은 기분을 환기시키는 볕 좋은 골목', about: '햇살 좋은 카페와 작은 편집숍이 이어진 골목이에요. 천천히 걸으며 사람 구경을 하다 보면 울적했던 기분이 환기돼요. 좋아하는 음료 한 잔과 함께하는 산책을 추천해요.'),
  Place(from: 4, to: 5, lift: 69, n: 128, x: 67, y: 43, lat: 37.5347, lng: 127.0048, name: '디뮤지엄', cat: '전시 · 문화', dist: '2.3km', pet: false, line: '잔잔하던 마음에 설렘을 더하는 전시 공간', about: '감각적인 기획 전시가 자주 열리는 공간이에요. 새로운 시각적 자극이 평온하던 마음에 설렘을 더해줘요. 천천히 작품을 둘러보며 영감을 얻기 좋아요.'),
  Place(from: 1, to: 0, lift: 65, n: 92, x: 75, y: 60, lat: 37.5662, lng: 126.9912, name: '을지로 골목', cat: '펍 · 모임', dist: '3.2km', pet: false, line: '적적한 저녁을 채우는 사람들의 온기', about: '오래된 골목 사이 작은 술집과 모임 공간이 모여 있어요. 사람들의 두런두런한 온기 속에 머물다 보면 적적했던 마음이 풀려요. 가까운 사람과 함께 가기 좋은 곳.'),
];
