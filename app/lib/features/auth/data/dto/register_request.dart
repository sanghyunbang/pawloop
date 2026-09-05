// lib/features/auth/data/dto/register_request.dart
//
// 약관 동의 필드가 없다. 동의는 가입이 아니라 첫 로그인 뒤 동의 화면이 받아서
// `PUT /api/consents` 로 적는다(#190). 계약(`openapi.yaml` 의 `SignupInput`)도 같다.
class RegisterRequest {
  final String email;
  final String password;
  final String nickname;
  final String name;
  final String gender;
  final String ageGroup; // 'over14' | 'under14'

  RegisterRequest({
    required this.email,
    required this.password,
    required this.nickname,
    required this.name,
    required this.gender,
    required this.ageGroup,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'nickname': nickname,
        'name': name,
        'gender': gender,
        'ageGroup': ageGroup,
      };
}
