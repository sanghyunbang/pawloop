// lib/v2/screens/settings/permission_notice_screen.dart
//
// 기기 접근권한 안내 — 이슈 #682.
//
// ## 법이 요구하는 화면이다
//
// **정보통신망 이용촉진 및 정보보호 등에 관한 법률 제22조의2 제1항**은, 앱이 이용자
// 단말기 안의 정보나 기능에 접근하려면 **접근권한이 필요한 항목**과 **그 이유**를 알리고,
// 서비스 제공에 반드시 필요하지는 않은 항목은 **따로 구분해서** 알리되 그 항목에는
// **동의하지 않아도 서비스를 이용할 수 있다는 사실**까지 알리도록 정한다. 그래서 이 화면은
// 목록을 필수와 선택 둘로 나누고, 선택 절에 그 문장을 [optionalNotice] 로 박아 둔다.
//
// 원스토어 대한민국 준수 정책도 같은 것을 본다 — 심사가 여는 것이 이 화면이다.
//
// 이 화면을 만들기 전까지 저장소 소스 전체에 '접근권한' 이 **한 건도 없었다**(#682).
//
// ## 목록을 어디서 가져왔나 — 지어내지 않았다
//
// 항목은 우리가 실제로 선언한 것뿐이다. 두 파일을 읽어서 옮겼다:
//
//  - `android/app/src/main/AndroidManifest.xml` 의 `uses-permission`
//  - `ios/Runner/Info.plist` 의 `NS...UsageDescription` 키들
//
// 그래서 각 항목이 [AppPermission.android] · [AppPermission.ios] 로 **자기 근거를 들고
// 있다.** `permission_notice_test.dart` 가 그 두 파일을 다시 읽어 빠진 것이 없는지 본다 —
// 매니페스트에 권한을 하나 더 얹고 이 화면을 잊으면 그 검사가 빨간불이다. 고지 화면은
// 한 번 쓰고 잊히기 쉬운 종류라, 사람 기억이 아니라 검사가 붙들고 있어야 한다.
//
// 선언은 했는데 고지하지 않는 것도 있다. 그것은 [kNotNoticedPermissions] 에 **이유와
// 함께** 적는다. 목록에서 그냥 지우면 대조 검사가 "선언에는 있고 고지에는 없다" 를 더는
// 못 잡고, 다음 사람이 새 권한을 얹고 고지를 잊어도 조용해진다. 일부러 뺀 것과 실수로
// 빠진 것은 구별돼야 한다.
//
// ## 필수와 선택을 무엇으로 갈랐나 — 코드가 실제로 구는 대로다
//
// **위치가 선택에 있는 것이 이 화면에서 가장 중요한 판단이다.** 앱의 본체는 산책 기록이고
// 위치 없이는 그것을 못 한다. 그런데도 선택인 이유는, 법이 가르는 기준이 "중요한
// 기능인가" 가 아니라 **"그 권한 없이 서비스를 이용할 수 있는가"** 이고, 코드를 읽어 보면
// 이용할 수 있기 때문이다:
//
//  - 라우터(`app_router.dart`)는 위치 권한을 보지 않는다. 붙잡는 것은 로그인·동의·소개뿐이다.
//  - 홈의 산책 안전 카드(`walk_safety_card.dart`)는 권한이 없으면 카드 대신 "허용" 한 줄을
//    그리고 화면은 그대로 산다.
//  - 산책 추적 화면(`walk_tracking_screen.dart:1324~`)은 거부 이유별로 안내와 버튼을 준다.
//  - 커뮤니티·채팅·일정·케어는 위치를 아예 부르지 않는다.
//
// 즉 위치를 거부한 사람도 앱을 쓴다 — 산책 기록과 주변 찾기를 못 쓸 뿐이다. 그러면 그것은
// 법이 말하는 선택적 접근권한이고, **"동의하지 않아도 쓸 수 있다" 고 말해야 하는 쪽**이다.
// 여기서 필수로 적으면 사용자가 가진 자유를 실제보다 작게 알리는 것이 된다.
//
// 대신 그 사실을 숨기지도 않는다 — 위치 항목의 [AppPermission.ifDenied] 가 무엇을 못 쓰게
// 되는지 그대로 적고, 끝에 [kLocationIsNotTheTerms] 를 붙여 **가입할 때 받는 위치기반서비스
// 이용약관 동의와 이 권한은 다른 것**이라고 말한다. 짝이 되는 문장은
// `consent_screen.dart` 의 [ConsentScreen.locationPermissionNote] 다 — 이쪽은 권한 화면에서
// "약관과 별개" 라 말하고, 저쪽은 동의 화면에서 "권한은 따로 묻는다" 고 말한다. 두 화면이
// 서로를 가리키게 하는 것이 그 두 줄의 일이다.
//
// ## 인터넷·네트워크는 뺐다 — 애초에 고지 대상이 아니다 (2026-09-18)
//
// 처음 만들 때는 `INTERNET`·`ACCESS_NETWORK_STATE` 를 **유일한 필수 항목**으로 올렸다.
// 사장님이 실기기에서 보고 "그럼 이 앱에 꼭 필요한 건 인터넷뿐이냐" 고 물었다. 원문을
// 다시 읽어 보니 그 항목은 애초에 이 화면에 올 것이 아니었다.
//
// **시행령 제9조의2 제1항**이 동의를 받아야 하는 접근권한을 네 가지로 닫아 놨다 —
// ① 연락처·일정·영상·통신내용·바이오정보 등 이용자가 단말에 저장한 정보, ② 위치정보·
// 통신기록·인증정보·신체활동기록 등 이용 과정에서 자동으로 저장된 정보, ③ 단말 고유정보,
// ④ 촬영·음성인식·감지센서 등 입력 및 출력 기능. 조문이 "…필요한 경우로 한다" 로 닫혀
// 있으니 이 밖은 대상이 아니다. 인터넷 연결도 네트워크 상태도 넷 중 어디에도 없다.
//
// 같은 조 제2항제1호는 안드로이드·iOS 처럼 개별 선택이 되는 운영체제에서는 "접근권한이
// 설정된 정보와 기능에 최초로 접근할 때 이용자가 동의 여부를 선택하도록" 받으라고 한다.
// 설치할 때 자동으로 붙는 권한은 최초 접근에 고를 것이 없다. **고를 수 없는 것은 동의
// 대상이 아니다.** 같은 이유로 `WAKE_LOCK`·`FOREGROUND_SERVICE` 도 뺐다.
// `FOREGROUND_SERVICE_LOCATION` 은 위치 항목에 그대로 두고, 화면을 꺼도 경로가 이어진다는
// 사실을 위치의 이유 안에 적는다 — 법이 시켜서가 아니라 놀라지 않게 하려고 적는다.
//
// 뺀 것은 지우지 않고 [kNotNoticedPermissions] 에 이유와 함께 남겼다.
//
// 원문은 국가법령정보센터 오픈 API 로 받아 직접 읽었다(법 제22조의2 시행일 2026.9.11,
// 시행령 제9조의2 시행일 2026.7.7). 방송통신위원회 「스마트폰 앱 접근권한 개인정보보호
// 안내서」(2017.3) 도 같은 범위를 쓰고, 그 안내서가 든 예시에도 인터넷은 없다.
//
// ## 필수적 접근권한이 0개다 — 없다고 적는다
//
// 넷을 빼고 나면 필수 절이 빈다. 절을 통째로 지우면 "필수는 왜 안 적었나" 로 읽히므로
// [noEssentialNotice] 로 **없다고 말한다.** 카카오스토리가 지금도 스토어 설명에
// "1. 필수적 접근권한 (없음)" 이라고 그대로 적는 것과 같은 방식이다(2026-09-07 자 플레이
// 스토어 설명에서 확인했다).
//
// 화면 자체를 없애지는 않는다. 선택적 접근권한이 남아 있는 한 법 제22조의2 제1항제2호가
// 항목·이유·동의하지 않을 수 있다는 사실을 알리라고 한다.
//
// ## "필수" 라는 말이 두 화면에서 다른 뜻이었다
//
// 이 화면의 필수/선택은 **기기 권한**이고, `consent_screen.dart` 의 필수/선택은 **약관
// 동의**다. 같은 두 글자가 뜻이 달라서 사장님 눈에 모순으로 보였다. 안내서에도
// <주의> 상자로 "접근권한에 대한 동의는 해당 정보에 대한 수집 동의는 아니" 라고 갈라
// 놨다. 그래서 말을 겹치지 않게 바꿨다 — 이 화면은 안내서 용어 그대로 "필수적 접근권한 /
// 선택적 접근권한", 동의 화면은 "동의 필수 / 동의 선택". 제목도 "기기 접근권한 안내" 로
// 해서 무엇에 대한 화면인지 제목만 보고도 갈리게 했다.
//
// ## 첫 실행에 한 번 보여 준다
//
// 법은 **설치 시 또는 최초 실행 시** 알리라고 한다. 그 자리는 `intro_screen.dart` 가
// 끝나는 지점이다(소개는 로그인보다 앞이고 기기당 한 번이다). 거기서 [firstRun] 으로 열면
// 아래에 "확인했어요" 버튼이 붙고, 그 버튼을 눌러야 소개가 끝난다.
//
// 설정 > 앱 > 접근권한 안내 로도 언제든 다시 열 수 있다. 고지는 한 번 보고 사라지면
// 안 되는 종류라, 들어오는 길이 둘이다.
library;

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/aurora.dart';

