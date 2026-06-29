✅ 1. 패키지 이름 확인하는 방법 (Flutter 프로젝트)
Flutter는 안드로이드 네이티브 코드를 /android 폴더 안에 보관합니다.

🔍 확인 경로:

your_flutter_project/android/app/src/main/AndroidManifest.xml

📄 열어보면 이런 줄이 있습니다:

<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.yourapp">
✅ 여기서 package="com.example.yourapp" 부분이 패키지 이름이에요.
👉 이걸 복사해서 구글 콘솔의 패키지 이름에 붙여넣으면 됩니다.

**NOTE:** AndroidManifest.xml에 없는 경우가 있음. 그때는 build.gradle.kts에 들어가서 label을 찾으면 됨. 이후에

```
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.heattrip.heat_trip_flutter">

    <application
        android:label="heat_trip_flutter"
```
이런식으로 직접 package와 label을 입력해주면 됨.


✅ 2. SHA-1 지문이란? 왜 필요한가?
SHA-1 지문은 앱 서명 키의 해시값입니다.
구글은 이 지문을 통해 진짜 당신의 앱인지 확인합니다.
소셜 로그인(OAuth 2.0)을 Android에서 쓸 때 필수입니다.

✅ 3. SHA-1 지문 얻는 방법 (Flutter 프로젝트 기준)
Flutter는 Android 프로젝트를 포함하므로, Android 스튜디오나 keytool로 얻을 수 있어요.

방법 ①: Android Studio로 얻기 (추천)
Android Studio에서 /android 폴더 열기

왼쪽 Gradle 탭 클릭 → android > Tasks > android > signingReport 더블 클릭

아래 Run 창에 결과가 나옵니다.

🔍 예시 출력:
Variant: debug
SHA1: A1:B2:C3:D4:...:ZZ
복사해서 콘솔에 붙여넣으면 됩니다!

방법 ②: 명령어 (keytool) 사용
터미널에서 아래 명령어 실행 (Windows 기준)
keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android

📍 Mac/Linux이면:
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
SHA1 항목 찾아 복사하세요!

📌 요약
항목	Flutter에서 확인 방법
패키지 이름	/android/app/src/main/AndroidManifest.xml에서 package="..." 확인
SHA-1 지문	Android Studio → Gradle → signingReport 실행 or keytool 명령어

---

구글문서 요약 : https://developers.google.com/identity/protocols/oauth2/?hl=ko

내가 계획한 구성: Authorizaiton Code Flow

 - 프론트 엔드 : Flutter (모바일 앱)
 - 백엔드 : Spring Boot (서버)
 - Oauth 처리 : 로그인, 토큰 발급 등은 서버(SB)에서 처리

 관련한 구글 문서 : 웹 서버 애클리케이션용 AOuth 2.0 
 
 백엔드가 클라이언트 시크릿을 보관하고, OAuth 토큰을 직접 교환하고 저장하는 것과 관련한 문서

 ** 인증흐름 예시 **

 1. Flutter 앱에서 사용자가 Google 로그인 버튼을 클릭
 2. Flutter는 백엔드(Spring Boot)에 /oauth/login/google 같은 endpoint 요청
 3. Spring Boot가 Google OAuth 로그인 URL을 생성해, Flutter에 리디렉션(또는 WebView 열기)
 4. 사용자가 구글 계정 로그인 -> Google이 authorization code를 Spring Boot 서버에 전달
 5. Spring Boot 서버가 그 코드를 이용해 Google과 직접 통신하여 Access Token/ID Token 발급
 6. Spring Boot 서버가 자체 JWT 토큰을 만들어 Flutter에 발급(세션 관리)

🧠 용어 정리

| 용어                        | 의미                                                           |
| ------------------------- | ------------------------------------------------------------ |
| Authorization Code Flow   | 보안을 위해 서버가 구글과 직접 통신하여 토큰을 교환하는 방식                           |
| 클라이언트 시크릿 (client secret) | 앱이 직접 갖고 있으면 안 되는 민감 정보 → Flutter에 두면 위험                     |
| Implicit Flow             | 모바일 앱이 직접 로그인하고 토큰을 받는 방식 (Flutter에서 직접 하는 방식) → 지금은 사용 ❌ 안함 |
