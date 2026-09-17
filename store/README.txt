Pawloop — 스토어 배포용 그래픽 (A안)
생성일 2026-09-17

────────────────────────────────────────
브랜드 값
────────────────────────────────────────
배경        #FFFFFF
강조색      #E04A2B (코랄레드) — 유일한 강조색
글자색      #2B2825 (웜 차콜)
카드 외곽선 #EDE6E1
채움 버튼   #FF8F4D → #E04A2B 그라데이션 (버튼에만 사용)
서체        Pawloop 워드마크 = Outfit 600 / 한글 카피 = Gothic A1 800
            (둘 다 Google Fonts, OFL 라이선스)

────────────────────────────────────────
ios/
────────────────────────────────────────
AppIcon.appiconset/
  AppIcon-1024.png      1024×1024, 알파 없음 (App Store 요구사항)
  Contents.json         Xcode 에셋 카탈로그에 폴더째 끌어다 놓으면 됩니다
launch/
  Splash-1290x2796.png  전체 화면 스플래시 이미지
  pawloop-mark.png      투명 배경 심볼 120px (@2x 240 / @3x 360)
                        LaunchScreen.storyboard 에 마크를 가운데 배치하는 방식을
                        권장합니다. 기기 크기마다 잘리지 않습니다.
screenshots-6.7/
  01-map / 02-home / 03-walk / 04-family / 05-community
  1290×2796, 알파 없음. App Store Connect 는 6.7인치 5장으로 6.9/6.5인치까지
  자동 대응합니다. iPad 를 지원한다면 iPad 13인치 세트가 별도로 필요합니다.

────────────────────────────────────────
android/
────────────────────────────────────────
play-listing/
  app-icon-512.png              512×512 32비트 PNG (Play 콘솔 앱 아이콘)
  feature-graphic-1024x500.png  1024×500 (피처 그래픽)
adaptive-icon/
  ic_launcher_background.png    1024 원본 (배경 레이어, 단색 코랄)
  ic_launcher_foreground.png    1024 원본 (전경 레이어, 투명 배경)
  mipmap-mdpi ~ mipmap-xxxhdpi  108 / 162 / 216 / 324 / 432 px 로 리사이즈된 두 레이어
  mipmap-anydpi-v26/            ic_launcher.xml, ic_launcher_round.xml
  → mipmap-* 폴더들을 app/src/main/res/ 아래에 그대로 복사하면 됩니다.
  → 전경 마크는 안전영역(66%, 지름 676px) 안에 들어가 있어 어떤 마스크로 잘려도
    잘리지 않습니다.
splash/
  splash-1080x2340.png             전체 화면 스플래시
  android12-splash-icon-1152.png   Android 12+ 스플래시 API 용
                                   (1152 캔버스, 아트 768 안쪽, 투명 배경)
                                   windowSplashScreenBackground 는 #FFFFFF 로.
screenshots-phone/
  01~05, 1080×2340. Play 는 최소 2장, 최대 8장을 받습니다.

────────────────────────────────────────
brand/
────────────────────────────────────────
symbol-coral.svg / symbol-white.svg   심볼 벡터 (크기 무제한)
symbol-coral.png                      투명 배경 1024px
wordmark-horizontal.png               가로형 워드마크 (코랄 심볼 + 차콜 글자)
wordmark-horizontal-mono.png          단색 차콜 — 인쇄·흑백 문서용
wordmark-horizontal-white.png         반전 — 코랄/어두운 바탕용

워드마크는 글자가 포함되어 PNG 로만 들어 있습니다. 벡터 워드마크가 필요하면
Outfit 600 으로 "Pawloop" 을 조판하고 자간 -0.03em 을 준 뒤 심볼을 글자 높이의
약 1.27배로 왼쪽에 두면 동일한 락업이 나옵니다.

────────────────────────────────────────
아직 없는 것
────────────────────────────────────────
· iPad / 태블릿 스크린샷
· App Store 프로모션 텍스트·설명·키워드 등 텍스트 메타데이터
· 다크모드 대응 아이콘 (iOS 18 의 다크·틴티드 아이콘 변형)
필요하시면 같은 규칙으로 이어서 만들어 드립니다.