/// 고지하는 접근권한 한 줄.
///
/// [android] 와 [ios] 는 **이 항목이 어느 선언에서 나왔는지**다. 화면에는 안 보이고,
/// `permission_notice_test.dart` 가 매니페스트·plist 와 맞대 보는 데 쓴다. 한쪽이 비어
/// 있는 것은 정상이다 — 안드로이드에만 있는 권한(알림 예약의 재부팅 수신)도, iOS 에만
/// 묻는 것(카메라)도 있다.
@immutable
class AppPermission {
  const AppPermission({
    required this.title,
    required this.icon,
    required this.why,
    required this.essential,
    this.ifDenied,
    this.android = const <String>[],
    this.ios = const <String>[],
  });

  /// 사용자가 OS 대화상자에서 보는 이름과 같은 말로 적는다.
  final String title;
  final IconData icon;

  /// 왜 필요한가. 법이 요구하는 것이 이 문장이다 — 기능 이름이 아니라 쓰임새를 적는다.
  final String why;

  /// 없으면 서비스를 이용할 수 없는가.
  final bool essential;

  /// 거부하면 무엇이 달라지는가. 선택 항목에서 한 줄 더 말할 것이 있을 때만 쓴다.
  final String? ifDenied;

  /// `AndroidManifest.xml` 의 `android.permission.*` 이름들.
  final List<String> android;

