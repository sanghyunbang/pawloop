import 'package:flutter/material.dart';

/// "무엇이 마음을 움직였나요?" 상황 6종 (핸드오프 SITU). 조언·인사이트 포함.
class Situation {
  final IconData icon;
  final String label;
  final String tip;
  final String advice;
  final String insight;
  const Situation(this.icon, this.label, this.tip, this.advice, this.insight);
}

const List<Situation> kSituations = [
  Situation(
    Icons.work_outline,
    '취업·진로',
    '몸을 움직이는 산책',
    '취업은 떨어져도 끝이 아니라, 부족한 점을 발견하고 다시 다듬어가는 과정이에요. 오늘의 흔들림은 그만큼 진심이라는 증거예요.',
    '취업 고민을 겪은 1,240명 중 78%가 가볍게 몸을 움직인 뒤 마음이 한결 가벼워졌어요.',
  ),
  Situation(
    Icons.favorite_border,
    '연애·관계',
    '온기 있는 공간',
    '사람은 또 다른 사람을 통해 다시 치유받을 수 있어요. 좋은 인연은 준비된 마음에 찾아오니, 지금은 나를 다정히 돌보는 시간으로.',
    '관계로 마음 쓴 980명은 사람의 온기가 있는 공간에서 위로를 가장 많이 얻었어요.',
  ),
  Situation(
    Icons.business_center_outlined,
    '일·업무',
    '탁 트인 전망',
    '끝나지 않을 것 같은 일도 결국 지나가요. 잠시 화면에서 눈을 떼고, 시야를 넓혀줄 풍경 앞에 서보는 건 어때요.',
    '번아웃을 호소한 1,500명은 탁 트인 전망에서 가장 빠르게 회복했어요.',
  ),
  Situation(
    Icons.person_outline,
    '외로움',
    '느슨한 북적임',
    '혼자라는 느낌이 들 때일수록, 느슨하게 사람들 사이에 머무는 것만으로 마음이 데워져요.',
    '외로움을 적은 사람들의 64%가 적당히 북적이는 카페·서점에서 위안을 찾았어요.',
  ),
  Situation(
    Icons.spa_outlined,
    '번아웃',
    '물가·숲',
    '몸과 마음이 보내는 신호예요. 무리하지 말고, 천천히 숨을 고를 수 있는 곳으로 떠나봐요.',
    '비슷한 컨디션의 사람들은 물가나 숲의 잔잔한 곳에서 회복이 빨랐어요.',
  ),
  Situation(
    Icons.cloud_outlined,
    '막연함',
    '발길 닿는 산책',
    '이유를 꼭 알지 않아도 괜찮아요. 마음이 흐릿한 날엔, 발길 닿는 대로 걷는 것도 좋은 답이 돼요.',
    '기분이 막연했던 사람들은 정처 없는 산책 뒤 가장 자주 평온을 되찾았어요.',
  ),
];
