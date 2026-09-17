// lib/v2/data/profile_store.dart
//
// 내 프로필을 서버에 적는 **한 자리** — `PUT /auth/me` (#665).
//
// ## 왜 꺼냈나
//
// 같은 엔드포인트로 보내는 코드가 이미 `neighborhood_store` 에 있었다(#342). 표시 이름을
// 고치는 화면(#665)이 그것을 한 벌 더 복사하면 요청을 만드는 자리가 둘이 된다 — 401 재시도도,
// 응답 본문을 읽는 규칙도 각자 늙는다. 그래서 요청 한 번을 여기로 꺼내고 동네 저장은 이 위에
// 앉혔다. 이 파일이 `AuthedClient` 를 부르는 유일한 v2 프로필 경로다.
//
// ## 실패를 한 가지로 뭉치지 않는다
//
// 화면이 "저장 못 했어요" 로 끝나면 사람은 무엇을 고쳐야 할지 모른다. 길이 초과(400)의
// "닉네임은 20자를 넘을 수 없습니다." 는 **서버가 준 문구**고, 우리가 지어내면 서버 상한이
// 바뀔 때 앱이 거짓말을 하게 된다. 그래서 본문의 문구를 그대로 올려 준다. 본문이 계약과
// 다르면 문구는 `null` 이다 — 모르는 이유는 지어내지 않는다(`schedule_repository` 와 같은 규칙).
//
// ## 빈 값을 여기서 막는 이유
//
// 서버의 `UserService.updateProfile` 은 `isBlank()` 인 닉네임을 **"안 바꿈"** 으로 읽고
// 200 을 준다. 그대로 보내면 아무것도 안 바뀌었는데 화면은 "저장했어요" 라고 말하고 닫힌다.
// 화면도 막지만, 막는 자리가 화면 하나뿐이면 다음 호출부가 같은 함정을 다시 밟는다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/config/env.dart';
import '../../core/net/authed_client.dart';
import '../../features/auth/data/auth_repository_impl.dart';

/// `PUT /auth/me` 한 번의 결말.
@immutable
class ProfileSaveResult {
  /// 200. [user] 는 서버가 돌려준 **갱신된 나**다.
  const ProfileSaveResult.saved(Map<String, dynamic> this.user)
      : ok = true,
        statusCode = 200,
        message = null;

  /// 서버가 거절했다. [message] 는 서버 문구(없으면 null).
  const ProfileSaveResult.rejected({
    required int this.statusCode,
    this.message,
  })  : ok = false,
        user = null;

  /// 응답 자체가 없었다 — 끊겼거나 못 붙었다.
  const ProfileSaveResult.offline()
      : ok = false,
        statusCode = null,
        message = null,
        user = null;

  /// 보내기 전에 앱이 막았다. 왕복이 없으므로 [statusCode] 도 없다.
  const ProfileSaveResult.blocked(String this.message)
      : ok = false,
        statusCode = null,
        user = null;

  final bool ok;

  /// HTTP 상태. 요청이 나가지 않았거나 응답이 없으면 null.
  final int? statusCode;

  /// 서버(또는 앱)가 준 사람 말. 없으면 null.
  final String? message;

  /// 200 의 본문. `AuthUser.fromJson` 이 읽는 모양 그대로다.
  final Map<String, dynamic>? user;

  /// 화면에 띄울 한 줄. **서버 문구가 먼저다** — 상한 같은 규칙은 서버가 정본이다.
  String get reason {
    final given = message;
    if (given != null && given.trim().isNotEmpty) return given;
    switch (statusCode) {
      case null:
        return '지금은 저장하지 못했어요 · 연결을 확인해 주세요';
      case 401:
        return '로그인이 풀렸어요 · 다시 로그인해 주세요';
      case 429:
        return '너무 자주 바꿨어요 · 잠시 뒤에 다시 시도해 주세요';
      default:
        return '저장하지 못했어요 · 잠시 뒤에 다시 시도해 주세요';
    }
  }
}

class ProfileStore {
  ProfileStore({AuthedClient? client, String? baseUrl})
      : _authed = client ?? AuthedClient.instance,
        _baseUrl = baseUrl ?? Env.apiBase;

  final AuthedClient _authed;
  final String _baseUrl;

  /// 표시 이름의 최대 글자 수.
  ///
  /// 정본은 서버의 `User.MAX_NICKNAME_LENGTH` 이고(#229), 앱에는 그 수가 이미
  /// [AuthRepositoryImpl.maxNicknameLength] 에 있다. 숫자를 여기 또 적지 않고 그것을 가리킨다 —
  /// 같은 수를 두 곳에 적어 두면 한쪽만 고쳐지는 날이 온다.
  static const int maxNicknameLength = AuthRepositoryImpl.maxNicknameLength;

  /// 빈 이름을 막을 때 하는 말. 화면과 저장소가 같은 문장을 쓴다.
  static const String emptyNameReason =
      '이름을 비워 둘 수 없어요 — 비우면 \'이름 없는 계정\' 으로 보여요';

  /// 표시 이름만 바꾼다. **다른 칸은 안 보낸다** — `null` 은 서버에서 "안 바꿈" 이다.
  Future<ProfileSaveResult> saveNickname(String nickname) {
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) {
      return Future.value(const ProfileSaveResult.blocked(emptyNameReason));
    }
    // 길이는 여기서 자르지 않는다. 화면의 입력 상한이 먼저 막고, 그래도 넘어온 값은
    // **서버가 판정한다** — 앱이 세는 단위(자소)와 서버가 세는 단위(UTF-16)가 이모지에서
    // 갈리기 때문에, 앱이 여기서 거절하면 서버라면 받아 줬을 이름을 앱이 거절할 수 있다.
    return update({'nickname': trimmed});
  }

  /// 프로필 부분 수정 한 번. [body] 에 넣은 칸만 바뀐다.
  Future<ProfileSaveResult> update(Map<String, dynamic> body) async {
    try {
      final response = await _authed.putJson(
        Uri.parse('$_baseUrl/auth/me'),
        body: body,
      );
      final decoded = _decode(response.bodyBytes);
      if (response.statusCode == 200) {
        return ProfileSaveResult.saved(
          decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{},
        );
      }
      if (kDebugMode) {
        debugPrint('[Profile] 저장 실패: ${response.statusCode}');
      }
      return ProfileSaveResult.rejected(
        statusCode: response.statusCode,
        message: _messageOf(decoded),
      );
    } catch (e) {
      // 게스트·오프라인이 여기로 온다. 상태 코드가 없으므로 "연결" 로 말한다.
      if (kDebugMode) debugPrint('[Profile] 저장 오류: ${e.runtimeType}');
      return const ProfileSaveResult.offline();
    }
  }

  static Object? _decode(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// 오류 본문의 계약은 `{"error":{"code":…,"message":…}}` (`GlobalExceptionHandler`).
  static String? _messageOf(Object? body) {
    if (body is Map && body['error'] is Map) {
      final message = (body['error'] as Map)['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    return null;
  }
}
