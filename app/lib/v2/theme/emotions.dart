import 'package:flutter/material.dart';

/// 감정 6종 (design_refactor 핸드오프 EMO[] 그대로).
/// 인덱스 순서가 soothe 매핑과 일치하므로 바꾸지 말 것.
class Emotion {
  final String label;
  final String emoji;
  final Color c1;
  final Color c2;
  final String desc;
  const Emotion(this.label, this.emoji, this.c1, this.c2, this.desc);

  /// 140deg 그라데이션 (핸드오프 grad()).
  LinearGradient get grad => LinearGradient(
        begin: const Alignment(-0.8, -1),
        end: const Alignment(0.8, 1),
        colors: [c1, c2],
      );
}

const List<Emotion> kEmotions = [
  Emotion('기쁨', '😊', Color(0xFFFFD86E), Color(0xFFFF8F63), '햇살처럼 번지는 따뜻함'),
  Emotion('슬픔', '😢', Color(0xFF8FB6FF), Color(0xFF5B79F5), '천천히 흘려보내도 괜찮아요'),
  Emotion('불안', '😰', Color(0xFFBBA0FF), Color(0xFF7E68F0), '잠시 숨을 고르는 시간'),
  Emotion('분노', '😡', Color(0xFFFF9180), Color(0xFFFF566E), '뜨겁게 일렁이는 마음'),
  Emotion('평온', '😌', Color(0xFF7FE6CC), Color(0xFF33BFA6), '잔잔하게 가라앉은 하루'),
  Emotion('설렘', '✨', Color(0xFFFF9FCF), Color(0xFFCE7DF5), '두근거리며 설레는 순간'),
];

/// 감정의 세기 라벨.
const List<String> kLevels = ['아주 약함', '약함', '보통', '강함', '아주 강함'];

/// 현재 감정 → 추천(위로) 목표 감정. (핸드오프 SOOTHE)
const List<int> kSoothe = [5, 0, 4, 4, 4, 5];

/// 상황 미선택(빠른 위로) 시 감정별 일반 위로 문구. (핸드오프 GENERIC)
const List<String> kGenericComfort = [
  '좋은 기분은 나눌수록 커져요. 이 마음을 이어갈 곳으로 안내할게요.',
  '슬픔은 천천히 흘려보내도 괜찮아요. 오늘은 나에게 다정한 하루를 선물해요.',
  '잠시 숨을 고르면, 흔들리던 마음도 천천히 가라앉아요. 차분한 곳들을 모았어요.',
  '뜨거운 마음은 바람을 쐬면 한결 가벼워져요. 탁 트인 곳으로 안내할게요.',
  '지금의 평온이 오래 머물도록, 잔잔한 곳들을 골라봤어요.',
  '설렘이 가득한 날, 그 두근거림을 더해줄 곳으로 떠나봐요.',
];