  /// `Info.plist` 의 `NS...UsageDescription` 키들.
  final List<String> ios;
}

/// 선언은 했지만 **일부러 고지하지 않는** 권한.
///
/// 이 목록이 있는 이유는 대조 검사다. 고지 목록에서 지우기만 하면 "선언에는 있는데
/// 고지에 없다" 를 검사가 더는 못 잡는다. 여기 적어 두면 검사는 **선언 = 고지 + 이 목록**
/// 을 양쪽으로 확인할 수 있고, 새 권한이 조용히 빠지는 것과 구별된다.
@immutable
class NotNoticedPermission {
  const NotNoticedPermission({required this.name, required this.why});

  /// `AndroidManifest.xml` · `Info.plist` 에 적힌 이름 그대로.
  final String name;

  /// 왜 고지 대상이 아닌가. **판단을 적는 자리다** — 비워 두면 다음 사람이 이 목록을
  /// "귀찮은 권한을 숨기는 곳" 으로 쓰게 된다.
  final String why;
}

/// 고지하지 않는 선언들. 근거는 파일 머리에 적었다(시행령 제9조의2 제1항 각 호).
const List<NotNoticedPermission> kNotNoticedPermissions = [
  NotNoticedPermission(
    name: 'android.permission.INTERNET',
    why: '시행령 제9조의2 제1항 각 호(단말에 저장한 정보·자동 저장된 정보·고유정보·'
        '입출력 기능) 어디에도 없다. 설치할 때 자동으로 붙어서 최초 접근 때 이용자가 '
        '고를 것도 없다 — 고를 수 없는 것은 동의 대상이 아니다.',
  ),
  NotNoticedPermission(
    name: 'android.permission.ACCESS_NETWORK_STATE',
    why: 'INTERNET 과 같다. 네트워크가 끊겼는지 보는 것뿐이고, 단말 안의 정보나 기능에 '
        '손대지 않는다.',
  ),
  NotNoticedPermission(
    name: 'android.permission.FOREGROUND_SERVICE',
    why: '산책 기록이 화면을 꺼도 이어지게 하는 실행 방식이다. 설치할 때 자동으로 붙고 '
        'OS 가 따로 묻지 않는다. 위치를 쓰는 쪽은 FOREGROUND_SERVICE_LOCATION 이고, '
        '그것은 위치 항목에 들어 있다 — 이용자가 고르는 것은 위치 권한 하나다.',
  ),
  NotNoticedPermission(
    name: 'android.permission.WAKE_LOCK',
    why: 'FOREGROUND_SERVICE 와 같다. 기록하는 동안 잠들지 않게 하는 것뿐이고 '
        '단말 안의 정보를 읽지 않는다.',
  ),
  NotNoticedPermission(
    name: 'android.permission.RECEIVE_BOOT_COMPLETED',
    why: '기기를 다시 켤 때 예약해 둔 알림을 다시 걸기 위한 신호다. 역시 설치할 때 '
        '자동으로 붙고 각 호 어디에도 없다. 이용자가 고르는 것은 알림 권한'
        '(POST_NOTIFICATIONS) 하나이고 그것은 고지 목록에 있다. '
        '— 이 한 건은 앞 단계 조사가 따로 판단해 주지 않았고, 위 셋과 같은 이유로 '
        '내가 뺐다.',
  ),
];

