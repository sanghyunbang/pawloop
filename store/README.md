# 스토어에 올리는 그래픽

App Store · 원스토어 등록 화면에 **사람이 직접 올리는** 파일입니다. 앱 바이너리에는 안 들어갑니다 — 앱 아이콘은 `app/assets/icons/` 의 원본 세 장에서 `flutter_launcher_icons` 가 만들어 냅니다.

## 왜 저장소에 두나

스토어는 반려되면 며칠이 날아갑니다. 그때 "그 스크린샷 어디 있더라" 를 다시 찾는 대신, 올린 것과 같은 파일이 여기 있어야 합니다. 재제출·업데이트·다른 기기에서 올릴 때 전부 여기를 봅니다.

## 무엇이 어디로

| 파일 | 올리는 곳 | 규격(실측) |
|:---|:---|:---|
| `android/play-listing/app-icon-512.png` | 원스토어 앱 아이콘 | 512×512 |
| `android/play-listing/feature-graphic-1024x500.png` | 피처 그래픽 | 1024×500 |
| `android/screenshots-phone/01~05.png` | 원스토어 스크린샷 | 1080×2340 |
| `ios/screenshots-6.7/01~05.png` | App Store 스크린샷 | 1290×2796 |
| `brand/*` | 보도자료·문서·웹 | 벡터(svg) + 1024 png |

App Store Connect 는 6.7인치 다섯 장으로 6.9·6.5인치까지 자동 대응합니다. iPad 를 지원하면 13인치 세트가 따로 필요합니다 — **지금은 없습니다.**

## 앱 아이콘은 여기서 올리지 않습니다

`ios/AppIcon.appiconset` 과 `android/adaptive-icon` 은 이 폴더에 **두지 않았습니다.** 그 둘은 원본 세 장으로 바뀌어 `app/assets/icons/` 에 들어갔고, 나머지는 명령 한 줄이 만듭니다.

```bash
cd app
flutter pub run flutter_launcher_icons
```

사본을 여기 또 두면 갈라지고, 갈라진 날 **앱에 박힌 아이콘과 스토어에 보이는 아이콘이 달라집니다.**

## 스플래시는 아직 안 붙였습니다

`android/splash/` · `ios/launch/` 의 파일은 들어 있지만 앱에 연결하지 않았습니다. 지금 스플래시는 예전 것이고, 바꾸려면 안드로이드는 `launch_background.xml`·Android 12 스플래시 API, iOS 는 `LaunchScreen.storyboard` 를 함께 고쳐야 합니다 — 배포를 막는 일이 아니라 뒤로 미뤘습니다.

## 브랜드 값

| | |
|:---|:---|
| 배경 | `#FFFFFF` |
| 강조 | `#E04A2B` (코랄레드) — **유일한 강조색** |
| 글자 | `#2B2825` |
| 카드 외곽선 | `#EDE6E1` |
| 서체 | 워드마크 Outfit 600 · 한글 Gothic A1 800 (둘 다 OFL) |

원본 묶음이 함께 온 설명은 `README.txt` 에 그대로 두었습니다.
