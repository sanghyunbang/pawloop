import 'package:flutter/material.dart';
import 'mood.dart';

/// 무드별 표시 색상 (감정 캘린더·감정 지도 공통).
/// docs/04-data-coldstart-map.md §5의 색 가이드(평온=블루, 설렘=핑크, 기쁨=옐로 …)를 따름.
const Map<String, Color> _moodColors = {
  '기쁨': Color(0xFFFFC53D), // 옐로
  '슬픔': Color(0xFF6B8AFD), // 블루
  '불안': Color(0xFFB07CF0), // 퍼플
  '분노': Color(0xFFFB6A6A), // 레드
  '평온': Color(0xFF4EC8C0), // 틸
  '설렘': Color(0xFFFF8FB3), // 핑크
};

/// 무드 키(한글 SSOT) → 색. 미지정/미매칭이면 중립 회색.
Color moodColor(String? moodKey) {
  final m = Moods.byKey(moodKey);
  final key = m?.key ?? moodKey;
  return _moodColors[key] ?? const Color(0xFFD8D8DE);
}
