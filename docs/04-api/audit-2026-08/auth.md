# 1부 · `/auth` 계약 검증

[← 인덱스](./README.md) · 관련 이슈 [#23](https://github.com/sanghyunbang/heattrip/issues/23)

> `NEW-*` 번호는 검증 에이전트별로 독립 부여되어 중복된다. 내용이 겹치는 항목이 있다.

---

## C1 · `CONFIRMED`

**근거**

docs/04-api/openapi.yaml:5-15 의 info.description 블록 안, 정확히 12번째 줄에 존재.
L5: `  description: |`
L12: `    - 인증: JWT Bearer. subject = 사용자 email.`
(주장에는 없던 마침표 `.` 가 실제로는 문장 끝에 붙어 있으나 내용은 동일)
대응하는 securityScheme 은 openapi.yaml:699-703 `bearerAuth: { type: http, scheme: bearer, bearerFormat: JWT }`, 전역 적용은 openapi.yaml:40-41 `security:\n  - bearerAuth: []`.

**정정 · 정확한 사실**

문구 존재 자체는 사실이므로 CONFIRMED. 다만 '계약이 그렇게 적혀 있다'와 '그 서술이 옳다'는 별개이고, 이 서술은 구현의 절반에서 거짓이다. 이메일/비밀번호 로그인 경로만 subject=email 이다 — backend/src/main/java/com/heattrip/heat_trip_backend/user/service/UserService.java:89 `return jwtProvider.createAccessToken(user.getEmail(), "ROLE_USER");`. 반면 소셜 로그인 경로의 subject 는 email 이 아니라 `provider_providerId` 다 — OAuth/handler/OAuth2SuccessHandler.java:48 `String userId = authentication.getName();` → OAuth/user/CustomOAuth2User.java:39-43 `return userInfo.getProvider() + "_" + userInfo.getProviderId();` (주석 예시 `kakao_123456`), 그리고 OAuth/jwt/JWTProvider.java:54 `.setSubject(userId)`. 계약이 Auth 태그를 '소셜 로그인(카카오/네이버)·토큰·내 정보'(openapi.yaml:26-27)로 규정해 소셜을 1급 경로로 삼고 있으므로, 'subject = 사용자 email' 은 계약의 주 경로에서 성립하지 않는 불변식이다. 실제 파급: AuthController.java:40-45 `me()` 가 `userService.emailFromAuth(authHeader)` → `findByEmail(email)` 을 하는데(UserService.java:139-148 `emailFromAuth` 는 그냥 subject 를 돌려줌, UserService.java:94-97 `findByEmail` 은 없으면 IllegalArgumentException), 소셜 발급 토큰으로 GET /auth/me 를 부르면 subject 가 `kakao_123456` 이라 조회 실패한다.

**제안 수정**

계약에서 subject 를 email 로 못박지 말고 '불투명 주체 식별자'로 바꾸고, 실제 두 갈래를 명시하라. openapi.yaml:12 를 교체:
```yaml
    - 인증: JWT Bearer(HS256). `sub` = 서버가 발급한 **불투명 사용자 키**이며
      이메일이라고 가정하지 말 것. 현재 발급 규칙:
        * 이메일/비밀번호 로그인 → `sub` = 사용자 email
        * 소셜 로그인 → `sub` = `{provider}_{providerId}` (예: `kakao_123456`)
      클라이언트는 `sub` 를 파싱하지 말고 `GET /auth/me` 로 사용자 정보를 조회한다.
      (권장 수렴안: 양쪽 모두 `sub` = User.id 로 통일하고 `email`/`provider` 는 별도 클레임)
```
그리고 components/securitySchemes/bearerAuth(openapi.yaml:700-703)에 설명을 붙여라:
```yaml
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
      description: |
        클레임: `sub`(불투명 사용자 키), `role`(예: ROLE_USER), `iat`, `exp`.
        `jti` 는 아직 없음(로그아웃 시 AT 무효화 불가) — backend/TODO/refresh-token-redis.md 참조.
```

---

## C2 · `CONFIRMED`

**근거**

[계약에 없음] openapi.yaml 의 Auth 경로는 딱 5개뿐 — L45 `/auth/oauth/{provider}`, L60 `/auth/oauth/{provider}/callback`, L85 `/auth/token/refresh`, L107 `/auth/me`, L125 `/auth/logout`. 파일 전체(1056줄)에서 `signup` 문자열은 0건이고 `login` 은 L51/L76 의 딥링크 문자열 `heattrip://login-callback` 뿐이다(경로 아님). `/auth/me` 블록(L107-123)에는 `get:`(L108)과 `delete:`(L118)만 있고 `put:` 이 없다 — 파일 전체에서 `    put:` 은 L670 단 1건(그룹 관련)이다.
[백엔드가 씀] backend/src/main/java/com/heattrip/heat_trip_backend/user/controller/AuthController.java:19 `@RequestMapping("/auth")`, L25 `@PostMapping("/signup")`, L31 `@PostMapping("/login")`, L48 `@PutMapping("/me")` (L49-56 `updateMe(...)`).
[앱이 씀] app/lib/features/auth/data/auth_repository_impl.dart:22 `final url = Uri.parse('$baseUrl/auth/login');`, L50 `final url = Uri.parse('$baseUrl/auth/signup');`, L126 `final url = Uri.parse('$baseUrl/auth/me'); // PUT` + L128 `await http.put(`.
[죽은 코드 아님 — 실제 호출부] app/lib/features/auth/presentation/login_screen.dart:17,37 `_authRepository.login(`; app/lib/features/auth/presentation/sign_up_screen.dart:40,177 `_authRepository.register(req)`; app/lib/features/profile/presentation/screens/profile_edit_screen.dart:219 `_authRepo.updateMyProfile(token, req)`.
[베이스 URL 확인] app/lib/core/config/env.dart:19-24 `apiBase` 는 `http://10.0.2.2:8080` 등 오리진만 반환(경로 프리픽스 없음) → 실제 호출 경로는 계약 기준 `/auth/login`, `/auth/signup`, `PUT /auth/me` 가 맞다.

**정정 · 정확한 사실**

주장 그대로 사실이다. 반증을 시도했으나 실패: (a) 계약에 다른 이름의 동등 엔드포인트가 숨어 있지 않다(signup 0건, login 경로 0건, put 1건뿐), (b) 앱 코드가 주석 처리된 죽은 코드가 아니다(위 3개 화면에서 실제 호출), (c) baseUrl 에 경로 프리픽스가 없어 경로 불일치로 인한 착시도 아니다. 덧붙일 정확한 사실 2가지: ① POST /auth/login 의 응답은 JSON 이 아니라 **JWT 원문 문자열**이다 — AuthController.java:32-35 `ResponseEntity<String> ... ResponseEntity.ok(token)`, 앱도 auth_repository_impl.dart:36-37 `final token = response.body;` 로 본문 전체를 토큰으로 취급. 즉 계약에 추가할 때 `AuthTokens` 스키마를 그대로 쓰면 현행 구현과 또 어긋난다. ② POST /auth/signup 은 201 이 아니라 200 + 본문 `"회원가입 성공"` 문자열을 준다(AuthController.java:28), 앱은 200/201 둘 다 허용(auth_repository_impl.dart:59).

**제안 수정**

세 오퍼레이션을 계약에 추가하되, 현행 구현을 그대로 박제하지 말고 '목표 계약'을 쓰고 구현 변경 항목을 명시하라. openapi.yaml 의 `/auth/oauth/{provider}` 바로 앞(L44 뒤)에 삽입:
```yaml
  /auth/signup:
    post:
      tags: [Auth]
      summary: 이메일 회원가입
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [email, password, nickname, agreeTos, agreePrivacy]
              properties:
                email: { type: string, format: email }
                password: { type: string, format: password, minLength: 8 }
                nickname: { type: string }
                name: { type: string }
                gender: { type: string, enum: [male, female, other] }
                ageGroup: { type: string, enum: [under14, over14] }
                agreeTos: { type: boolean }        # false/null 이면 400
                agreePrivacy: { type: boolean }    # false/null 이면 400
                agreeMarketing: { type: boolean }
                tosVersion: { type: string, default: "v1.0" }
                privacyVersion: { type: string, default: "v1.0" }
                marketingVersion: { type: string, default: "v1.0" }
      responses:
        '201': { description: 가입됨, content: { application/json: { schema: { $ref: '#/components/schemas/User' } } } }
        '400': { $ref: '#/components/responses/ValidationError' }   # 필수 동의 누락
        '409': { $ref: '#/components/responses/Conflict' }          # 이미 가입된 이메일

  /auth/login:
    post:
      tags: [Auth]
      summary: 이메일/비밀번호 로그인
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [email, password]
              properties:
                email: { type: string, format: email }
                password: { type: string, format: password }
      responses:
        '200':
          description: 토큰 발급
          content:
            application/json:
              schema: { $ref: '#/components/schemas/AuthTokens' }
        '401': { $ref: '#/components/responses/Unauthorized' }
```
그리고 `/auth/me`(L107) 블록의 `get:`(L108-117)과 `delete:`(L118-123) 사이에 `put:` 을 추가:
```yaml
    put:
      tags: [Auth]
      summary: 내 정보 수정(부분 수정 — 보낸 필드만 반영)
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/UserUpdate' }
      responses:
        '200': { description: 수정됨, content: { application/json: { schema: { $ref: '#/components/schemas/User' } } } }
        '400': { $ref: '#/components/responses/ValidationError' }
        '401': { $ref: '#/components/responses/Unauthorized' }
```
components/schemas 에 `UserUpdate` 신설(backend UpdateProfileRequest / UserService.updateProfile:100-138 기준):
```yaml
    UserUpdate:
      type: object
      minProperties: 1
      properties:
        name: { type: string }
        nickname: { type: string }
        gender: { type: string, enum: [MALE, FEMALE, OTHER] }
        age: { type: integer }
        travelType: { type: string }
        imageUrl: { type: string, format: uri }
        agreeMarketing: { type: boolean }
```
주의: 시맨틱상 '부분 수정'이므로 장기적으로는 `PUT` 대신 `PATCH /auth/me` 가 옳다. 계약에 PUT 을 적을 거면 '부분 수정'임을 summary 에 명시(위 예시대로)하고, 정리 이슈로 PATCH 전환을 남겨라. 또한 위 계약을 채택하면 백엔드 2곳을 함께 고쳐야 한다 — AuthController.java:26-29(200+평문 → 201+User JSON), AuthController.java:31-35(평문 토큰 → AuthTokens JSON), 그리고 앱 auth_repository_impl.dart:36-37, 58-59 의 파싱.

---

## C3 · `PARTIAL`

**근거**

openapi.yaml:125-130 전문:
L125: `  /auth/logout:`
L126: `    post:`
L127: `      tags: [Auth]`
L128: `      summary: 로그아웃(refreshToken 폐기)`
L129: `      responses:`
L130: `        '204': { description: 로그아웃됨 }`
→ requestBody 없음, parameters 없음, security 오버라이드 없음, 401 응답 없음. 전부 사실.
그러나 '전달할 방법이 없다'는 틀렸다: openapi.yaml:40-41 `security:\n  - bearerAuth: []` 가 전역이고 L125-130 에 `security: []` 오버라이드가 없으므로 **이 오퍼레이션은 Bearer 액세스 토큰을 요구한다**. 즉 서버는 AT 의 `sub` 로 주체를 식별해 '그 사용자의 refreshToken 전부'를 폐기할 수 있고, 백엔드가 실제로 그 설계다 — AuthController.java:69-76 `String authHeader = request.getHeader("Authorization"); String email = userService.emailFromAuth(authHeader); userService.logout(email);`. 별도 Swagger 문서에도 `@SecurityRequirement(name = "bearerAuth")` 가 붙어 있다(user/controller/AuthApiDoc.java:20).

**정정 · 정확한 사실**

'requestBody 가 없다'와 'summary 가 로그아웃(refreshToken 폐기)이다'는 CONFIRMED. 하지만 결론인 '어떤 refreshToken 을 폐기할지 전달할 방법이 계약에 없다'는 REFUTED — 전역 bearerAuth 로 액세스 토큰이 주체를 전달하므로 '해당 사용자의 모든 RT 폐기(전 기기 로그아웃)' 시맨틱은 계약상 표현 가능하고, 백엔드도 그 방식이다. 진짜 결함은 다른 세 가지다. ① **시맨틱이 계약에 안 적혀 있다**: '현재 기기만'인지 '전 기기'인지 summary/description 어디에도 없어 멀티 디바이스 동작이 미정의다. requestBody 가 없으니 사실상 '전 기기'인데 그걸 명시하지 않았다. ② **401 응답 누락**: 인증을 요구하면서 responses 에 204 만 있다(L129-130). AuthApiDoc.java:18-19 는 204 와 401 둘 다 선언하고 있어 두 문서가 서로 어긋난다. ③ **폐기할 refreshToken 이 애초에 존재하지 않는다**: 백엔드 전체에 RefreshToken 엔티티/저장소/발급 코드가 없고(`grep -rn 'refresh' backend/src/main/java` 결과는 PlaceRepository.refreshAllSearchTexts 등 무관한 것과 AuthApiDoc.java:15 의 설명 문구뿐), `UserService.logout` 은 **빈 메서드**다 — user/service/UserService.java:161-165 `@Transactional public void logout(String email) { }`. 즉 계약의 summary '(refreshToken 폐기)'는 현시점에 아무것도 폐기하지 않는 no-op 을 서술하는 거짓말이며, AT 에 `jti` 도 없어(JWTProvider.java:53-58 은 setSubject/claim/setIssuedAt/setExpiration 만) 액세스 토큰 무효화도 불가능하다. 미구현 사실은 backend/TODO/refresh-token-redis.md 가 스스로 인정한다('`UserService.logout` 채우기 ... ← 지금 비어있는 메서드').

**제안 수정**

계약을 '전 기기 로그아웃 + 선택적 단일 세션 종료'로 명시하고 401 을 채워라. openapi.yaml:125-130 을 교체:
```yaml
  /auth/logout:
    post:
      tags: [Auth]
      summary: 로그아웃
      description: |
        Authorization 헤더의 액세스 토큰으로 주체를 식별한다.
        - `refreshToken` 을 **보내지 않으면**: 해당 사용자의 모든 refreshToken 폐기(전 기기 로그아웃).
        - `refreshToken` 을 **보내면**: 그 토큰(=그 기기 세션) 하나만 폐기.
        액세스 토큰은 만료 전까지 유효할 수 있으므로 클라이언트도 저장된 토큰을 삭제해야 한다.
        (AT 즉시 무효화는 `jti` 블랙리스트 도입 후 보장 — backend/TODO/refresh-token-redis.md)
      requestBody:
        required: false
        content:
          application/json:
            schema:
              type: object
              properties:
                refreshToken:
                  type: string
                  description: 생략 시 전 기기 로그아웃
      responses:
        '204': { description: 로그아웃됨(멱등 — 이미 폐기된 토큰이어도 204) }
        '401': { $ref: '#/components/responses/Unauthorized' }
```
동시에, RT 가 구현될 때까지는 계약이 거짓이 되지 않도록 `/auth/token/refresh`(openapi.yaml:85-105)와 위 로그아웃에 미구현 표식을 달아라:
```yaml
      x-implementation-status: not-implemented   # RefreshToken 엔티티/발급/폐기 전무. UserService.logout 은 빈 메서드
```
혹은 RT 도입 전이라면 summary 에서 '(refreshToken 폐기)' 문구를 지우는 것이 최소 수정이다.

---

## NEW-1 · `CONFIRMED`

**근거**

계약에는 refreshToken 을 **얻을 수 있는 경로가 사실상 없다**. AuthTokens 스키마는 openapi.yaml:785-791 에서 `accessToken/refreshToken/expiresIn/user` 를 정의하지만, 이를 반환하는 오퍼레이션은 `/auth/oauth/{provider}/callback`(L60-83, 200 → AuthTokens)과 `/auth/token/refresh`(L85-105, 200 → AuthTokens) 둘뿐이다. 그런데 주 로그인 경로인 `/auth/oauth/{provider}`(L45-58)는 302 리다이렉트이고 딥링크 형식이 L51 에 `heattrip://login-callback?token=<JWT>` 로 고정돼 있다 — **refreshToken 파라미터가 없다**. 실제 구현도 동일: OAuth/handler/OAuth2SuccessHandler.java:59 `String redirect = "heattrip://login-callback?token=" + token;`, 앱도 app/lib/features/auth/service/social_login_service.dart:32-33 에서 `token=` 하나만 파싱한다.

**정정 · 정확한 사실**

결과적으로 `/auth/token/refresh`(L85-105)는 `required: [refreshToken]` 인 입력을 요구하는데, 계약을 따르는 클라이언트가 그 값을 손에 넣을 실질적 경로가 302 딥링크 흐름에는 존재하지 않는다. 즉 리프레시 흐름이 계약 안에서 닫혀 있지 않다(unreachable operation). backend/TODO/refresh-token-redis.md 도 '`OAuth2SuccessHandler` 수정 ... 리다이렉트에 `&refresh=` 추가(프론트 파싱도 수정)'라고 이 구멍을 지적하고 있다.

**제안 수정**

302 딥링크 계약에 refresh 를 포함시키고 형식을 계약에 못박아라. openapi.yaml:50-52 의 description 과 L55-58 의 302 응답을 수정:
```yaml
      description: |
        인증 성공 시 백엔드가 앱 딥링크로 리다이렉트합니다:
        `heattrip://login-callback?token=<accessToken>&refresh=<refreshToken>&expiresIn=<초>`
      responses:
        '302':
          description: 공급자 로그인 페이지로 리다이렉트(최종 콜백은 앱 딥링크)
          headers:
            Location:
              schema: { type: string }
              example: "heattrip://login-callback?token=eyJhbGciOi...&refresh=8f3c...&expiresIn=1800"
```
토큰을 URL 쿼리로 흘리는 것 자체가 유출 위험이므로, 더 나은 계약은 딥링크에 **일회용 단기 code** 만 실어 보내고 앱이 `/auth/oauth/{provider}/callback`(L60-83)로 교환해 AuthTokens 를 받는 것이다. 이미 그 오퍼레이션이 존재하므로 302 경로를 그쪽으로 수렴시키면 `AuthTokens` 반환 지점이 한 곳으로 통일된다.

---

## NEW-2 · `CONFIRMED`

**근거**

`GET /auth/me` 의 200 스키마는 `#/components/schemas/User`(openapi.yaml:116)인데 User 스키마(openapi.yaml:793-798)는 다음 4개 필드뿐이다:
L794: `      type: object`
L795-798: `id`(int64), `provider`(enum [kakao, naver, google]), `nickname`, `isNew`(boolean).
반면 백엔드가 실제로 돌려주는 것은 user/dto/UserResponse.java:13-22 의 10개 필드 — `id, name, nickname, gender, age, email, travelType, imageUrl, createdAt, updatedAt` (AuthController.java:44 `ResponseEntity.ok(UserResponse.from(me))`).

**정정 · 정확한 사실**

교집합은 `id`, `nickname` 뿐이다. ① 계약의 `provider` 와 `isNew` 는 백엔드가 **전혀 반환하지 않는다**. ② 백엔드가 반환하는 `email, name, gender, age, travelType, imageUrl, createdAt, updatedAt` 8개는 **계약에 없다**. ③ 특히 `email` 이 User 스키마에 없는 것은 openapi.yaml:12 의 'subject = 사용자 email' 서술과 정면으로 어긋난다 — 계약상 클라이언트는 자기 email 을 알아낼 방법이 없다. ④ `provider` enum `[kakao, naver, google]` 에는 이메일/비밀번호 가입 사용자를 표현할 값이 없는데, 백엔드는 UserService.java:56-105 에서 이메일 가입을 정식 지원한다(`signup`/`login`). 즉 로컬 가입 사용자는 계약의 User 로 표현 불가능하다. ⑤ 계약의 `provider` 는 required 표기가 없어 nullable 처럼 보이지만 required 목록 자체가 스키마에 없어(L793-798 에 `required:` 없음) 모든 필드가 선택 — 스키마가 아무것도 보장하지 않는다.

**제안 수정**

User 스키마(openapi.yaml:793-798)를 실제 응답에 맞추고 required 를 명시하라:
```yaml
    User:
      type: object
      required: [id, email, nickname]
      properties:
        id: { type: integer, format: int64 }
        email: { type: string, format: email }
        provider:
          type: string
          enum: [local, kakao, naver, google]   # local = 이메일/비밀번호 가입
          description: 계정 출처
        name: { type: string }
        nickname: { type: string, example: "보리아빠" }
        gender: { type: string, enum: [MALE, FEMALE, OTHER] }
        age: { type: integer }
        travelType: { type: string, description: 현재 스키마는 단일 문자열 }
        imageUrl: { type: [string, "null"], format: uri }
        isNew: { type: boolean, description: 신규 가입이면 온보딩 유도 }
        createdAt: { type: string, format: date-time }
        updatedAt: { type: string, format: date-time }
```
`provider`/`isNew` 를 유지하려면 UserResponse.java:12-37 에 두 필드를 추가해야 하고, 반대로 유지하지 않을 거면 계약에서 지워라 — 지금처럼 양쪽에 서로 없는 필드를 남겨두면 계약이 검증 도구(Prism 목 서버, openapi.yaml:20 `http://localhost:4010`)에서 실서버와 다른 응답을 만들어낸다.

---

## NEW-3 · `CONFIRMED`

**근거**

계약은 소셜 로그인 시작 경로를 `/auth/oauth/{provider}`(openapi.yaml:45-58)로 규정하고, L52 에서 '(레거시 Spring Security OAuth2 `/oauth2/authorization/{provider}` 흐름 계승)'이라고 적었다. 그러나 ① 앱은 계약 경로를 쓰지 않고 레거시 경로를 그대로 호출한다 — app/lib/features/auth/service/social_login_service.dart:21 `final url = "$baseUrl/oauth2/authorization/$provider";`. ② 백엔드의 계약 경로 구현은 **빈 스텁**이다 — user/controller/AuthController.java:79-83:
```java
    @GetMapping("/oauth/{provider}")
    public ResponseEntity<Void> socialLogin() {
        return ResponseEntity.ok().build();
    }
```
즉 302 가 아니라 **200 을 반환**하고, `{provider}` 경로 변수를 받지도 않는다(파라미터 없음).

**정정 · 정확한 사실**

계약의 `/auth/oauth/{provider}` 는 아무도 호출하지 않는 죽은 계약이며, 존재하는 유일한 구현은 계약의 '302 리다이렉트'(openapi.yaml:56-58 `'302': description: 공급자 로그인 페이지로 리다이렉트`)를 위반하는 200 스텁이다. 실제로 동작하는 경로 `/oauth2/authorization/{provider}` 는 계약에 아예 등재돼 있지 않다 — C2 와 같은 종류의 누락이지만 별개 건이다. 또한 계약의 Provider enum 은 `[kakao, naver, google]`(openapi.yaml:706-710)로 3개인데 태그 설명(openapi.yaml:26-27)은 '소셜 로그인(카카오/네이버)'로 2개만 적어 문서 내부에서도 불일치한다.

**제안 수정**

둘 중 하나로 결정하고 계약을 그에 맞춰라. (A) 레거시 경로를 정식화 — openapi.yaml 에 실제 경로를 등재하고 `/auth/oauth/{provider}` 는 삭제하거나 deprecated 표시:
```yaml
  /oauth2/authorization/{provider}:
    get:
      tags: [Auth]
      summary: 소셜 로그인 시작(302 리다이렉트) — Spring Security 기본 경로
      security: []
      parameters:
        - $ref: '#/components/parameters/Provider'
      responses:
        '302':
          description: 공급자 로그인 페이지로 리다이렉트
          headers:
            Location: { schema: { type: string } }

  /auth/oauth/{provider}:
    get:
      deprecated: true
      tags: [Auth]
      summary: (미구현 스텁 — /oauth2/authorization/{provider} 사용) 
```
(B) 계약 경로로 수렴 — AuthController.java:79-83 을 `/oauth2/authorization/{provider}` 로 302 리다이렉트하는 실구현으로 바꾸고 social_login_service.dart:21 도 함께 변경. 어느 쪽이든 태그 설명 openapi.yaml:27 의 '(카카오/네이버)'를 Provider enum(L709 `[kakao, naver, google]`)과 일치시켜라.

---

## NEW-4 · `CONFIRMED`

**근거**

전역 `security: - bearerAuth: []`(openapi.yaml:40-41)가 걸려 있는데도 계약의 `info.description` 은 'MVP에선 읽기(장소 조회 등)는 비인증 허용'(openapi.yaml:13)이라고 선언한다. 그런데 `security: []` 로 인증을 면제한 오퍼레이션은 Auth 태그의 3개뿐이다 — L54(`/auth/oauth/{provider}`), L65(`/auth/oauth/{provider}/callback`), L89(`/auth/token/refresh`). 파일 전체에서 `      security: []` 는 이 3건이 전부다. 반면 Places 등 읽기 오퍼레이션에는 전부 `'401': { $ref: '#/components/responses/Unauthorized' }` 가 붙어 있다(예: L285, L300, L333, L375, L425 …).

**정정 · 정확한 사실**

계약 본문(paths)이 서술문(L13)을 구현하지 않았다. 장소 조회 같은 공개 읽기 오퍼레이션이 전역 bearerAuth 를 상속하므로, 계약대로 검증하면 비인증 읽기는 **불허**다. 서술문과 스펙이 충돌할 때 코드 생성기·Prism 목·계약 테스트가 따르는 것은 서술문이 아니라 paths 이므로, 이 상태에서는 '비인증 읽기' 요구사항이 어떤 자동 검증에도 잡히지 않는다.

**제안 수정**

공개 읽기 오퍼레이션마다 `security: []` 를 명시하고 불필요한 401 을 제거하라. 예를 들어 Places 조회 오퍼레이션에:
```yaml
      security: []          # MVP: 비인증 읽기 허용
      responses:
        '200': { ... }
        # '401' 제거 — 인증을 요구하지 않으므로
```
인증 여부에 따라 응답이 달라지는(예: 북마크 여부 포함) 오퍼레이션이라면 '선택적 인증'을 이렇게 표현하라:
```yaml
      security:
        - {}                # 비인증 허용
        - bearerAuth: []    # 토큰이 있으면 개인화 필드 포함
```
그리고 openapi.yaml:13 의 서술을 '아래 오퍼레이션의 `security` 선언이 정본이며 이 문장은 요약'이라고 명시해 충돌 시 우선순위를 못박아라.

---

## C4 · `PARTIAL`

**근거**

openapi.yaml:793-799 (User 스키마 전문)
```
793:    User:
794:      type: object
795:      properties:
796:        id: { type: integer, format: int64 }
797:        provider: { type: string, enum: [kakao, naver, google] }
798:        nickname: { type: string, example: "보리아빠" }
799:        isNew: { type: boolean, description: 신규 가입이면 온보딩 유도 }
```
openapi.yaml:707-710 (Provider 파라미터도 동일 enum)
```
707:      name: provider
710:      schema: { type: string, enum: [kakao, naver, google] }
```
계약 전체 path 목록 (openapi.yaml:45,60,85,107,125) — /auth/signup, /auth/login 자체가 없음:
```
45:  /auth/oauth/{provider}:
60:  /auth/oauth/{provider}/callback:
85:  /auth/token/refresh:
107:  /auth/me:
125:  /auth/logout:
```
실제 코드에는 이메일/비번 인증이 살아 있음:
backend .../user/controller/AuthController.java:25-33
```
25:    @PostMapping("/signup")
26:    public ResponseEntity<String> signup(@RequestBody SignupRequest request) {
31:    @PostMapping("/login")
32:    public ResponseEntity<String> login(@RequestBody LoginRequest request) throws IllegalAccessException {
```
backend .../user/entity/User.java:41-43
```
41:    @Column(unique = true)
42:    private String email; // 로그인용 id
43:    private String password; // 로그인용 비밀번호
```
app/lib/features/auth/data/auth_repository_impl.dart:22, 50
```
22:    final url = Uri.parse('$baseUrl/auth/login');
50:    final url = Uri.parse('$baseUrl/auth/signup');
```
설계 의도 기록: docs/04-api/api-spec.md:156 "감정앱의 이메일/비번 `/auth/signup`·`/auth/login`은 MVP에서 소셜 로그인으로 대체(스텁 유지)."

**정정 · 정확한 사실**

전반부(enum 사실관계)는 100% 맞다. openapi.yaml:797 의 enum 은 정확히 [kakao, naver, google] 이고 local/email/password 값이 없다.

그러나 후반부의 인과관계 두 가지가 부정확하다.

(1) "그래서(enum 때문에) 표현할 수 없다"는 틀렸다. User 스키마(793-799)에는 `required:` 목록이 아예 없어서 `provider` 를 포함한 모든 속성이 optional 이다. 따라서 `{"id":1,"nickname":"홍길동"}` 처럼 provider 를 생략한 로컬 사용자 페이로드는 지금 계약으로도 **스키마 검증을 통과한다**. 즉 "표현 불가"가 아니라 "명시적으로 구분 불가(암묵적 null 로만 표현 가능)"가 정확한 서술이다.

(2) 진짜 결함은 enum 이 아니라 **경로 자체의 부재**다. 계약에는 POST /auth/signup, POST /auth/login 이 존재하지 않는다(45-131 전 구간). enum 에 `local` 만 추가해도 이메일/비번 사용자는 여전히 계약상 생성될 경로가 없으므로 아무것도 해결되지 않는다.

(3) 추가로, 이 누락은 사고가 아니라 문서화된 의도다. api-spec.md:156 이 "이메일/비번 /auth/signup·/auth/login은 MVP에서 소셜 로그인으로 대체(스텁 유지)"라고 명시한다. 다만 AuthController.java:25,31 과 auth_repository_impl.dart:22,50 에서 두 엔드포인트가 여전히 **구현되어 있고 앱이 실제로 호출 중**이므로, 계약이 가동 중인 코드와 어긋난 상태인 것은 사실이다.

(4) 또한 backend User 엔티티(User.java)에는 `provider` 컬럼이 아예 없다. 소셜 사용자는 `username = "google_123456"` 형태 문자열로만 구분된다(CustomOAuth2UserService.java:139 `String username = userInfo.getProvider() + "_" + userInfo.getProviderId();`). 즉 계약의 `provider` 필드는 백엔드에 대응 데이터가 없다.

**제안 수정**

결정을 먼저 하고 두 갈래 중 하나를 택해야 한다.

[A] 이메일/비번을 계약에 포함(현재 코드 반영)하는 경우 — enum 추가만으로 부족하고 경로+스키마를 함께 넣어야 한다.
```yaml
# components/schemas/User
    User:
      type: object
      required: [id, provider]          # 필수 지정 없으면 무엇도 강제되지 않음
      properties:
        id: { type: integer, format: int64 }
        provider:
          type: string
          enum: [local, kakao, naver, google]
          description: local = 이메일/비밀번호 가입
        email: { type: string, format: email }
        nickname: { type: [string, "null"] }

# components/parameters/Provider 는 소셜 전용이므로 local 을 넣으면 안 된다(별도 유지)
    Provider:
      name: provider
      in: path
      required: true
      schema: { type: string, enum: [kakao, naver, google] }

# paths 에 추가
  /auth/signup:
    post:
      tags: [Auth]
      summary: 이메일/비밀번호 회원가입
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/SignupRequest' }
      responses:
        '201':
          description: 가입됨
          content:
            application/json:
              schema: { $ref: '#/components/schemas/AuthTokens' }
        '400': { $ref: '#/components/responses/ValidationError' }
        '409': { $ref: '#/components/responses/Conflict' }

  /auth/login:
    post:
      tags: [Auth]
      summary: 이메일/비밀번호 로그인
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [email, password]
              properties:
                email: { type: string, format: email }
                password: { type: string, format: password }
      responses:
        '200':
          description: 토큰 발급
          content:
            application/json:
              schema: { $ref: '#/components/schemas/AuthTokens' }
        '401': { $ref: '#/components/responses/Unauthorized' }
```
(SignupRequest 는 backend SignupRequest.java 의 email/password/nickname/name/gender/ageGroup/agreeTos/agreePrivacy/agreeMarketing/tosVersion/privacyVersion/marketingVersion 을 그대로 모델링할 것.)

[B] 소셜 전용으로 확정하는 경우 — enum 은 그대로 두되, api-spec.md:156 의 결정을 openapi.yaml 의 info.description 에 명시하고, AuthController.java:25,31 의 두 엔드포인트와 auth_repository_impl.dart:22,50 의 호출을 제거하는 후속 이슈를 만들어야 한다. 계약만 침묵하고 코드가 살아 있는 현 상태(= 계약 미기재 공개 엔드포인트)는 어느 쪽이든 결함이다.

---

## C5 · `PARTIAL`

**근거**

openapi.yaml:785-799 (AuthTokens 와 User 를 나란히)
```
785:    AuthTokens:
786:      type: object
787:      properties:
788:        accessToken: { type: string }
789:        refreshToken: { type: string }
790:        expiresIn: { type: integer, description: 초, example: 3600 }
791:        user: { $ref: '#/components/schemas/User' }
792:
793:    User:
794:      type: object
795:      properties:
796:        id: { type: integer, format: int64 }
797:        provider: { type: string, enum: [kakao, naver, google] }
798:        nickname: { type: string, example: "보리아빠" }
799:        isNew: { type: boolean, description: 신규 가입이면 온보딩 유도 }
```
openapi.yaml:107-117 (GET /auth/me 가 같은 User 를 재사용)
```
107:  /auth/me:
108:    get:
111:      responses:
112:        '200':
113:          description: 사용자
116:              schema: { $ref: '#/components/schemas/User' }
```
반증 근거 — 자매 문서의 GET /auth/me 예시는 isNew 를 아예 넣지 않는다. api-spec.md:145-153
```
147:{
148:  "id": 42,
149:  "provider": "kakao",
150:  "nickname": "보리아빠",
151:  "profileImage": "https://.../me.png",
152:  "createdAt": "2026-05-01T10:00:00+09:00"
153:}
```
반면 콜백 응답 예시에는 들어 있다. api-spec.md:117-128
```
120:  "user": {
121:    "id": 42,
122:    "provider": "kakao",
123:    "isNew": false
128:- `isNew=true` 면 프론트는 온보딩(강아지 프로필 등록)으로 유도.
```
프론트에서 isNew 소비처는 0건: `grep -rn "isNew" app/lib/` → 결과 없음.
백엔드 응답 DTO 에도 isNew 없음: backend .../user/dto/UserResponse.java:13-22 (id, name, nickname, gender, age, email, travelType, imageUrl, createdAt, updatedAt).

**정정 · 정확한 사실**

세 개 주장 중 두 개는 맞고 하나는 틀렸다.

(1) 위치 사실 — 맞다. isNew 는 openapi.yaml:799 의 User 에 있고 AuthTokens(785-791)에는 없다.

(2) 의미론 비판 — 타당하다. User 는 GET /auth/me 응답 스키마로도 재사용(116행)되므로, 로그인 이벤트 속성이 영속 프로필 표현에 섞여 들어간다.

(3) "그 결과 GET /auth/me 는 항상 isNew=false 를 반환해야 하는 이상한 상태가 된다" — **틀렸다.** User 스키마에는 `required:` 목록이 없어 isNew 를 포함한 모든 필드가 optional 이다. 서버는 /auth/me 에서 isNew 를 그냥 **생략**하면 되고, 그것이 계약 위반이 아니다. 실제로 자매 문서 api-spec.md:147-153 의 /auth/me 예시가 isNew 를 빼고 있어, "항상 false 를 강제한다"는 서술은 문서 자체에 의해 반증된다. 정확한 표현은 "/auth/me 응답에 의미 없는 optional 필드가 노출되고, 클라이언트가 그 유무/값을 신뢰할 근거가 계약에 없다" 이다.

(4) 주장이 놓친, 더 심각한 사실 — AuthTokens 로 옮겨도 현행 흐름에서는 isNew 가 클라이언트에 **도달하지 못한다.** 실제로 구현된 유일한 로그인 경로는 302 딥링크이며 access token 문자열 하나만 전달한다(openapi.yaml:51 `heattrip://login-callback?token=<JWT>`, OAuth2SuccessHandler.java:59 `String redirect = "heattrip://login-callback?token=" + token;`, social_login_service.dart:35 `Uri.parse(result).queryParameters['token']`). AuthTokens 를 반환하는 POST /auth/oauth/{provider}/callback(openapi.yaml:60)은 백엔드에 핸들러가 존재하지 않는다. 따라서 isNew 는 위치 문제 이전에 **전달 경로 자체가 없는 필드**다. 이것이 NEW-1 로 별도 보고된다.

**제안 수정**

isNew 를 User 에서 제거하고 로그인 응답 이벤트 필드로 승격한다. 동시에 User 에 required 를 명시해 optional 남용을 막는다.
```yaml
    AuthTokens:
      type: object
      required: [accessToken, expiresIn, user]
      properties:
        accessToken: { type: string }
        refreshToken: { type: string }
        expiresIn: { type: integer, description: 초, example: 3600 }
        isNew:
          type: boolean
          default: false
          description: >-
            이번 인증으로 계정이 새로 생성되었으면 true.
            로그인 응답 1회성 이벤트 속성이며 사용자 프로필의 영속 속성이 아니다.
            true 면 프론트는 온보딩(반려견 프로필 등록)으로 유도한다.
        user: { $ref: '#/components/schemas/User' }

    User:
      type: object
      required: [id, provider]
      properties:
        id: { type: integer, format: int64 }
        provider: { type: string, enum: [kakao, naver, google] }
        nickname: { type: [string, "null"] }
        # isNew 제거 — GET /auth/me 응답에서 사라지는 것이 정상
```
연쇄 수정 필수: api-spec.md:120-128 의 콜백 예시에서 `isNew` 를 `user` 블록 밖 최상위로 옮기고, 128행 설명문도 `AuthTokens.isNew` 를 가리키도록 고칠 것.
또한 NEW-1 을 함께 해결하지 않으면 이 수정만으로는 isNew 가 여전히 클라이언트에 도달하지 못한다.

---

## C6 · `CONFIRMED`

**근거**

openapi.yaml:24-26
```
24:tags:
25:  - name: Auth
26:    description: 소셜 로그인(카카오/네이버) · 토큰 · 내 정보
```
(cat -A 로 바이트 확인: `M-lM-^FM-^LM-lM-^EM-^\ M-kM-!M-^\M-jM-7M-8M-lM-^]M-8(M-lM-9M-4M-lM-9M-4M-lM-^XM-$/M-kM-^DM-$M-lM-^]M-4M-kM-2M-^D)` = "소셜 로그인(카카오/네이버)" — google 문자열 없음)

google 이 실제로 지원됨을 보이는 반대 증거:
openapi.yaml:710 `schema: { type: string, enum: [kakao, naver, google] }`
openapi.yaml:797 `provider: { type: string, enum: [kakao, naver, google] }`
backend .../OAuth/service/CustomOAuth2UserService.java:113-116
```
113:        switch (registrationId) {
114:            case "google":
115:                userInfo = new GoogleOAuth2User(attributes);
116:                break;
```
backend/src/main/resources/application-dev.properties:23-26 및 application-prod.properties:23-26
```
23:spring.security.oauth2.client.registration.google.client-id=${GOOGLE_CLIENT_ID:...}
26:spring.security.oauth2.client.registration.google.scope=email,profile
```
app/lib/features/auth/service/social_login_service.dart:10
```
10:  /// [provide]에는 'google', 'kakao', 'naver' 중 하나의 문자열이 들어갑니다.
```

naver 가 정당하게 지원됨을 보이는 증거:
CustomOAuth2UserService.java:122-124 `case "naver": userInfo = new NaverOAuth2User(attributes);`
application-dev.properties:41-51 (naver client-id / authorization-uri / token-uri / user-info-uri 전부 설정됨)

오기의 출처 추정 근거: api-spec.md:92 "카카오·네이버 OAuth 중심", api-spec.md:96 "`GET /auth/oauth/{provider}` — `provider ∈ {kakao, naver}`"

**정정 · 정확한 사실**

두 가지 사실 주장 모두 문자 그대로 맞다. 26행 description 은 정확히 "소셜 로그인(카카오/네이버) · 토큰 · 내 정보" 이고 google 이 빠져 있다.

다만 뉘앙스 한 가지를 바로잡는다. "naver 가 들어 있다"가 결함처럼 읽힐 수 있으나 naver 는 **정상**이다. Provider enum(710), CustomOAuth2UserService.java:122, application-dev/prod.properties:41-51 모두 naver 를 정식 지원한다. 결함은 오직 **google 누락 한 가지**다.

원인도 특정된다. 이 문구는 2-provider(kakao/naver) 시절 설계의 잔재다. api-spec.md:92,96 이 여전히 `provider ∈ {kakao, naver}` 로 남아 있고 tags 문구가 그것과 일치한다. 즉 openapi.yaml 의 enum 만 google 을 포함하도록 갱신되고 tags description 과 api-spec.md 는 갱신되지 않은, 부분 갱신 흔적이다. 따라서 26행만 고치면 반쪽 수정이고 api-spec.md:92,96 도 같이 고쳐야 한다(NEW-6).

영향도는 낮다(코드 생성/검증에 쓰이지 않는 표시용 문자열). 그러나 tags description 은 Swagger UI/Redoc 상단에 그대로 노출되므로 통합 담당자가 google 미지원으로 오독할 수 있다.

**제안 수정**

openapi.yaml:26 을 enum 과 동기화한다. provider 를 나열하는 방식은 enum 이 늘 때마다 또 어긋나므로, 열거를 지우고 참조 문구로 바꾸는 편이 재발 방지에 낫다.

최소 수정(열거 유지):
```yaml
tags:
  - name: Auth
    description: 소셜 로그인(카카오/네이버/구글) · 토큰 · 내 정보
```

권장 수정(열거 제거 — 드리프트 원천 차단):
```yaml
tags:
  - name: Auth
    description: >-
      소셜 로그인 · 토큰 발급/갱신 · 내 정보.
      지원 공급자는 `components.parameters.Provider` 의 enum 을 단일 출처로 한다.
```
동시 수정 필요:
- api-spec.md:96 `provider ∈ {kakao, naver}` → `provider ∈ {kakao, naver, google}`
- api-spec.md:92 "카카오·네이버 OAuth 중심" → "카카오·네이버·구글 OAuth 중심"

---

## NEW-1 · `CONFIRMED`

**근거**

실제로 구현된 유일한 로그인 흐름은 302 딥링크이고, 그 딥링크는 access token 문자열 하나만 싣는다.
openapi.yaml:45-59
```
45:  /auth/oauth/{provider}:
51:        인증 성공 시 백엔드가 앱 딥링크로 리다이렉트합니다: `heattrip://login-callback?token=<JWT>`.
57:        '302':
58:          description: 공급자 로그인 페이지로 리다이렉트
```
backend .../OAuth/handler/OAuth2SuccessHandler.java:57-61
```
57:         // 예: heattrip://login-callback?token=<access-token>
59:         String redirect = "heattrip://login-callback?token=" + token;
61:         response.sendRedirect(redirect);
```
app/lib/features/auth/service/social_login_service.dart:27-35
```
27:      final result = await FlutterWebAuth2.authenticate(
28:        url: url,
29:        callbackUrlScheme: "heattrip",
35:      final token = Uri.parse(result).queryParameters['token'];
```
반면 AuthTokens 를 반환하는 유일한 경로는 백엔드에 핸들러가 없다.
openapi.yaml:60-83 `/auth/oauth/{provider}/callback` → `grep -rn "callback" backend/src/main/java --include=*.java` 결과: OAuth2SuccessHandler.java:57,59 의 주석/문자열 2건뿐, `@PostMapping("/oauth/{provider}/callback")` 없음.

**정정 · 정확한 사실**

AuthTokens(openapi.yaml:785-791)의 refreshToken · expiresIn · user · (C5 수정 후의) isNew 는 **현행 시스템에서 클라이언트에 도달할 경로가 없다.** 유일하게 구현된 302 딥링크(OAuth2SuccessHandler.java:59)는 access token 문자열만 전달하고, AuthTokens 를 반환한다고 선언된 POST /auth/oauth/{provider}/callback(openapi.yaml:60)은 백엔드에 구현이 없다. 즉 계약이 정의한 인증 응답 모델 전체가 죽은 스펙이다.

추가로 openapi.yaml:57 은 이 경로의 응답으로 '302' 만 선언하지만, 백엔드 AuthController.java:79-83 의 실제 구현은 302 가 아니라 빈 200 을 돌려준다.
```
79:    @GetMapping("/oauth/{provider}")
80:    public ResponseEntity<Void> socialLogin() {
82:        return ResponseEntity.ok().build();
83:    }
```
실제 302 는 Spring Security 필터의 `/oauth2/authorization/{provider}` 가 처리하며, 앱도 그 경로를 호출한다(social_login_service.dart:21 `final url = "$baseUrl/oauth2/authorization/$provider";`). 계약이 선언한 /auth/oauth/{provider} 는 앱도 백엔드도 쓰지 않는 유령 경로다.

**제안 수정**

딥링크가 토큰 하나만 나르는 한 AuthTokens 는 의미가 없다. 둘 중 하나로 정리해야 한다.

[A] 딥링크에 one-time code 를 실어 보내고 교환 경로를 실제로 구현(권장 — 토큰이 URL/브라우저 히스토리에 남지 않는 이점도 있다):
```yaml
  /auth/oauth/{provider}:
    get:
      description: |
        성공 시 `heattrip://login-callback?code=<one-time-code>` 로 리다이렉트한다.
        앱은 이 code 를 POST /auth/oauth/exchange 로 교환해 AuthTokens 를 받는다.
        (토큰을 딥링크 쿼리에 직접 싣지 않는다.)
      responses:
        '302':
          description: 공급자 로그인 페이지로 리다이렉트
          headers:
            Location: { schema: { type: string } }

  /auth/oauth/exchange:
    post:
      tags: [Auth]
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [code]
              properties:
                code: { type: string }
      responses:
        '200':
          content:
            application/json:
              schema: { $ref: '#/components/schemas/AuthTokens' }
```

[B] 현행 구현을 그대로 계약화(빠른 정합화):
- /auth/oauth/{provider} 의 실제 경로가 `/oauth2/authorization/{provider}` 임을 path 로 반영하거나, 계약 경로를 백엔드에서 302 리다이렉트하도록 AuthController.java:79-83 을 고친다(현재는 빈 200 반환 → 계약 위반).
- 딥링크가 access token 만 나른다는 사실을 명시하고, AuthTokens 의 refreshToken/expiresIn/user 는 `POST /auth/oauth/{provider}/callback` 이 실제 구현될 때까지 계약에서 제거하거나 `deprecated: true` 또는 `x-status: planned` 로 표시한다.
어느 쪽이든 "구현 없는 경로가 200 으로 선언되어 있는" 현 상태는 목서버(Prism, openapi.yaml:19-20) 기준 통합 테스트를 통과시키면서 실서버에서는 실패시킨다.

---

## NEW-2 · `CONFIRMED`

**근거**

계약이 선언한 GET /auth/me 응답: openapi.yaml:112-117 → `schema: { $ref: '#/components/schemas/User' }` → openapi.yaml:796-799 의 4개 필드 (id, provider, nickname, isNew).

실제 구현 응답: backend .../user/controller/AuthController.java:39-45
```
39:    @GetMapping("/me")
40:    public ResponseEntity<UserResponse> me(@RequestHeader("Authorization") String authHeader) {
44:        return ResponseEntity.ok(UserResponse.from(me));
```
backend .../user/dto/UserResponse.java:13-22
```
13:    private Long id;
14:    private String name;
15:    private String nickname;
16:    private String gender;     // "FEMALE" / "MALE" / "OTHER"
17:    private Integer age;
18:    private String email;
19:    private String travelType; // 현재 스키마는 단일 문자열
20:    private String imageUrl;
21:    private LocalDateTime createdAt;
22:    private LocalDateTime updatedAt;
```
backend .../user/entity/User.java 에는 `provider` 컬럼이 존재하지 않음(34행 `private String username; // 소셜 로그인 식별자 (예: google_123456)` 로 대체).
소셜 가입 시 nickname 미설정: CustomOAuth2UserService.java:153-161 의 User.builder() 는 username/email/name/gender/travelType/createdAt/updatedAt 만 설정하며 `.nickname(...)` 호출이 없다(`grep -n "nickname" CustomOAuth2UserService.java` → 결과 없음).

계약 info 는 email 을 인증 주체로 명시: openapi.yaml:12 `- 인증: JWT Bearer. subject = 사용자 email.`

**정정 · 정확한 사실**

계약의 User(4필드)와 실제 GET /auth/me 응답(10필드)이 `id`, `nickname` 두 개에서만 겹친다.

- 계약에만 있고 백엔드에 없는 필드: `provider`(User 엔티티에 컬럼 자체가 없음), `isNew`(UserResponse 에 없음). 두 필드 모두 실제로는 절대 내려오지 않는다.
- 백엔드에만 있고 계약에 없는 필드: name, gender, age, **email**, travelType, imageUrl, createdAt, updatedAt (8개).
- 특히 `email` 누락은 자기모순이다. openapi.yaml:12 가 JWT subject 를 email 로 규정하고 User.java:42 가 email 을 로그인 ID(`@Column(unique = true)`)로 쓰는데, 사용자 표현 스키마에 email 이 없다.
- `nickname`(798행)은 소셜 가입 경로에서 한 번도 설정되지 않으므로(CustomOAuth2UserService.java:153-161) 소셜 사용자에게는 항상 null 이다. 그런데 계약은 `type: string` 으로 선언해 null 을 허용하지 않는다.
- 세 번째 문서인 api-spec.md:147-153 은 또 다른 형태(`profileImage`, `createdAt` 포함, isNew 제외)를 예시로 든다. 즉 같은 응답에 대해 서로 다른 3개 정의가 공존한다.

**제안 수정**

실제 UserResponse 를 단일 출처로 삼아 User 를 다시 쓴다. 계약에 없는 필드를 임의로 지우기보다, 내려오는 것을 먼저 정확히 적고 그 다음에 축소를 논의해야 한다.
```yaml
    User:
      type: object
      required: [id, email]
      properties:
        id: { type: integer, format: int64 }
        email: { type: string, format: email, description: JWT subject 와 동일 }
        name: { type: [string, "null"] }
        nickname:
          type: [string, "null"]
          description: 소셜 가입 경로에서는 설정되지 않아 null 일 수 있다
          example: "보리아빠"
        gender: { type: string, enum: [MALE, FEMALE, OTHER], default: OTHER }
        age: { type: [integer, "null"] }
        travelType: { type: [string, "null"] }
        imageUrl: { type: [string, "null"] }
        createdAt: { type: string, format: date-time }
        updatedAt: { type: string, format: date-time }
        provider:
          type: [string, "null"]
          enum: [kakao, naver, google, null]
          description: >-
            현재 백엔드 User 엔티티에 대응 컬럼이 없어 응답에 포함되지 않는다.
            제공하려면 users 테이블에 provider 컬럼을 추가하거나
            username("google_123456") 접두사에서 파생시켜야 한다.
```
후속 작업 2건이 따라붙는다.
1. `provider` 를 계약에 남기려면 backend User.java 에 컬럼 추가 + UserResponse.java 에 매핑 추가가 선행되어야 한다. 그렇지 않으면 다시 죽은 필드가 된다.
2. api-spec.md:147-153 의 예시를 위 스키마와 일치시킨다(`profileImage` → `imageUrl` 로 통일).

---

## NEW-3 · `CONFIRMED`

**근거**

계약은 refresh 토큰 체계를 전제한다.
openapi.yaml:789 `refreshToken: { type: string }`
openapi.yaml:85-105 `/auth/token/refresh` (requestBody required: [refreshToken], 200 → AuthTokens)
openapi.yaml:125-128
```
125:  /auth/logout:
126:    post:
128:      summary: 로그아웃(refreshToken 폐기)
```
백엔드에는 refresh 토큰이 전혀 없다.
backend .../OAuth/jwt/JWTProvider.java — `grep -n "Refresh\|refresh"` 결과 0건. 발급 메서드는 access 하나뿐:
```
44:    public String createAccessToken(String userId, String role) {
46:        Date expiry = new Date(now.getTime() + TOKEN_VALID_TIME);
```
backend .../user/service/UserService.java:89 (로그인도 access 만 반환)
```
89:        return jwtProvider.createAccessToken(user.getEmail(), "ROLE_USER");
```
AuthController.java 에 `/token/refresh` 매핑 없음(25 signup, 31 login, 39 GET /me, 48 PUT /me, 59 DELETE /me, 68 logout, 79 oauth 가 전부).
로그아웃 구현은 refreshToken 이 아니라 access token 의 email 로 동작: AuthController.java:72-74
```
72:        String authHeader = request.getHeader("Authorization");
73:        String email = userService.emailFromAuth(authHeader);
74:        userService.logout(email);
```

**정정 · 정확한 사실**

세 갈래 결함이 얽혀 있다.

(1) refreshToken 은 발급 주체가 없다. JWTProvider 에 createRefreshToken 이 없고 저장소/폐기 로직도 없다. 따라서 POST /auth/token/refresh(85-105)는 required 로 강제한 입력값을 클라이언트가 애초에 획득할 수 없는 엔드포인트다.

(2) /auth/logout(125-131) 은 summary 가 "refreshToken 폐기"라고 선언해 놓고 **requestBody 를 전혀 정의하지 않는다.** 어떤 refresh 토큰을 폐기할지 지정할 수단이 계약에 없다. 실제 구현(AuthController.java:72-74)은 Authorization 헤더의 access token 에서 email 을 뽑아 세션을 정리하는, summary 와 다른 동작이다. 또한 이 경로에는 '401' 응답이 선언되어 있지 않은데(129-131), 전역 `security: - bearerAuth: []`(openapi.yaml:41-42)를 상속하므로 401 이 발생할 수 있다.

(3) 같은 엔드포인트의 응답 형태를 두 문서가 다르게 정의한다. openapi.yaml:104 는 200 응답이 AuthTokens 전체(accessToken+refreshToken+expiresIn+user)라 하고, api-spec.md:137-138 은 `{ "accessToken": "...", "expiresIn": 3600 }` 두 필드뿐이라 한다. 회전(rotation) 여부가 문서마다 다르다는 뜻이라 보안상 모호하다.

**제안 수정**

refresh 를 도입할지 먼저 결정하고, 도입 전까지는 계약에서 planned 임을 못 박아야 한다.

[단기 — 정직한 계약]
```yaml
    AuthTokens:
      type: object
      required: [accessToken, expiresIn]
      properties:
        accessToken: { type: string }
        refreshToken:
          type: string
          description: "미구현(JWTProvider 에 발급 로직 없음). refresh 도입 전까지 응답에 포함되지 않는다."
        expiresIn: { type: integer, description: 초, example: 3600 }
        user: { $ref: '#/components/schemas/User' }

  /auth/token/refresh:
    post:
      x-status: planned            # 백엔드 미구현
      deprecated: false
      ...

  /auth/logout:
    post:
      tags: [Auth]
      summary: 로그아웃
      description: Authorization 헤더의 액세스 토큰으로 식별된 사용자의 세션을 종료한다.
      responses:
        '204': { description: 로그아웃됨 }
        '401': { $ref: '#/components/responses/Unauthorized' }   # 누락분 추가
```

[중기 — refresh 를 실제로 도입하는 경우]
- JWTProvider 에 createRefreshToken + 저장/폐기(테이블 또는 Redis) 추가.
- 회전 정책을 계약에 명시: 응답에 새 refreshToken 을 포함할지 여부를 openapi.yaml 과 api-spec.md:137-138 중 하나로 통일. 회전을 한다면 openapi 쪽(AuthTokens 전체 반환)이 맞고, api-spec.md 를 고쳐야 한다.
- /auth/logout 에 `requestBody: { refreshToken }` 를 추가하고 summary 대로 동작시키거나, summary 에서 "refreshToken 폐기"를 삭제하고 현행 동작을 기술한다. 둘 중 하나를 반드시 택할 것.

---

## NEW-4 · `CONFIRMED`

**근거**

계약이 선언한 /auth/me 의 메서드는 get 과 delete 뿐이다. openapi.yaml:107-123
```
107:  /auth/me:
108:    get:
110:      summary: 내 정보 조회
118:    delete:
120:      summary: 회원 탈퇴
121:      responses:
122:        '204': { description: 삭제됨 }
```
그러나 PUT /auth/me 가 구현되어 있고 앱이 호출한다.
backend .../user/controller/AuthController.java:47-56
```
47:    /** 내 프로필 수정 (부분 수정) */
48:    @PutMapping("/me")
49:    public ResponseEntity<UserResponse> updateMe(
50:            @RequestHeader("Authorization") String authHeader,
```
app/lib/features/auth/data/auth_repository_impl.dart:126
```
126:    final url = Uri.parse('$baseUrl/auth/me'); // PUT
```
같은 파일 22행(`/auth/login`), 50행(`/auth/signup`)도 계약에 없는 경로다.
계약 전체 path 목록(`grep -n "^  /" openapi.yaml`)에 /auth/signup, /auth/login 은 없다(45, 60, 85, 107, 125 가 Auth 의 전부).

**정정 · 정확한 사실**

Auth 태그에서 계약 미기재 상태로 가동 중인 엔드포인트가 3개다.
- POST /auth/signup — AuthController.java:25, 앱 호출 auth_repository_impl.dart:50
- POST /auth/login — AuthController.java:31, 앱 호출 auth_repository_impl.dart:22
- PUT /auth/me — AuthController.java:48, 앱 호출 auth_repository_impl.dart:126

반대로 계약에만 있고 구현이 없는 Auth 엔드포인트도 2개다.
- POST /auth/oauth/{provider}/callback (openapi.yaml:60) — 백엔드에 핸들러 없음
- POST /auth/token/refresh (openapi.yaml:85) — 백엔드에 핸들러 없음

design-first 를 표방하는 문서(openapi.yaml:7 "design-first(계약 우선)")로서, 계약과 구현이 Auth 영역에서 양방향으로 어긋나 있다. PUT /auth/me 누락은 특히 문제인데, api-spec.md:156 이 근거로 든 "소셜 로그인으로 대체" 논리가 프로필 수정에는 적용되지 않기 때문이다. 즉 signup/login 누락은 의도로 설명되지만 PUT /auth/me 누락은 단순 빠뜨림이다.

부수적으로 DELETE /auth/me(118-123)에는 '204' 와 '401' 만 선언되어 있는데, 구현(AuthController.java:59-64)이 `userService.emailFromAuth` → `findByEmail` 경유이므로 사용자 미존재 시 UserService.java:95-96 의 `IllegalArgumentException("사용자를 찾을 수 없습니다.")` 가 발생할 수 있다. 404 응답이 계약에 없다.

**제안 수정**

최소한 PUT /auth/me 는 즉시 계약에 추가해야 한다(signup/login 은 C4 의 [A]/[B] 결정에 종속).
```yaml
  /auth/me:
    get:
      tags: [Auth]
      summary: 내 정보 조회
      responses:
        '200':
          description: 사용자
          content:
            application/json:
              schema: { $ref: '#/components/schemas/User' }
        '401': { $ref: '#/components/responses/Unauthorized' }
    put:
      tags: [Auth]
      summary: 내 프로필 수정(부분 수정)
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/UpdateProfileRequest' }
      responses:
        '200':
          description: 수정됨
          content:
            application/json:
              schema: { $ref: '#/components/schemas/User' }
        '400': { $ref: '#/components/responses/ValidationError' }
        '401': { $ref: '#/components/responses/Unauthorized' }
        '404': { $ref: '#/components/responses/NotFound' }
    delete:
      tags: [Auth]
      summary: 회원 탈퇴
      responses:
        '204': { description: 삭제됨 }
        '401': { $ref: '#/components/responses/Unauthorized' }
        '404': { $ref: '#/components/responses/NotFound' }   # 누락분 추가
```
UpdateProfileRequest 스키마는 backend .../user/dto/UpdateProfileRequest.java 의 필드를 그대로 옮겨 정의할 것.
그리고 계약에만 존재하는 POST /auth/oauth/{provider}/callback(60행)·POST /auth/token/refresh(85행)에는 `x-status: planned` 를 달아, 목서버(openapi.yaml:19-20 Prism)로 통합 테스트하는 쪽이 구현 여부를 오판하지 않게 해야 한다.

---

## NEW-5 · `CONFIRMED`

**근거**

Auth 영역 전체 스키마에 `required:` 키워드가 단 한 번도 나타나지 않는다.
openapi.yaml:785-799
```
785:    AuthTokens:
786:      type: object
787:      properties:
788:        accessToken: { type: string }
789:        refreshToken: { type: string }
790:        expiresIn: { type: integer, description: 초, example: 3600 }
791:        user: { $ref: '#/components/schemas/User' }
792:
793:    User:
794:      type: object
795:      properties:
796:        id: { type: integer, format: int64 }
797:        provider: { type: string, enum: [kakao, naver, google] }
798:        nickname: { type: string, example: "보리아빠" }
799:        isNew: { type: boolean, description: 신규 가입이면 온보딩 유도 }
```
비교: 같은 파일의 요청 스키마들은 required 를 제대로 쓴다.
openapi.yaml:70 `required: [code]`, openapi.yaml:96 `required: [refreshToken]`, openapi.yaml:824 `required: [name, size]` (DogInput), openapi.yaml:750 `required: [code, message]` (Error.error).
서버 목록에 Prism 목서버가 등록되어 있어 이 스키마가 실제 검증/모킹에 쓰인다: openapi.yaml:19-20
```
19:  - url: http://localhost:4010
20:    description: Prism 목 서버 (design-first mock)
```

**정정 · 정확한 사실**

AuthTokens 와 User 는 응답 스키마인데도 required 가 전혀 없어, **모든 필드가 optional** 이다. 그 결과:

- `{}` 빈 객체가 유효한 AuthTokens 이고 유효한 User 다. accessToken 없는 로그인 응답, id 없는 사용자도 계약을 통과한다.
- Prism 목서버(19-20행) 기반 계약 테스트가 어떤 필드 누락도 잡아내지 못한다. design-first(7행)를 선언한 문서의 검증 기능이 Auth 영역에서 사실상 꺼져 있다.
- 코드 생성기(openapi-generator 등)가 Dart/Java 모델의 전 필드를 nullable 로 만들어, 프론트가 `accessToken!` 같은 강제 언랩을 쓰게 되고 런타임 오류로 밀려난다.
- C4 와 C5 의 "표현 불가"/"항상 false" 주장이 성립하지 않았던 근본 이유도 바로 이 required 부재다. 즉 이 항목은 앞의 두 주장이 겨냥한 문제보다 상위의 구조적 결함이다.
- 같은 파일 안에서 요청 스키마(70, 96, 824행)는 required 를 쓰고 응답 스키마만 안 쓰는 비일관성이 있어, 의도된 설계가 아니라 누락으로 보인다.

같은 문제가 Auth 밖에도 있다. Page(openapi.yaml:775-783)도 required 가 없어 items/nextCursor/hasMore 가 모두 optional 이며, 문서 서두(openapi.yaml:14)가 "목록은 커서 페이지네이션(items/nextCursor/hasMore)"이라고 규정한 것과 어긋난다.

**제안 수정**

응답 스키마에도 required 를 명시한다. 특히 클라이언트가 없으면 동작 불가한 필드는 반드시 넣는다.
```yaml
    AuthTokens:
      type: object
      required: [accessToken, expiresIn, user]
      properties:
        accessToken: { type: string }
        refreshToken: { type: string }
        expiresIn: { type: integer, description: 초, example: 3600 }
        user: { $ref: '#/components/schemas/User' }

    User:
      type: object
      required: [id, email]        # NEW-2 의 스키마 교체와 함께 적용
      properties:
        ...

    Page:
      type: object
      required: [items, hasMore]   # nextCursor 는 null 허용이므로 제외
      properties:
        items: { type: array, items: {} }
        nextCursor: { type: [string, "null"], example: "eyJpZCI6MTIzfQ==" }
        hasMore: { type: boolean }
```
추가로, null 이 실제로 내려올 수 있는 필드는 `type: [string, "null"]` 로 바꿔야 한다. 예: User.nickname 은 소셜 가입 시 설정되지 않으므로(CustomOAuth2UserService.java:153-161 에 .nickname() 호출 없음) 현재의 `type: string` 은 실서버 응답과 충돌한다.
검증 절차도 함께 도입할 것: CI 에서 Prism 또는 Spectral 로 openapi.yaml 을 린트하고, 응답 스키마에 required 가 없으면 실패시키는 규칙을 추가하면 재발을 막을 수 있다.

---

## NEW-6 · `CONFIRMED`

**근거**

같은 docs/04-api/ 안의 두 계약 문서가 서로 다른 값을 말한다.

(a) 지원 provider
openapi.yaml:710 `schema: { type: string, enum: [kakao, naver, google] }`
openapi.yaml:797 `provider: { type: string, enum: [kakao, naver, google] }`
api-spec.md:96 "`GET /auth/oauth/{provider}` — `provider ∈ {kakao, naver}`"
api-spec.md:92 "카카오·네이버 OAuth 중심(레거시 `kakao/`, `OAuth/` 패키지 계승)"
openapi.yaml:26 "description: 소셜 로그인(카카오/네이버) · 토큰 · 내 정보"

(b) 딥링크 스킴
openapi.yaml:51 "`heattrip://login-callback?token=<JWT>`"
openapi.yaml:76 `redirectUri: { type: string, example: "heattrip://login-callback" }`
api-spec.md:110 `{ "code": "authorization_code_from_provider", "redirectUri": "pawloop://auth" }`
api-spec.md:99 "| `redirect_uri` | 콜백 앱스킴 (예: `pawloop://auth`) |"
실제 앱 구현: social_login_service.dart:29 `callbackUrlScheme: "heattrip",`
실제 백엔드 구현: OAuth2SuccessHandler.java:59 `String redirect = "heattrip://login-callback?token=" + token;`

(c) /auth/token/refresh 응답 형태
openapi.yaml:100-104 → `schema: { $ref: '#/components/schemas/AuthTokens' }` (4필드)
api-spec.md:138 `{ "accessToken": "eyJhbGci...", "expiresIn": 3600 }` (2필드)

(d) /auth/me 응답 필드
openapi.yaml:796-799 → id, provider, nickname, isNew
api-spec.md:147-153 → id, provider, nickname, profileImage, createdAt (isNew 없음, profileImage/createdAt 추가)

(e) 제품명
openapi.yaml:3 `title: Pawloop API`, openapi.yaml:6 "Pawloop(포루프) — 반려동물 산책·동반장소·커뮤니티 앱의 REST API 계약."
openapi.yaml:17 `- url: https://api.heattrip.link`

**정정 · 정확한 사실**

docs/04-api/ 에 openapi.yaml 과 api-spec.md 두 개의 계약 문서가 있는데 어느 쪽이 단일 출처(source of truth)인지 선언되어 있지 않고, 최소 5개 지점에서 값이 충돌한다. C6 에서 지적된 tags 문구도 이 충돌군의 한 사례일 뿐이며, 26행만 고치면 api-spec.md:92,96 이 남아 다음 리뷰에서 같은 지적이 재발한다.

특히 (b) 딥링크 스킴은 실제 통합을 깨뜨릴 수 있는 항목이다. 코드는 양쪽 모두 `heattrip://` 를 쓰는데(social_login_service.dart:29, OAuth2SuccessHandler.java:59) api-spec.md:99,110 만 `pawloop://` 를 예시로 든다. api-spec.md 를 보고 구현하는 사람은 콜백을 받지 못한다.

(e) 는 리네임 진행 중임을 보여준다(openapi.yaml:18 "운영(예정 — 패키지/도메인 리네임 전까지 기존 유지)"). 즉 문서군이 heattrip→pawloop 전환 도중 부분 갱신된 상태이고, 위 충돌들은 대부분 그 전환의 잔재다.

**제안 수정**

1) 단일 출처를 openapi.yaml 로 못 박고 api-spec.md 를 파생 문서로 강등한다. api-spec.md 상단에 다음을 추가.
```markdown
> **단일 출처는 `openapi.yaml` 이다.** 이 문서는 사람이 읽기 위한 요약이며,
> 값이 충돌하면 항상 `openapi.yaml` 이 우선한다.
```

2) 충돌 5건을 openapi.yaml 기준으로 일괄 정정한다.
- api-spec.md:92 "카카오·네이버 OAuth 중심" → "카카오·네이버·구글 OAuth 중심"
- api-spec.md:96 `provider ∈ {kakao, naver}` → `provider ∈ {kakao, naver, google}`
- openapi.yaml:26 → C6 의 fix 적용
- api-spec.md:99, 110 의 `pawloop://auth` → `heattrip://login-callback` (코드 기준. social_login_service.dart:29 와 OAuth2SuccessHandler.java:59 가 실제 동작이므로 이쪽이 정답)
- api-spec.md:137-138 의 refresh 응답 → NEW-3 에서 회전 정책을 결정한 뒤 openapi.yaml:104 와 일치시킬 것
- api-spec.md:147-153 의 /auth/me 예시 → NEW-2 의 새 User 스키마와 일치시키고 `profileImage` 를 `imageUrl` 로 통일

3) 제품명 전환을 마무리하거나 상태를 명시한다. openapi.yaml:3 의 `title: Pawloop API` 와 openapi.yaml:17 의 `api.heattrip.link`, 그리고 딥링크 `heattrip://` 가 공존하는 상태를 info.description 에 한 줄로 기록해 두면 통합 담당자의 혼선을 줄일 수 있다.
```yaml
info:
  title: Pawloop API
  description: |
    ...
    - 리네임 진행 중: 제품명은 Pawloop, 도메인/딥링크 스킴은 당분간 heattrip 유지
      (`https://api.heattrip.link`, `heattrip://login-callback`).
