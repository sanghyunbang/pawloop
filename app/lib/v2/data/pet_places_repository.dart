import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/env.dart';
import '../domain/pet.dart';

/// 관광공사 반려동물 동반여행(KorPetTourService2) 장소.
class PetPlace {
  final String contentId;
  final String title;
  final String contentTypeId;
  final String addr;
  final String image;
  final String tel;
  final double lat;
  final double lng;
  final double distM; // locationBasedList2의 거리(m)

  const PetPlace({
    required this.contentId,
    required this.title,
    required this.contentTypeId,
    required this.addr,
    required this.image,
    required this.tel,
    required this.lat,
    required this.lng,
    this.distM = 0,
  });

  PetCategory get category => petCatByType(contentTypeId);

  String get distLabel =>
      distM <= 0 ? '' : (distM < 1000 ? '${distM.round()}m' : '${(distM / 1000).toStringAsFixed(1)}km');

  factory PetPlace.fromJson(Map<String, dynamic> j) => PetPlace(
        contentId: '${j['contentid'] ?? ''}',
        title: '${j['title'] ?? ''}',
        contentTypeId: '${j['contenttypeid'] ?? ''}',
        addr: '${j['addr1'] ?? ''}',
        image: '${j['firstimage'] ?? j['firstimage2'] ?? ''}',
        tel: '${j['tel'] ?? ''}',
        lat: double.tryParse('${j['mapy'] ?? ''}') ?? 0,
        lng: double.tryParse('${j['mapx'] ?? ''}') ?? 0,
        distM: double.tryParse('${j['dist'] ?? ''}') ?? 0,
      );
}

class PetPlacesRepository {
  static const _base = 'https://apis.data.go.kr/B551011/KorPetTourService2';

  /// 내 주변 반려동반 가능 장소(거리순). key는 이미 인코딩된 형태라 그대로 사용.
  Future<List<PetPlace>> fetchNearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int numOfRows = 80,
    String? contentTypeId,
  }) async {
    final key = Env.tourServiceKey;
    if (key.isEmpty) return const [];
    final qp = StringBuffer()
      ..write('serviceKey=$key')
      ..write('&MobileOS=ETC&MobileApp=heattrip&_type=json')
      ..write('&numOfRows=$numOfRows&pageNo=1')
      ..write('&mapX=$lng&mapY=$lat&radius=$radius&arrange=E');
    if (contentTypeId != null && contentTypeId.isNotEmpty) {
      qp.write('&contentTypeId=$contentTypeId');
    }
    final uri = Uri.parse('$_base/locationBasedList2?$qp');
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const [];
    return _parse(res.body);
  }

  List<PetPlace> _parse(String body) {
    try {
      final j = jsonDecode(body);
      final b = j['response']?['body'];
      final items = b?['items'];
      if (items == null || items == '' || items is String) return const [];
      var arr = items['item'];
      if (arr == null) return const [];
      if (arr is Map) arr = [arr];
      return (arr as List)
          .whereType<Map>()
          .map((e) => PetPlace.fromJson(e.cast<String, dynamic>()))
          .where((p) => p.lat != 0 && p.lng != 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
