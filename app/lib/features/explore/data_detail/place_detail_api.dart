/// place_detail_api.dart
///
/// 장소 상세를 **우리 백엔드에서** 받아 온다 — 이슈 #40.
///
/// ## 예전에는 관광공사를 직접 불렀다
///
/// 공공데이터포털로 `detailCommon2` 와 `detailIntro2` 를 각각 호출했고, 그러려면
/// 서비스키가 앱 바이너리 안에 있어야 했다. `--dart-define` 으로 옮겨도 문자열은 남아서
/// `strings` 한 번이면 나온다. 키는 쿼터·과금이 걸린 자격증명이고 폐기하려면 **앱을 새로
/// 배포**해야 하므로 즉시 대응이 불가능하다.
///
/// 지금은 서버가 대신 부르고 30일 캐시한다. 앱에는 키가 없다.
///
/// ## 호출이 하나로 줄었다
///
/// 계약(`GET /api/places/{contentId}`)이 개요와 반려동반 정보를 한 응답에 담는다.
/// 이 클래스는 그 응답을 **기존 DTO 두 개가 읽던 모양**으로 나눠 돌려준다 — 그래야
/// `DetailCommonDto`/`DetailIntroDto` 와 `mergeDetail` 을 안 건드린다.
///
/// ## `detailIntro2` 는 서버가 안 부른다
///
/// 앱의 상세 매퍼가 그 응답에서 쓰던 것은 **추가 이미지**뿐이었다(`useTime`·`parking` 은
/// DTO 로 파싱만 되고 화면에 안 갔다). 넣으면 상세 1건이 3콜이 되어 서버의 하루 상세
/// 예산이 75건에서 50건으로 준다. **갤러리 이미지가 두 장으로 줄어드는 것을 받아들인
/// 결정**이고, 되돌리려면 계약과 예산을 함께 고쳐야 한다.
library;

import 'dart:async' as dart_async;
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;

import 'package:http/http.dart' as http;
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/errors/app_exception.dart';

class PlaceDetailApi {
  /// http 클라이언트 (테스트 용이성을 위해 외부 주입)
  final http.Client client;

  /// 백엔드 베이스 URL. 기본값은 [Env.apiBase] 다.
  ///
  /// **호스트 허용목록을 두지 않는다.** 예전에는 공공데이터포털 호스트 하나만 허용했는데,
  /// 그건 외부 API 를 직접 부르던 시절의 방어였다. 지금 부르는 곳은 우리 서버이고 그 주소는
  /// 빌드 설정이 정한다 — 여기서 다시 검사하면 로컬 백엔드(`http://10.0.2.2:8080`)에서
  /// 상세가 통째로 막힌다.
  final String baseUrl;

  PlaceDetailApi({required this.client, String? baseUrl})
      : baseUrl = baseUrl ?? Env.apiBase;

  /// 개요·주소·좌표. `DetailCommonDto` 가 읽는 키로 돌려준다.
  Future<Map<String, dynamic>> fetchDetailCommonItem({required int contentId}) async {
    final detail = await _fetch(contentId);
    return <String, dynamic>{
      'contentid': detail['contentId'],
      'title': detail['title'],
      'overview': detail['overview'],
      // 서버는 주소를 한 필드로 준다. addr2 는 없다 — 나눌 근거가 응답에 없으므로
      // 지어내지 않는다(mergeDetail 이 둘을 합쳐 쓰므로 결과는 같다).
      'addr1': detail['addr'],
      'firstimage': detail['image'],
      'mapx': detail['lng'],
      'mapy': detail['lat'],
      'tel': detail['tel'],
    };
  }

  /// 반려동반 정보. `DetailIntroDto` 가 읽는 키로 돌려준다.
  ///
  /// **`contentTypeId` 를 안 쓴다.** 계약이 그것 없이 상세를 준다 — 서버가 이미 아는
  /// 값을 앱이 다시 보낼 이유가 없다. 시그니처를 남겨 둔 것은 호출부
  /// (`PlaceDetailRepository`)를 안 건드리기 위해서다.
  Future<Map<String, dynamic>?> fetchDetailIntroItem({
    required int contentId,
    required int contentTypeId,
  }) async {
    final detail = await _fetch(contentId);
    final petInfo = detail['petInfo'];
    if (petInfo is! Map) return null;

    return <String, dynamic>{
      'contentid': detail['contentId'],
      // 반려동반 정보를 화면이 읽을 수 있는 자리에 싣는다. KTO 의 usetime/parking 계열은
      // 서버가 안 받아 오므로 여기 없다 — 위 라이브러리 주석 참조.
      'acmpyPsblCpam': petInfo['acmpyPsblCpam'],
      'acmpyNeedMtr': petInfo['acmpyNeedMtr'],
      'etcAcmpyInfo': petInfo['etcAcmpyInfo'],
    };
  }

  // ─────────────────────────── 내부 ───────────────────────────

  /// 상세 한 건. 두 공개 메서드가 같은 응답을 나눠 쓴다.
  ///
  /// **캐싱을 여기서 하지 않는다.** 한 화면에서 두 번 부르는 것은 서버 캐시가 흡수하고,
  /// 앱에 캐시를 두면 그것이 언제 낡는지를 또 정해야 한다.
  Future<Map<String, dynamic>> _fetch(int contentId) async {
    final uri = Uri.parse('$baseUrl/api/places/$contentId');

    try {
      final res = await client.get(uri).timeout(const Duration(seconds: 12));

      if (res.statusCode == 404) {
        throw const AppMessageException('장소를 찾을 수 없습니다.');
      }
      if (res.statusCode != 200) {
        throw const AppMessageException('장소 정보를 불러오지 못했습니다.');
      }

      // bodyBytes 에서 직접 디코딩한다. res.body 는 charset 이 없으면 latin-1 로 읽어
      // 한글이 깨진다(#81 에서 겪었다).
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) {
        throw const AppFormatException();
      }
      return decoded.cast<String, dynamic>();
    } on AppException {
      rethrow;
    } on dart_async.TimeoutException {
      throw const AppMessageException('응답이 지연되고 있습니다. 잠시 후 다시 시도해 주세요.');
    } on SocketException {
      throw const AppMessageException('네트워크에 연결할 수 없습니다.');
    } on HandshakeException {
      throw const AppMessageException('보안 연결에 실패했습니다.');
    } catch (_) {
      // 예외 메시지에 URL 조각이 섞일 수 있어 옮기지 않는다.
      throw const AppMessageException('장소 정보를 불러오지 못했습니다.');
    }
  }
}