/// 두 화면이 같은 말을 다른 뜻으로 쓰던 것을 푸는 한 줄 — 여기 위치 항목에 붙인다.
///
/// 짝이 되는 문장은 `ConsentScreen.locationPermissionNote` 다. 한쪽만 고치면 다시
/// 어긋나므로 두 문장 다 검사가 붙들고 있다.
const String kLocationIsNotTheTerms = '가입할 때 동의하는 ‘위치기반서비스 이용약관’ 과 이 '
    '권한은 별개예요. 약관은 서비스를 쓰기 위한 동의고, 이 권한은 기기의 위치 기능을 '
    '켜는 허용이에요.';

/// 고지 목록. **여기가 정본이다** — 화면도 검사도 이 하나를 읽는다.
///
/// 지금은 전부 선택이다. 필수적 접근권한은 없다(파일 머리 참고).
const List<AppPermission> kAppPermissions = [
  AppPermission(
    title: '위치',
    icon: Icons.near_me_outlined,
    why: '산책 경로와 걸은 거리를 기록하고, 주변의 반려동반 장소·동물병원·산책로를 '
        '보여드려요. 화면을 꺼도 기록이 끊기지 않도록 산책하는 동안에는 알림 하나가 '
        '떠 있어요.',
    // 위에서 밝힌 판단이다 — 앱은 열리고, 못 쓰는 것은 두 기능이다.
    ifDenied: '거부해도 앱을 쓸 수 있어요. 커뮤니티·채팅·일정·케어는 그대로 쓰고, '
        '산책 경로 기록과 주변 찾기만 못 해요. 허용한 뒤에도 프로필의 '
        "'위치 정보 수집 일시 중단' 으로 언제든 멈출 수 있어요.\n\n"
        '$kLocationIsNotTheTerms',
    essential: false,
    android: [
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.FOREGROUND_SERVICE_LOCATION',
    ],
    ios: ['NSLocationWhenInUseUsageDescription'],
  ),
  AppPermission(
    title: '알림',
    icon: Icons.notifications_none_rounded,
    why: '저녁 산책 알림·일정 알림·주간 정리를 보내드려요. 설정에서 스위치를 켜는 '
        '순간에만 물어요. 기기를 다시 켜도 예약해 둔 알림이 살아 있도록 재부팅 '
        '신호를 함께 받아요.',
    ifDenied: '거부해도 앱을 쓸 수 있어요. 산책 기록도 그대로 이어지고, '
        '기록하는 동안 뜨는 알림만 안 보여요.',
    essential: false,
    android: ['android.permission.POST_NOTIFICATIONS'],
  ),
  AppPermission(
    title: '사진',
    icon: Icons.photo_library_outlined,
    why: '커뮤니티 글과 프로필에 붙일 사진을 기기에서 골라요. 올릴 때 사진에 붙어 있는 '
        '위치 정보는 지워요.',
    ifDenied: '거부해도 앱을 쓸 수 있어요. 글은 사진 없이 쓰면 돼요.',
    essential: false,
    ios: ['NSPhotoLibraryUsageDescription'],
  ),
  AppPermission(
    title: '카메라',
    icon: Icons.photo_camera_outlined,
    why: '산책하는 동안 사진을 찍어 그날 기록에 붙여요. 안드로이드에서는 기본 카메라 '
        '앱으로 찍어서 따로 묻지 않아요.',
    ifDenied: '거부해도 앱을 쓸 수 있어요. 갤러리에서 고른 사진을 붙이면 돼요.',
    essential: false,
    ios: ['NSCameraUsageDescription'],
  ),
  AppPermission(
    title: '사진 저장',
    icon: Icons.save_alt_rounded,
    why: '산책 경로를 그린 그림을 사진 앱에 저장할 때 써요. 사진을 읽지는 않아요. '
        '안드로이드 10 이상은 권한 없이 저장돼요.',
    ifDenied: '거부해도 앱을 쓸 수 있어요. 저장만 못 하고 기록은 앱 안에 남아요.',
    essential: false,
    android: ['android.permission.WRITE_EXTERNAL_STORAGE'],
    ios: ['NSPhotoLibraryAddUsageDescription'],
  ),
];

