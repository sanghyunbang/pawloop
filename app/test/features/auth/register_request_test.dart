// 가입 요청에 약관 동의 필드가 없는지 본다 — #190 후속 (users 의 옛 동의 컬럼 삭제).
//
// 동의는 가입이 아니라 첫 로그인 뒤 동의 화면이 한 번 받아서 `PUT /api/consents` 로 적는다.
// 가입 요청에 동의 필드가 다시 들어오면 같은 사람에게 두 번 묻는 화면으로 돌아가고, 서버는
// 그 값을 적을 컬럼이 없어서 조용히 버린다 — 보내는 쪽만 "동의를 받았다" 고 믿게 된다.

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/features/auth/data/dto/register_request.dart';

void main() {
  test('가입 요청 JSON 에 동의 필드가 없다 — 동의는 /api/consents 한 곳뿐이다', () {
    final json = RegisterRequest(
      email: 'a@b.c',
      password: 'pw12345678',
      nickname: '보리아빠',
      name: '방상현',
      gender: 'male',
      ageGroup: 'over14',
    ).toJson();

    expect(json.keys, containsAll(['email', 'password', 'nickname', 'name', 'gender', 'ageGroup']));
    for (final key in json.keys) {
      expect(key.toLowerCase(), isNot(contains('agree')),
          reason: '$key — 동의를 가입에 실으면 로그인 뒤 동의 화면과 두 번 묻는다');
      expect(key.toLowerCase(), isNot(contains('version')),
          reason: '$key — 문서 버전은 동의 화면이 서버 기록과 견줘 정한다');
    }
  });
}