```

4) 재발 방지: CI 에 openapi.yaml 린트를 추가하고, api-spec.md 의 코드블록 예시를 openapi.yaml 에서 생성하거나 최소한 두 문서 동시 수정을 PR 체크리스트에 넣을 것.

---

## C7 · `PARTIAL`

**근거**

openapi.yaml:16-22 — servers 목록은 정확히 3개다:
```
16: servers:
17:   - url: https://api.heattrip.link
18:     description: 운영(예정 — 패키지/도메인 리네임 전까지 기존 유지)
19:   - url: http://localhost:4010
20:     description: Prism 목 서버 (design-first mock)
21:   - url: http://10.0.2.2:8080
22:     description: 로컬 백엔드 (안드로이드 에뮬레이터 → 호스트)
```
grep 결과 파일 전체에서 `url:` 은 17/19/21 세 줄뿐이며 `localhost:8080` 은 0건 → "http://localhost:8080 이 없다"는 사실 확인.

실제 리디렉션 URI 가 servers 베이스에서 파생되는 것도 확인:
backend/src/main/resources/application-dev.properties:6 `app.base-url=${APP_BASE_URL:http://10.0.2.2:8080}`
backend/src/main/resources/application-dev.properties:25 `spring.security.oauth2.client.registration.google.redirect-uri=${app.base-url}/login/oauth2/code/google`
→ dev 기본값으로 실제 등록 필요 URI 는 `http://10.0.2.2:8080/login/oauth2/code/google` 이 되고, 이 값은 Google Cloud Console 이 거부한다.

주장을 약화시키는 반증들:
- app/lib/features/auth/presentation/login_screen.dart:277-284 — Google 로그인 버튼이 전부 주석 처리됨: `// iconPath: 'assets/icons/google.svg'`, `// onPressed: () => _handleSocialLogin('google')`. kakao(287-292), naver(295-)도 동일. 즉 "구글 로그인 개발 환경"은 현재 앱에서 활성 플로우가 아니다.
- openapi.yaml:26 `description: 소셜 로그인(카카오/네이버) · 토큰 · 내 정보` — 계약의 Auth 태그 설명은 google 을 범위 밖으로 적고 있다(반면 openapi.yaml:710 `enum: [kakao, naver, google]`).
- 실제 리디렉션 경로 `/login/oauth2/code/{provider}` 는 계약의 paths 에 단 한 줄도 없다(grep 0건). 문제는 servers 항목 하나가 아니라 리디렉션 표면 전체가 미문서화라는 점이다.
- docs/05-build/setup.md:145 `| CORS 허용 | APP_SECURITY_ALLOWED_ORIGINS | http://localhost:8080,http://10.0.2.2:8080 |` 와 docs/02-architecture/system-overview.md:129 는 `http://localhost:8080` 을 로컬 오리진으로 이미 문서화 → 같은 docs 세트 안에서 openapi.yaml 만 이 환경을 누락(주장 지지).

**정정 · 정확한 사실**

사실 부분(servers 3개, localhost:8080 부재)은 맞다. 그러나 근거로 든 규칙과 결론의 범위가 부정확하다.

1) "http://localhost 만 예외로 허용" — 틀렸다. Google 은 loopback 호스트에 대해 `http://localhost` 뿐 아니라 `http://127.0.0.1`(및 `[::1]`)도 http 로 허용한다. 또한 거부 사유는 "사설 IP라서"가 아니라 "https 가 아니면서 loopback 도 아닌 호스트"이기 때문이다(Web 클라이언트 리디렉션 URI 는 공인 TLD 도메인 또는 loopback 만 허용). 10.0.2.2 는 그 규칙에 걸리는 한 사례일 뿐이다.

