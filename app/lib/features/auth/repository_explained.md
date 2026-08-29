| 폴더              | 역할                           |
| --------------- | ---------------------------- |
| `data/`         | 실제 데이터 통신/처리 (API 호출 등)      |
| `domain/`       | 핵심 비즈니스 로직 계층, 인터페이스 및 모델 정의 |
| `presentation/` | UI 화면 구성                     |
| `service/`      | 인증 흐름, 로그인/로그아웃 기능 통합 관리     |

> 인증 **상태**(누가 로그인해 있는가)는 이 폴더가 아니라 `lib/v2/data/auth_state.dart`
> 가 들고 있고, 그 상태를 보고 화면을 고르는 것은 `lib/app/auth_redirect.dart` 다 (#12).
> `service/` 안에 그 일을 하는 것처럼 보이던 파일이 두 개(초기 진입 판단용 위젯,
> 로그아웃 헬퍼) 있었지만 **어디서도 호출되지 않던 죽은 코드**여서 #12 에서 삭제했다.
> 이름만 보고 손대면 시간을 버리는 종류였다.


lib/
└── auth/
    ├── presentation/
    │   ├── login_screen.dart              // 자체 로그인 UI
    │   ├── register_screen.dart ✨         // 회원가입 UI
    │   ├── widgets/
    │   │   └── social_login_button.dart   // 소셜 로그인 버튼 UI
    ├── service/
    │   ├── oauth_callback.dart            // 콜백 딥링크 파싱 (순수 함수)
    │   ├── social_login_service.dart      // 소셜 로그인 전용
    │   ├── secure_token_store.dart        // OS 보안 저장소 (#8)
    │   ├── token_storage.dart             // 위 저장소로 가는 얇은 위임 래퍼
    │   └── auth_service.dart ✨            // 자체 로그인/회원가입 API 호출 로직
    ├── data/
    │   ├── dto/
    │   │   ├── login_request.dart ✨
    │   │   └── register_request.dart ✨
    │   └── repository/auth_repository_impl.dart ✨
    └── domain/
        └── repository/auth_repository.dart ✨

