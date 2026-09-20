// 가족 구성원마다 색 하나 — 이슈 #736.
//
// 구글 캘린더처럼 **사람마다 색**이 있어야 담당이 눈에 들어온다. 색은 가족 목록의 **순서**로
// 정한다(가입 순) — 이름으로 해시하면 이름을 바꾸는 날 색이 바뀐다. 순서는 안 바뀐다.
//
// 넷이면 충분하다 — 한 집에 넷 넘게 사는 일은 드물고, 넘으면 처음부터 돈다. 넷 다 **진한**
// 색이다: 흰 바탕 위 글자로도, 연한 바탕의 태그로도 읽혀야 해서 파스텔은 안 된다(#446).
// 브랜드 코랄(`T.accent`)은 안 쓴다 — 그건 "골랐다 · 끝냈다" 의 색이라 사람 색과 섞이면 둘 다 흐려진다.
import 'package:flutter/material.dart';

/// 가족 순서대로 — 파랑 · 초록 · 금색 · 보라. 코랄(브랜드)과 겹치는 색은 없다.
const List<Color> kMemberColors = [
  Color(0xFF1E6FB8),
  Color(0xFF2E8B57),
  Color(0xFFB8860B),
  Color(0xFF8E44AD),
];

/// [index] 번째 구성원의 색. 넷을 넘으면 처음부터 돈다.
Color memberColor(int index) => kMemberColors[index % kMemberColors.length];