2) "servers 에 http://localhost:8080 만 추가하면 된다"는 함의는 불완전하다. 안드로이드 에뮬레이터 안의 브라우저에서 `localhost` 는 에뮬레이터 자신을 가리키므로, `adb reverse tcp:8080 tcp:8080` 없이는 localhost:8080 베이스도 에뮬레이터에서 동작하지 않는다. 즉 servers 항목 추가만으로 구글 개발 환경이 표현되지 않는다.

3) 결함의 실체는 servers 목록이 아니라 리디렉션 URI 계약의 부재다. OpenAPI 의 servers 는 API 베이스 URL 선언이지 OAuth 리디렉션 URI 레지스트리가 아니다. 실제로 등록·검증이 필요한 값은 `${app.base-url}/login/oauth2/code/{provider}`(application-dev.properties:25/32/45)인데 이 경로 자체가 계약에 없다.

4) 심각도는 주장보다 낮다. login_screen.dart:277-284 에서 구글(및 카카오/네이버) 버튼이 주석 처리되어 있어 현재 앱에는 활성 구글 로그인 경로가 없다. 계약 문서 결함으로는 유효하나 "개발이 막힌다"는 수준은 아니다.

**제안 수정**

servers 에 localhost:8080 을 추가하되, 각 오리진이 어떤 공급자에 쓸 수 있는지와 에뮬레이터 제약을 description 에 명시하고, 미문서화된 리디렉션 수신 경로를 계약에 넣는다.

