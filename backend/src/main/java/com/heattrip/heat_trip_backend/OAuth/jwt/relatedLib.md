## 📌 JJWT 및 JWTProvider 구성 요소 설명
JWTProvider 클래스에서 사용되는 주요 클래스, 타입, 어노테이션들을 정리한 문서입니다.

## 🔑 JWT 관련 클래스 및 메서드

### Claims (io.jsonwebtoken.Claims)
JWT의 Payload(본문)를 표현하는 객체.

내부적으로는 Map<String, Object>처럼 동작.

subject, exp, iat 같은 표준 클레임 외에 커스텀 클레임(role 등)도 저장 가능.

예를 들어 이런 토큰이 있다고 할 때:

```
{
  "sub": "abc123",
  "role": "ROLE_USER",
  "iat": 1693825700,
  "exp": 1693829300
}
```
JJWT의 parseClaimsJws(token).getBody()를 호출하면
→ 이 내용을 Claims 객체로 돌려줍니다.

```
Claims claims = parseClaims(token);
String userId = claims.getSubject();           // "abc123"
String role = claims.get("role", String.class); // "ROLE_USER"
```
### Key (java.security.Key)

- Key는 JJWT 라이브러리에서 서명(=암호화된 인증 마크)을 생성하거나 검증할 때 쓰는 핵심 객체입니다.

- 이 Key는 Keys.hmacShaKeyFor(secret.getBytes())를 통해 생성

- secret 문자열을 자동으로 암호화 키로 적절한 길이로 가공해줍니다.

- 내부적으로 javax.crypto.spec.SecretKeySpec 객체로 만들어져요.

🔁 그다음엔 이렇게 쓰입니다:

```
Jwts.builder()
    .setSubject("user123")
    .signWith(key, SignatureAlgorithm.HS256)
    .compact();
```
이때 signWith()는 key를 이용해서 실제로 토큰에 **서명(Signature)** 을 생성합니다.

### Jwts.builder()
JWT 생성을 위한 빌더 패턴 메서드.

.setSubject() / .claim() / .setIssuedAt() / .setExpiration() 등으로 JWT 내용을 구성.

.signWith()로 서명 키와 알고리즘 설정.

.compact()로 최종 JWT 문자열 생성.

### Jwts.parserBuilder()
JWT 파싱을 위한 빌더
 cf) 파싱 : JWT 문자열을 **payload의 내부 내용(Claims)** 로 바꿔주는 작업

.setSigningKey(key)로 서명 검증 키 설정.

.build().parseClaimsJws(token)으로 JWT 서명 검증 + payload 파싱 수행.

### ⚠️ 예외 처리 관련 클래스
**JwtException (io.jsonwebtoken.JwtException)**
- JJWT에서 발생할 수 있는 모든 예외의 최상위 클래스.

- JWT 위조, 만료, 형식 오류 등으로 발생.

**IllegalArgumentException**
- Java 표준 예외.

- null, 빈 문자열, 잘못된 인자가 메서드에 전달되었을 때 발생.

- JWT 토큰이 null인 경우를 처리하기 위해 catch 절에서 함께 사용.

### ⚙️ Spring 어노테이션 및 설정
@PostConstruct
스프링에서 Bean이 초기화된 후 자동 실행되는 메서드에 붙임.

여기서는 secret 값을 기반으로 Key 객체를 초기화하는 데 사용.

@Value("${jwt.secret}")
Spring의 프로퍼티 값을 주입하는 어노테이션.

application.properties 또는 환경 변수에서 jwt.secret 값을 가져옴.