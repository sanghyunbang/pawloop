import 'package:flutter/foundation.dart';

/// 다이어리 변경 신호.
///
/// 기록 추가/수정/삭제 시 [notifyDiaryChanged]를 호출하면, 이 값을 구독하는
/// 화면(피드/나 등)이 keep-alive 상태라도 자동으로 새로고침합니다.
final ValueNotifier<int> diaryRevision = ValueNotifier<int>(0);

void notifyDiaryChanged() => diaryRevision.value++;
