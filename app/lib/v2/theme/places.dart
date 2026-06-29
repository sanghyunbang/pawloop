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
  });
}

const List<Place> kPlaces = [
  Place(from: 2, to: 4, lift: 82, n: 240, x: 27, y: 46, name: '서울숲', cat: '공원 · 산책', dist: '1.8km', pet: true, line: '불안했던 마음이 천천히 가라앉는 호숫가 숲길'),
  Place(from: 2, to: 4, lift: 80, n: 147, x: 57, y: 75, name: '남산 둘레길', cat: '숲길 · 전망', dist: '3.5km', pet: true, line: '숨을 고르며 마음을 정리하는 전망 길'),
  Place(from: 3, to: 4, lift: 77, n: 184, x: 40, y: 63, name: '한강 뚝섬', cat: '강변 · 노을', dist: '2.7km', pet: true, line: '들끓던 마음을 바람에 식히는 강변'),
  Place(from: 1, to: 0, lift: 74, n: 156, x: 46, y: 31, name: '성수 연무장길', cat: '카페 거리', dist: '1.1km', pet: true, line: '가라앉은 기분을 환기시키는 볕 좋은 골목'),
  Place(from: 4, to: 5, lift: 69, n: 128, x: 67, y: 43, name: '디뮤지엄', cat: '전시 · 문화', dist: '2.3km', pet: false, line: '잔잔하던 마음에 설렘을 더하는 전시 공간'),
  Place(from: 1, to: 0, lift: 65, n: 92, x: 75, y: 60, name: '을지로 골목', cat: '펍 · 모임', dist: '3.2km', pet: false, line: '적적한 저녁을 채우는 사람들의 온기'),
];
