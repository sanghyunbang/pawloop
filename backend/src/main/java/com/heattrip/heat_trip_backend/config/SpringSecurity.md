```
[클라이언트 로그인 요청]
     ↓
Spring Security가 자동으로 OAuth2 로그인 처리
     ↓
AccessToken 받음 + 사용자 정보 조회
     ↓
✔ CustomOAuth2UserService.loadUser() 호출됨
     ↓
(회원 정보 저장)
     ↓
✔ OAuth2SuccessHandler.onAuthenticationSuccess() 호출됨
     ↓
→ JWT 발급, 리다이렉트 처리
```