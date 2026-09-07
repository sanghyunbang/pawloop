// 동물병원의 "지금 열려 있나" — 이름으로 짐작하는 것뿐이다 (#337).
//
// ## 왜 이름인가
//
// 진료시간을 주는 공공 데이터가 없다. 우리가 쓰는 인허가 데이터(행정안전부 LOCALDATA ·
// 서울 열린데이터광장 · 경기데이터드림)는 "이 자리에서 동물병원을 해도 된다" 는 기록이라
// 영업시간이 애초에 항목에 없다. 야간·응급 여부는 병원이 스스로 알리는 정보다.
//
// 그래서 **이름에 24시가 있으면 표시하고, 화면에 "이름 기준" 이라고 함께 적는다.**
// 밤 11시에 전화를 걸 사람에게 우리가 확인하지 않은 것을 확인한 척하면 안 된다.
// 표시가 있든 없든 상세 시트의 첫 동작은 전화다 — "가서 확인" 보다 "걸어서 확인" 이 빠르다.
import '../data/pet_places_repository.dart';

/// 이름에 24시가 붙어 있는가. 공백·가운뎃점을 지우고 본다.
///
/// `24` 뒤가 `시`·`시간`·`h`·`H` 일 때만이다 — "24번지" 같은 주소 조각을 24시로 읽지 않는다.
bool isTwentyFourHourByName(String name) {
  final squeezed = name.replaceAll(RegExp(r'[\s·・.]'), '');
  return RegExp(r'24(시간|시|h)', caseSensitive: false).hasMatch(squeezed);
}

/// 가까운 동물병원 [limit] 곳. 거리는 이미 기기 안에서 잰 값([PetPlace.distM])이다 —
/// 좌표가 서버로 나가지 않는다(A안 #235).
///
/// 거리를 모르는 행(0)은 뒤로 민다. "0m" 로 맨 앞에 세우면 급할 때 엉뚱한 곳으로 전화한다.
List<PetPlace> nearestVets(List<PetPlace> places, {int limit = 3}) {
  final vets = places.where((p) => p.categoryKey == 'vet').toList();
  vets.sort((a, b) {
    final da = a.distM > 0 ? a.distM : double.infinity;
    final db = b.distM > 0 ? b.distM : double.infinity;
    return da.compareTo(db);
  });
  return vets.take(limit).toList();
}
