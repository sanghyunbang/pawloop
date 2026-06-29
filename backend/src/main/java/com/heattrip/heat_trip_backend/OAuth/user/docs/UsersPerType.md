### Google

1. 사전 구조 (Google 응답 예시)
Google OAuth2에서 https://www.googleapis.com/oauth2/v3/userinfo를 호출하면 다음과 같은 응답을 받습니다:

```
{
  "sub": "103284713847102934719",
  "name": "John Doe",
  "given_name": "John",
  "family_name": "Doe",
  "picture": "https://lh3.googleusercontent.com/a-/someimage",
  "email": "johndoe@gmail.com",
  "email_verified": true,
  "locale": "en"
}
```
2. OAuth2UserInfo 인터페이스 (기반)
3. GoogleOAuth2User.java 코드

### Kakao

1. 사전 구조 

```
{
  "id": 1234567890,
  "connected_at": "2023-01-01T00:00:00Z",
  "kakao_account": {
    "email": "user@kakao.com",
    "profile": {
      "nickname": "홍길동",
      "profile_image_url": "http://...jpg"
    }
  }
}
```

### Naver

1. 사전 구조

```
{
  "resultcode": "00",
  "message": "success",
  "response": {
    "id": "NAvER_121212121212",
    "email": "naveruser@naver.com",
    "name": "홍길동",
    "nickname": "길동이",
    "profile_image": "https://..."
  }
}
```

