import 'package:flutter/material.dart';

/// "무엇이 마음을 움직였나요?" 상황 6종 (핸드오프 SITU).
class Situation {
  final IconData icon;
  final String label;
  final String tip;
  const Situation(this.icon, this.label, this.tip);
}

const List<Situation> kSituations = [
  Situation(Icons.work_outline, '취업·진로', '몸을 움직이는 산책'),
  Situation(Icons.favorite_border, '연애·관계', '온기 있는 공간'),
  Situation(Icons.business_center_outlined, '일·업무', '탁 트인 전망'),
  Situation(Icons.person_outline, '외로움', '느슨한 북적임'),
  Situation(Icons.spa_outlined, '번아웃', '물가·숲'),
  Situation(Icons.cloud_outlined, '막연함', '발길 닿는 산책'),
];