class PermissionNoticeScreen extends StatelessWidget {
  const PermissionNoticeScreen({super.key, this.firstRun = false, this.onAcknowledged});

  /// 첫 실행에 보여 주는 중인가. 아래에 "확인했어요" 버튼이 붙는다.
  final bool firstRun;

  /// 첫 실행일 때 그 버튼이 부르는 것. 안 주면 그냥 닫는다.
  final VoidCallback? onAcknowledged;

  /// 정보통신망법 제22조의2 제1항이 선택 항목에 대해 알리라고 한 사실.
  ///
  /// **문자열을 상수로 둔 것은 검사가 이 문장을 찾기 때문이다.** 화면 안에 직접 적어 두면
  /// 문구를 다듬다가 조용히 사라질 수 있다.
  static const String optionalNotice = '동의하지 않아도 앱을 쓸 수 있어요';

  static const String essentialNotice = '이 권한이 없으면 앱을 쓸 수 없어요';

  /// 필수적 접근권한이 하나도 없을 때 그 자리에 적는 말.
  ///
  /// **절을 지우는 대신 없다고 말한다.** 빈 자리는 "안 적었나" 로 읽히지만 "없어요" 는
  /// 그 자체로 정보다. 카카오스토리도 스토어 설명에 "필수적 접근권한 (없음)" 이라고 적는다.
  static const String noEssentialNotice = '없어요. 아래 권한은 하나도 허용하지 않아도 앱을 '
      '쓸 수 있고, 그 기능만 못 써요.';

  /// 이 화면이 무엇에 대한 것인지, 그리고 무엇이 아닌지.
  ///
  /// 안내서에도 <주의> 상자로 "접근권한에 대한 동의는 해당 정보에 대한 수집 동의는
  /// 아니" 라고 갈라 놨다. 그 경계를 화면에도 한 줄로 적는다.
  static const String boundaryNotice = '여기서 허용하는 것은 휴대폰의 기능과 정보예요. '
      '로그인한 뒤에 나오는 약관 동의와는 별개예요.';

  /// 절 제목. 방송통신위원회 안내서가 괄호로 정의한 말 그대로다 — 법은 "반드시 필요한
  /// 접근권한" 이라고 풀어 쓰고 이 낱말을 쓰지 않지만, 실제 앱들이 다 이 말을 쓴다.
  /// **동의 화면의 "동의 필수 / 동의 선택" 과 겹치지 않게** 골랐다.
  static const String essentialLabel = '필수적 접근권한';
  static const String optionalLabel = '선택적 접근권한';

  /// 설정에서 여는 줄의 이름. 설정 화면과 검사가 같은 말을 쓰게 한다.
  ///
  /// "기기" 를 앞에 붙인 것은 동의 화면과 제목부터 갈라 놓기 위해서다.
  static const String menuLabel = '기기 접근권한 안내';