```yaml
servers:
  - url: https://api.heattrip.link
    description: 운영
  - url: http://localhost:4010
    description: Prism 목 서버 (design-first mock)
  - url: http://localhost:8080
    description: |
      로컬 백엔드 직접 접속. Google OAuth 개발 시 반드시 이 오리진을 사용한다.
      Google 승인 리디렉션 URI: http://localhost:8080/login/oauth2/code/google
      (Google 은 http 스킴을 loopback 호스트 localhost / 127.0.0.1 / [::1] 에만 허용)
      안드로이드 에뮬레이터에서 이 베이스를 쓰려면 `adb reverse tcp:8080 tcp:8080` 필요.
      대응 백엔드 설정: APP_BASE_URL=http://localhost:8080
  - url: http://10.0.2.2:8080
    description: |
      로컬 백엔드 (안드로이드 에뮬레이터 → 호스트). 카카오/네이버 전용.
      주의: 이 오리진은 Google 리디렉션 URI 로 등록 불가(https 아님 + loopback 아님).
```

리디렉션 수신 경로를 paths 에 명시(현재 계약에 없음):

```yaml
  /login/oauth2/code/{provider}:
    get:
      tags: [Auth]
      summary: 공급자 리디렉션 수신(Spring Security OAuth2 내부 콜백)
      description: |
        공급자에 등록해야 하는 승인 리디렉션 URI. 값은 `{server.url}/login/oauth2/code/{provider}`.
        성공 시 앱 딥링크 `heattrip://login-callback?token=<JWT>` 로 302.
      security: []
      parameters:
        - $ref: '#/components/parameters/Provider'
        - { name: code,  in: query, required: true, schema: { type: string } }
        - { name: state, in: query, schema: { type: string } }
      responses:
        '302': { description: 앱 딥링크로 리다이렉트 }
