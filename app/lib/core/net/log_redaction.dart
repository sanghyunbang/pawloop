// lib/core/net/log_redaction.dart
//
// 로그에 남으면 안 되는 값을 가린다 — 이슈 #61.
//
// 왜 별도 파일인가: 마스킹 규칙은 순수 함수라 위젯이나 HTTP 계층 없이 테스트할 수 있다.
// 그리고 로거가 하나 더 생겨도 같은 규칙을 쓰게 하려면 한 곳에 있어야 한다.
//
// 백엔드는 #6 에서 같은 일을 했다(토큰·시크릿·이메일을 어떤 로그 레벨에도 남기지 않는다).
// 프론트에는 그 규칙이 없었고, 그래서 KTO 서비스키가 URL 째로 플랫폼 로그에 남고 있었다.
//
// 좌표는 비밀이 아니라 **개인정보**라 다르게 다룬다 — 이슈 #186. 통째로 지우면 위치
// 디버깅이 안 되고(#160 은 좌표를 눈으로 보고 잡았다), 그대로 두면 로그를 이슈에 붙이는
// 순간 어느 집 앞인지가 남는다. 그래서 **소수 둘째 자리까지만** 남긴다 — 약 1.1km 격자라
// "강남역 근처" 는 알 수 있고 집은 알 수 없다.

/// 값이 통째로 로그에 남으면 안 되는 쿼리 파라미터 이름(소문자 비교).
///
/// `serviceKey` 는 KTO 공공데이터 키다. 쿼리스트링으로 흐르기 때문에 URL 을 찍는 순간 샌다.
/// 앱에서 이 키를 완전히 없애는 것은 백엔드 프록시(#40) 작업이고, 그전까지는 최소한
/// 로그로 새지 않게 한다.
/// 비교 전에 `_`·`-` 를 걷어내고 소문자로 만든다.
///
/// 같은 개념이 `refresh_token`·`refreshToken`·`refresh-token` 세 모양으로 온다.
/// 목록에 셋을 다 적으면 하나를 빠뜨리고, 빠뜨린 그 하나가 새는 경로가 된다.
/// (실제로 처음에 `refreshToken` 을 빠뜨려 테스트가 잡았다.)
String _normalize(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[_-]'), '');

const _secretQueryKeys = <String>{
  'servicekey',
  'token',
  'accesstoken',
  'refreshtoken',
  'refresh',
  'key',
  'apikey',
  'secret',
  'clientsecret',
  'code',
  'password',
};

/// 값이 통째로 로그에 남으면 안 되는 헤더 이름.
const _secretHeaders = <String>{
  'authorization',
  'cookie',
  'setcookie',
  'proxyauthorization',
  'xapikey',
};

/// 좌표 파라미터·필드 이름(소문자 비교). 비밀 목록과 **섞지 않는다** — 비밀은 지우고,
/// 좌표는 자른다. 목록의 뜻이 다르다(#186).
const _coordinateKeys = <String>{
  'lat',
  'lng',
  'lon',
  'latitude',
  'longitude',
};

/// 좌표에 남기는 소수 자릿수. 둘째 자리는 위도 기준 약 1.1km 다.
const coordinatePrecision = 2;

/// 가려진 값을 나타내는 표식.
///
/// 별표가 아니라 글자인 이유: `Uri.replace(queryParameters:)` 가 값을 퍼센트 인코딩한다.
/// `***` 를 쓰면 로그에 `%2A%2A%2A` 로 나와 사람이 읽기 어렵고, 테스트가 표식을
/// 찾지 못한다(실제로 그렇게 한 번 빨간불이 났다).
const redactedMark = 'REDACTED';

/// 좌표 하나를 소수 [coordinatePrecision] 자리까지만 남긴다.
///
/// 숫자가 아니면 그대로 돌려준다 — 좌표 이름을 달고 온 값이 좌표가 아닐 때(예: 검색어)
/// 그것까지 지울 이유는 없다.
String truncateCoordinate(String value) {
  final number = double.tryParse(value);
  if (number == null) return value;
  return number.toStringAsFixed(coordinatePrecision);
}

/// URL 에서 민감한 쿼리 파라미터 값을 가린다.
///
/// 경로와 나머지 파라미터는 그대로 둔다 — 디버깅에 필요하고 비밀이 아니다.
/// **디버그 빌드에서도 가린다.** 개발자가 화면을 공유하거나 로그를 이슈에 붙이는 경로가
/// 실재하고, 그때 "디버그니까 괜찮다" 는 성립하지 않는다.
/// 좌표 파라미터는 지우지 않고 자른다 — 파일 머리의 이유.
String redactUrl(Uri url) {
  if (url.queryParameters.isEmpty) return url.toString();

  final masked = <String, String>{};
  url.queryParameters.forEach((name, value) {
    final key = _normalize(name);
    if (_secretQueryKeys.contains(key)) {
      masked[name] = redactedMark;
    } else if (_coordinateKeys.contains(key)) {
      masked[name] = truncateCoordinate(value);
    } else {
      masked[name] = value;
    }
  });
  return url.replace(queryParameters: masked).toString();
}

/// 헤더 한 줄을 `이름: 값` 으로 만들되 민감한 이름이면 값을 가린다.
String redactHeader(String name, String value) {
  final safe =
      _secretHeaders.contains(_normalize(name)) ? redactedMark : value;
  return '$name: $safe';
}

/// 응답 본문에서 토큰처럼 생긴 값을 가리고, 좌표처럼 생긴 값을 자른다.
///
/// 본문은 형태를 모르기 때문에 이름 기반으로만 가린다. 완벽하지 않다 —
/// 그래서 본문 로깅 자체가 디버그 전용이어야 한다(`LoggingClient` 가 그렇게 한다).
/// 여기서 잡는 것은 가장 흔한 모양들이다.
///   `"token":"eyJ..."`  ·  `"refreshToken": "abc"`  ·  `"lat": 37.544712`
String redactBody(String body) {
  final secretsHidden = body.replaceAllMapped(
    RegExp(
      r'"(access_?token|refresh_?token|token|password|secret)"\s*:\s*"[^"]*"',
      caseSensitive: false,
    ),
    (m) => '"${m[1]}":"$redactedMark"',
  );
  return secretsHidden.replaceAllMapped(
    RegExp(
      r'"(lat|lng|lon|latitude|longitude)"\s*:\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ),
    (m) => '"${m[1]}":${truncateCoordinate(m[2]!)}',
  );
}