  static List<AppPermission> get essentials =>
      kAppPermissions.where((p) => p.essential).toList();

  static List<AppPermission> get optionals =>
      kAppPermissions.where((p) => !p.essential).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      appBar: AppBar(
        title: const Text(menuLabel),
        backgroundColor: T.bgTop,
        elevation: 0,
        foregroundColor: T.textPrimary,
        // 첫 실행에는 뒤로 갈 곳이 없다 — 아래 버튼이 유일한 출구다.
        automaticallyImplyLeading: !firstRun,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                children: [
                  const _Lead(),
                  const SizedBox(height: 18),
                  // 지금은 필수가 비어 있다. 절을 지우지 않고 없다고 말한다.
                  _section(essentialLabel,
                      essentials.isEmpty ? noEssentialNotice : essentialNotice),
                  for (final p in essentials) _Item(permission: p),
                  const SizedBox(height: 18),
                  _section(optionalLabel, optionalNotice),
                  for (final p in optionals) _Item(permission: p),
                  const SizedBox(height: 18),
                  const _HowToTurnOff(),
                ],
              ),
            ),
            if (firstRun)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                child: SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(colors: [T.sigStart, T.sigEnd]),
                    ),
                    child: TextButton(
                      key: const Key('permission-notice-ack'),
                      onPressed: onAcknowledged ??
                          () => Navigator.of(context).maybePop(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('확인했어요',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _section(String label, String notice) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(notice,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: T.warmText)),
          ],
        ),
      );
}

class _Lead extends StatelessWidget {
  const _Lead();

  @override
  Widget build(BuildContext context) => const GlassCard(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('포루프가 기기에서 쓰는 것',
                style: TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
            SizedBox(height: 8),
            Text(
              '아래 항목 말고는 기기에서 아무것도 가져오지 않아요. 권한은 그 기능을 '
              '처음 쓰는 순간에 물어보고, 허용한 뒤에도 기기 설정에서 언제든 다시 끌 수 '
              '있어요.',
              style: TextStyle(fontSize: 13.5, height: 1.6, color: T.textSecondary),
            ),
            SizedBox(height: 10),
            // 두 화면의 경계. 이 줄이 없어서 같은 "필수" 가 다른 뜻으로 읽혔다.
            Text(
              PermissionNoticeScreen.boundaryNotice,
              style: TextStyle(fontSize: 13, height: 1.6, color: T.textMuted),
            ),
          ],
        ),
      );
}

class _Item extends StatelessWidget {
  const _Item({required this.permission});

  final AppPermission permission;

  @override
  Widget build(BuildContext context) {
    final denied = permission.ifDenied;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(permission.icon, size: 19, color: T.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(permission.title,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: T.textPrimary)),
              ),
              // 절 제목과 같은 말이다 — 동의 화면의 "동의 필수/동의 선택" 과 겹치지
              // 않게 "-적" 을 붙여 둔다.
              Text(permission.essential ? '필수적' : '선택적',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: permission.essential ? T.warmText : T.textMuted)),
            ]),
            const SizedBox(height: 8),
            Text(permission.why,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.6, color: T.textSecondary)),
            if (denied != null) ...[
              const SizedBox(height: 8),
              Text(denied,
                  style: const TextStyle(
                      fontSize: 13, height: 1.6, color: T.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 끄는 법. 법이 요구하는 것은 항목과 이유지만, 안내만 하고 되돌릴 길을 안 적으면
/// 사용자는 허용한 것을 어디서 거두는지 모른 채 남는다.
class _HowToTurnOff extends StatelessWidget {
  const _HowToTurnOff();

  @override
  Widget build(BuildContext context) => const GlassCard(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('언제든 끄는 법',
                style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
            SizedBox(height: 8),
            Text(
              '안드로이드는 설정 > 애플리케이션 > 포루프 > 권한, 아이폰은 설정 > 포루프 '
              '에서 항목마다 끌 수 있어요. 위치는 앱 안에서도 멈출 수 있어요 — '
              "프로필의 '위치 정보 수집 일시 중단' 을 켜면 돼요.",
              style: TextStyle(fontSize: 13.5, height: 1.6, color: T.textSecondary),
            ),
          ],
        ),
      );
}