```

그리고 openapi.yaml:26 의 Auth 태그 설명을 `소셜 로그인(카카오/네이버/구글) · 토큰 · 내 정보` 로 고쳐 710줄의 `enum: [kakao, naver, google]` 과 일치시킨다.

---

## C8 · `PARTIAL`

**근거**

계약 사실은 확인된다.
openapi.yaml:40-41 —
```
40: security:
41:   - bearerAuth: []
```
openapi.yaml:53 `      security: []`  (/auth/oauth/{provider}, 45줄)
openapi.yaml:64 `      security: []`  (/auth/oauth/{provider}/callback, 60줄)
openapi.yaml:89 `      security: []`  (/auth/token/refresh, 85줄)
openapi.yaml:125-130 —
```
125:   /auth/logout:
126:     post:
127:       tags: [Auth]
128:       summary: 로그아웃(refreshToken 폐기)
129:       responses:
130:         '204': { description: 로그아웃됨 }
```
→ security 오버라이드 없음(전역 bearerAuth 상속), requestBody 없음. 여기까지는 주장대로다.

주장을 반증/수정하는 근거들:
1) "security: [] 한 것은 그 3개"는 문서 전역 기준으로 불완전하다. grep 결과 `security: []` 는 53, 64, 89 외에 210(/api/places/nearby), 247(/api/places/{contentId}), 340, 381(/api/community/posts), 398(/api/community/posts/{postId}) 에도 있다.

2) "모순"이라는 규정이 과하다. 백엔드 구현이 계약과 동일한 인터페이스다:
backend/.../user/controller/AuthController.java:68-75 —
```
68:     @PostMapping("/logout")
69:     public ResponseEntity<?> logout(HttpServletRequest request) {
72:         String authHeader = request.getHeader("Authorization");
73:         String email = userService.emailFromAuth(authHeader);
74:         userService.logout(email);
75:         return ResponseEntity.noContent().build();
```
액세스 토큰의 subject 로 서버측 세션을 폐기하는 revoke-all 형태이며, 이는 표준적인 설계다. 계약과 구현이 일치하므로 "모순"이 아니다.

3) "인증이 필요하다"는 계약 문서상으로만 참이다. 실제로는 전혀 강제되지 않는다:
backend/.../config/SecurityConfig.java:51-61 publicMatchers 에 `55: "/auth/**",` → `/auth/logout`, `/auth/me`(GET/DELETE) 전부 permitAll.

4) "폐기 대상 refreshToken" 자체가 백엔드에 존재하지 않는다. backend/src/main/java 전체 grep 에서 `refreshToken` 은 단 1건, 그것도 Swagger 설명 문자열이다: AuthApiDoc.java:15 `description = "저장된 refreshToken을 폐기해 더 이상 재발급되지 않게 합니다. "`. 그리고 UserService.java:162-165 —
```
162:     @Transactional
163:     public void logout(String email) {
164:         
165:     }
```
메서드 본문이 비어 있다(no-op).

5) 계약 내부 일관성 결함: /auth/logout(129-130)만 '401' 응답이 없다. 같은 인증 요구 오퍼레이션인 /auth/me GET(117 `'401': { $ref: ... }`), DELETE(123)는 모두 선언한다.

**정정 · 정확한 사실**

사실 관계(전역 bearerAuth, 3개 해제, /auth/logout 미해제 + refreshToken 미수신)는 맞다. 하지만 판정 근거인 "모순"은 틀렸고, 열거도 문서 전역 기준으로는 불완전하다.

- 정확한 사실 1: `security: []` 는 Auth 3개 외에 Places/Community 읽기 5곳(210, 247, 340, 381, 398)에도 있다. "이 3개만 해제"는 Auth 섹션 한정으로만 참이다.
- 정확한 사실 2: accessToken 인증 + 서버측 세션 일괄 폐기는 모순이 아니라 정상적인 all-devices logout 패턴이다. 백엔드 구현(AuthController.java:68-75)도 정확히 그 형태라 계약-구현 인터페이스는 일치한다.
- 실제 결함은 셋이다.
  (a) 명세 미달: summary(128줄) 는 "refreshToken 폐기"라고 특정 토큰을 지목하는데 그 토큰을 받는 파라미터가 없고, 단일 세션 폐기인지 전체 세션 폐기인지도 적혀 있지 않다. 클라이언트가 동작을 예측할 수 없다.
  (b) 응답 누락: 인증을 요구하면서 '401' 을 선언하지 않은 유일한 오퍼레이션이다(117/123과 비교).
  (c) 설계 공백: accessToken 이 이미 만료된 상태 — 로그아웃이 가장 필요한 상황 — 에서는 이 계약상 로그아웃을 호출할 방법이 전혀 없다. refreshToken 만으로 폐기하는 경로가 없다.
- 추가로, 계약이 말하는 인증 요구는 백엔드에서 무효다(SecurityConfig.java:55 `/auth/**` permitAll), 폐기 로직도 빈 메서드다(UserService.java:163-165). 즉 이 오퍼레이션은 계약·구현 양쪽에서 아무 것도 폐기하지 않는다.

**제안 수정**

refreshToken 을 선택 파라미터로 받아 단일/전체 세션 폐기를 명시하고, accessToken 만료 시에도 호출 가능하도록 security 를 optional 로 바꾸고, 401 을 추가한다.

```yaml
  /auth/logout:
    post:
      tags: [Auth]
      summary: 로그아웃(세션 폐기)
      description: |
        서버측 refreshToken 세션을 폐기한다.
        - `refreshToken` 을 보내면 해당 세션 하나만 폐기(단말 단위 로그아웃).
        - 생략하면 accessToken 의 subject 에 해당하는 **모든** 세션을 폐기(all-devices).
        accessToken 은 만료까지 서명상 유효하므로 클라이언트도 로컬 토큰을 반드시 삭제해야 한다.
        멱등: 이미 폐기된 세션에 대해서도 204 를 반환한다.
      security:
        - bearerAuth: []
        - {}   # accessToken 만료 시 refreshToken 만으로 폐기 허용
      requestBody:
        required: false
        content:
          application/json:
            schema:
              type: object
              properties:
                refreshToken:
                  type: string
                  description: 생략 시 해당 사용자의 모든 세션 폐기
      responses:
        '204': { description: 로그아웃됨(멱등) }
        '400': { $ref: '#/components/responses/ValidationError' }
        '401': { $ref: '#/components/responses/Unauthorized' }
```

주의: `security: [- bearerAuth: [], - {}]` 로 optional auth 를 만들 경우 "둘 다 없으면 400" 규칙을 description 에 명시해야 한다. 전체 세션 폐기만 지원할 거라면 반대로 requestBody 를 넣지 말고 summary 를 `로그아웃(해당 사용자의 모든 세션 폐기)` 로 고쳐 128줄의 "refreshToken 폐기" 표현을 제거하고 '401' 만 추가하면 된다. 어느 쪽이든 현재처럼 "refreshToken 폐기"라고 쓰면서 refreshToken 을 안 받는 상태는 유지하면 안 된다.

---

## NEW-1 · `CONFIRMED`

**근거**

계약이 정의한 소셜 로그인 시작 경로와 실제 클라이언트/서버가 3자 불일치.

계약: openapi.yaml:45-58 —
```
45:   /auth/oauth/{provider}:
46:     get:
48:       summary: 소셜 로그인 시작(302 리다이렉트)
52:         (레거시 Spring Security OAuth2 `/oauth2/authorization/{provider}` 흐름 계승)
57:         '302':
58:           description: 공급자 로그인 페이지로 리다이렉트
```

클라이언트는 계약 경로를 호출하지 않는다: app/lib/features/auth/service/social_login_service.dart:21 —
`      final url = "$baseUrl/oauth2/authorization/$provider";`

백엔드는 계약 경로를 302 가 아니라 200 빈 응답으로 구현: backend/.../user/controller/AuthController.java:79-83 —
```
79:     @GetMapping("/oauth/{provider}")
80:     public ResponseEntity<Void> socialLogin() {
82:         return ResponseEntity.ok().build();
83:     }
```
`{provider}` 를 @PathVariable 로 받지도 않는다.

그리고 실제로 동작하는 경로 `/oauth2/authorization/{provider}` 는 openapi.yaml paths 에 존재하지 않는다(grep 0건).

**정정 · 정확한 사실**

계약이 문서화한 `/auth/oauth/{provider}` 는 어느 쪽도 사용하지 않는 유령 엔드포인트다. 클라이언트가 실제로 여는 URL 은 `/oauth2/authorization/{provider}` 이고 이는 계약에 없다. 백엔드의 `/auth/oauth/{provider}` 는 302 가 아니라 200 을 반환하므로 계약의 응답 정의도 틀렸다. `security: []` 만 맞다.

**제안 수정**

실제 흐름을 계약으로 승격시키고, 죽은 엔드포인트를 정리한다.

```yaml
  /oauth2/authorization/{provider}:
    get:
      tags: [Auth]
      summary: 소셜 로그인 시작(302 리다이렉트) — Spring Security OAuth2 진입점
      description: |
        `flutter_web_auth_2` 가 여는 실제 URL. 공급자 인증 화면으로 302.
        성공 시 백엔드가 `heattrip://login-callback?token=<JWT>` 로 리다이렉트.
      security: []
      parameters:
        - $ref: '#/components/parameters/Provider'
      responses:
        '302':
          description: 공급자 로그인 페이지로 리다이렉트
          headers:
            Location: { schema: { type: string } }
```

`/auth/oauth/{provider}`(openapi.yaml:45-58)는 삭제하거나, 유지한다면 `deprecated: true` 를 붙이고 실제 응답인 `'200': { description: no-op }` 으로 고친다. 동시에 AuthController.java:79-83 의 no-op 핸들러도 제거 대상으로 표시한다.

---

## NEW-2 · `CONFIRMED`

**근거**

계약의 전역 인증 요구가 백엔드에서 통째로 무효화된다.

계약: openapi.yaml:40-41 `security:` / `  - bearerAuth: []` (전역), 그리고 /auth/me GET(107-117), DELETE(118-123), /auth/logout(125-130) 는 모두 오버라이드 없이 인증 필요로 선언.

백엔드: backend/.../config/SecurityConfig.java:51-61 —
```
51:         var publicMatchers = new ArrayList<>(List.of(
52:                 "/",
53:                 "/oauth2/**",
54:                 "/login/**",
55:                 "/auth/**",
```
그리고 SecurityConfig.java:74-77 `.requestMatchers(publicMatchers.toArray(String[]::new)).permitAll()`.

즉 `DELETE /auth/me`(회원 탈퇴, openapi.yaml:118-123)를 포함한 모든 `/auth/*` 가 필터 레벨에서 토큰 없이 통과한다. 컨트롤러가 `@RequestHeader("Authorization")`(AuthController.java:40, 49, 60) 로 직접 읽어 방어하는 형태라, 인증 실패는 401 이 아니라 헤더 누락/파싱 예외로 나타난다.

**정정 · 정확한 사실**

계약은 `/auth/me`, `/auth/logout` 에 bearerAuth 를 요구하지만 실제 서버는 `/auth/**` 전체를 permitAll 로 열어둔다. 특히 회원 탈퇴(DELETE /auth/me)가 Spring Security 인가 계층을 거치지 않는다. 계약의 보안 모델이 구현과 어긋난 상태이며, 401 응답 계약(openapi.yaml:117/123)도 실제로는 보장되지 않는다.

**제안 수정**

계약 쪽에서 할 일은 두 가지다.

1) 인증이 필요한 /auth 경로와 아닌 경로를 계약에 명시적으로 갈라두고(현재 상속에 의존), 각 오퍼레이션에 401 을 빠짐없이 선언한다. `/auth/logout` 에 누락된 401 추가는 C8 fix 참조.

2) 계약에 백엔드가 지켜야 할 인가 경계를 주석이 아니라 문서로 남긴다. 예를 들어 info.description 또는 Auth 태그 설명에 다음을 추가:

```yaml
tags:
  - name: Auth
    description: |
      소셜 로그인(카카오/네이버/구글) · 토큰 · 내 정보
      인가 경계: `/auth/oauth/**`, `/auth/token/refresh` 만 비인증 허용.
      `/auth/me`(GET/DELETE), `/auth/logout` 은 반드시 bearerAuth 검증 대상이어야 한다.
      (구현 참조: SecurityConfig 의 permitAll 목록에서 `/auth/**` 를
       `/auth/oauth/**`, `/auth/token/refresh` 로 좁힐 것)
```

계약 파일만으로는 강제할 수 없으므로, 이 경계를 검증하는 계약 테스트(무토큰 DELETE /auth/me → 401)를 CI 에 추가하는 것을 함께 이슈로 남긴다.

---

## NEW-3 · `CONFIRMED`

**근거**

계약의 토큰 갱신·폐기 모델 전체에 구현이 없다.

계약: openapi.yaml:85-105 `/auth/token/refresh` (requestBody required `refreshToken`, 200 → AuthTokens), openapi.yaml:786-791 AuthTokens 스키마 —
```
789:         refreshToken: { type: string }
```
(/auth/oauth/{provider}/callback 200 응답도 AuthTokens 참조: openapi.yaml:92)

백엔드: `grep -rn "refreshToken|refresh_token|RefreshToken" backend/src/main/java` 결과 단 1건이며 Swagger 설명 문자열이다 —
backend/.../user/controller/AuthApiDoc.java:15 `            description = "저장된 refreshToken을 폐기해 더 이상 재발급되지 않게 합니다. "`

폐기 로직도 빈 메서드: backend/.../user/service/UserService.java:161-165 —
```
161:     /** 사용자 로그아웃 */
162:     @Transactional
163:     public void logout(String email) {
164:         
165:     }
```

실제 로그인 응답도 토큰 객체가 아니라 문자열 하나다: AuthController.java:31-36 `public ResponseEntity<String> login(...)` → `ResponseEntity.ok(token)`. 클라이언트도 단일 JWT 만 저장한다: app/lib/features/auth/service/social_login_service.dart:35 `final token = Uri.parse(result).queryParameters['token'];`, token_provider.dart:17 `static const _jwtKey = 'jwt_token';` (refresh 키 없음).

**정정 · 정확한 사실**

`/auth/token/refresh`, `AuthTokens.refreshToken`, `/auth/logout` 의 "refreshToken 폐기"는 서버·클라이언트 어디에도 대응물이 없는 계약상의 허구다. 실제 시스템은 refresh 토큰 개념 없이 단일 JWT(jwt.expiration=3600000, application-dev.properties:20)만 쓴다. 계약대로 클라이언트를 구현하면 refreshToken 이 항상 null 이고 /auth/token/refresh 는 404 다.

**제안 수정**

둘 중 하나를 택하고 계약에 그 선택을 못박는다.

A) refresh 모델을 목표 상태로 유지할 경우 — 미구현임을 계약에 표시해 프론트가 성급히 의존하지 않게 한다.
```yaml
  /auth/token/refresh:
    post:
      tags: [Auth]
      summary: 액세스 토큰 갱신
      x-implementation-status: not-implemented   # 백엔드 미구현(2026-08 기준)
      description: |
        NOTE: 현재 백엔드는 refresh 토큰을 발급/저장하지 않는다.
        구현 전까지 클라이언트는 accessToken 만료 시 재로그인으로 처리한다.
```
그리고 AuthTokens 에서 refreshToken 을 optional 로 명시:
```yaml
    AuthTokens:
      type: object
      required: [accessToken, expiresIn]
      properties:
        accessToken: { type: string }
        refreshToken:
          type: string
          description: 미구현 — 현재 응답에 포함되지 않음
        expiresIn: { type: integer, example: 3600 }
```

B) 단일 JWT 모델을 확정할 경우 — `/auth/token/refresh`(85-105)를 계약에서 제거하고, AuthTokens 에서 refreshToken 을 삭제하며, `/auth/logout` summary(128)의 "refreshToken 폐기"를 "클라이언트 토큰 폐기(서버 무상태)"로 고친다. 이 경우 UserService.logout 의 빈 구현도 계약과 일치하게 된다.

---

## NEW-4 · `CONFIRMED`

**근거**

백엔드에서 실제로 동작하는 인증 엔드포인트 3개가 계약에 없다.

backend/.../user/controller/AuthController.java —
```
25:     @PostMapping("/signup")
26:     public ResponseEntity<String> signup(@RequestBody SignupRequest request) {
31:     @PostMapping("/login")
32:     public ResponseEntity<String> login(@RequestBody LoginRequest request) throws IllegalAccessException {
48:     public ResponseEntity<UserResponse> updateMe(
```
(48줄 updateMe 는 47줄 `@PutMapping("/me")`)

계약 openapi.yaml 의 Auth 섹션(44-130)에는 `/auth/signup`, `/auth/login` 이 없고, `/auth/me` 에는 get(108)과 delete(118)만 있을 뿐 put 이 없다. grep 으로 파일 전체에서 `signup`, `/auth/login` 0건.

또한 클라이언트에는 회원가입 화면이 존재한다: app/lib/features/auth/presentation/sign_up_screen.dart (git status 상 수정 중인 추적 파일).

**정정 · 정확한 사실**

계약은 소셜 로그인 + refresh 모델만 문서화하고, 실제로 구현되어 동작하는 이메일/비밀번호 가입·로그인(POST /auth/signup, POST /auth/login)과 프로필 수정(PUT /auth/me)을 전혀 다루지 않는다. 즉 계약이 문서화한 인증 경로는 미구현이고, 구현된 인증 경로는 미문서화라는 완전한 역전 상태다. 프론트에 sign_up_screen 이 있으므로 이 경로들은 죽은 코드가 아니다.

**제안 수정**

실제 동작하는 세 오퍼레이션을 계약에 추가한다. 응답 타입도 현재 구현(문자열 반환)을 그대로 쓰지 말고 AuthTokens/User 로 정규화할 것을 함께 명시한다.

```yaml
  /auth/signup:
    post:
      tags: [Auth]
      summary: 이메일 회원가입
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [email, password, nickname]
              properties:
                email:    { type: string, format: email }
                password: { type: string, format: password, minLength: 8 }
                nickname: { type: string }
      responses:
        '201': { description: 가입됨, content: { application/json: { schema: { $ref: '#/components/schemas/User' } } } }
        '409': { $ref: '#/components/responses/Conflict' }
        '400': { $ref: '#/components/responses/ValidationError' }

  /auth/login:
    post:
      tags: [Auth]
      summary: 이메일 로그인
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [email, password]
              properties:
                email:    { type: string, format: email }
                password: { type: string, format: password }
      responses:
        '200': { description: 토큰 발급, content: { application/json: { schema: { $ref: '#/components/schemas/AuthTokens' } } } }
        '401': { $ref: '#/components/responses/Unauthorized' }
```

`/auth/me` 에 put 을 추가:
```yaml
    put:
      tags: [Auth]
      summary: 내 프로필 수정(부분 수정)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                nickname: { type: string }
      responses:
        '200': { description: 수정됨, content: { application/json: { schema: { $ref: '#/components/schemas/User' } } } }
        '401': { $ref: '#/components/responses/Unauthorized' }
```

현재 AuthController.login 이 `ResponseEntity<String>` 으로 raw JWT 문자열을 반환하므로(31-36줄), 계약을 AuthTokens 로 잡으면 구현 변경이 필요하다. 이 차이를 이슈에 명시할 것.

---

## NEW-5 · `CONFIRMED`

**근거**

계약 내부 불일치 — google 이 범위에 있는지 문서가 스스로 상충한다.

openapi.yaml:25-26 —
```
25:   - name: Auth
26:     description: 소셜 로그인(카카오/네이버) · 토큰 · 내 정보
```
openapi.yaml:706-710 —
```
706:     Provider:
707:       name: provider
708:       in: path
709:       required: true
710:       schema: { type: string, enum: [kakao, naver, google] }
```
info.description(openapi.yaml:5-15)에도 공급자 목록은 없다.

백엔드는 google 을 설정한다: application-dev.properties:23-26 (`registration.google.client-id`, `.scope=email,profile`), application-prod.properties:23-26. 사용자 정보 매핑도 존재: backend/.../OAuth/user/GoogleOAuth2User.java.

앱에서는 google 버튼이 주석 처리: app/lib/features/auth/presentation/login_screen.dart:277-284.

**정정 · 정확한 사실**

Provider enum(710줄)은 google 을 허용값으로 선언하는데 Auth 태그 설명(26줄)은 카카오/네이버만 적는다. 계약 소비자(코드 생성기, Prism mock, 프론트 개발자)가 google 지원 여부를 계약만 보고 판단할 수 없다. 백엔드 설정과 GoogleOAuth2User 는 존재하므로 실제 범위는 google 포함이 맞고, 26줄 설명 쪽이 낡았다. 이는 C7 이 지적한 "구글 개발 환경 미표현" 문제의 계약 내부 근원이기도 하다.

**제안 수정**

태그 설명을 enum 과 일치시키고, 공급자별 리디렉션 제약을 한 곳에 모은다.

```yaml
tags:
  - name: Auth
    description: |
      소셜 로그인(카카오/네이버/구글) · 토큰 · 내 정보
      공급자별 리디렉션 URI 제약:
        - kakao / naver : http 오리진 허용 → http://10.0.2.2:8080 사용 가능
        - google        : http 는 loopback(localhost / 127.0.0.1)만 허용
                          → 개발 시 http://localhost:8080 + `adb reverse tcp:8080 tcp:8080`
```

반대로 google 을 MVP 범위에서 뺄 생각이라면 710줄 enum 을 `[kakao, naver]` 로 좁히고, backend 의 google registration(application-dev.properties:23-26)과 GoogleOAuth2User 도 범위 밖임을 이슈에 명시한다. 어느 쪽이든 26줄과 710줄이 서로 다른 이야기를 하는 상태는 해소해야 한다.

---

