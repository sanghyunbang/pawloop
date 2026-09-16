// 항목 칸의 그림 — 이슈 #560.
//
// 서버가 열쇠말 하나로 보내고(`CareItem.icon`, 계약의 `CareIcon`) 앱이 그림을 고른다.
// 이모지를 받지 않는 이유는 사장님 결정이다 — 기기마다 다르게 그려지고, 흰 바탕에 코랄
// 하나로 맞춰 둔 화면에 색이 섞인다.
import 'package:flutter/material.dart';

/// 고치기 화면이 보여 주는 <b>고르는 목록</b>. 순서가 곧 화면의 순서다.
///
/// 앞의 일곱은 기본 항목이 쓰는 값이고(`CareType` 과 같은 표기) 나머지는 직접 만들 때
/// 고르는 것들이다. **서버가 아는 목록과 같아야 한다** — 여기에만 있는 값을 고르면 저장이
/// 400 이고, 서버에만 있는 값은 아래 [careItemIcon] 이 기본 그림으로 떨어뜨린다.
const List<String> kCareIconKeys = [
  'water',
  'meal',
  'walk',
  'med',
  'vet',
  'poop',
  'pee',
  'snack',
  'tooth',
  'bath',
  'brush',
  'nail',
  'heart',
  'play',
  'weight',
  'etc',
];

/// 열쇠말 → 그림. **모르는 값이면 기본 그림**이다.
///
/// 던지지 않는 것이 요점이다. 서버가 목록을 넓히면 옛 앱에는 모르는 값이 내려오는데,
/// 그때 예외를 던지면 그 칸 하나 때문에 카드가 통째로 안 그려진다 — 그림 하나가 밋밋한
/// 것과 화면이 비는 것은 무게가 다르다.
///
/// <b>기본 그림으로 체크 표시를 쓰면 안 된다.</b> 카드는 완료한 칸을 체크로 그린다 —
/// 모르는 열쇠말이 체크로 떨어지면 **아직 안 한 칸이 한 것처럼 보인다.** 처음에
/// `check_circle_outline` 으로 뒀다가 에뮬레이터에서 `기타` 칸이 체크로 그려지는 것을 보고
/// 고쳤다.
///
/// 배변·마킹은 여기 없다 — 머티리얼에 그 뜻의 아이콘이 없어 [CareGlyph] 가 직접 그린다.
IconData careItemIcon(String key) => switch (key) {
      'water' => Icons.water_drop_rounded,
      'meal' => Icons.restaurant_rounded,
      'walk' => Icons.pets_rounded,
      'med' => Icons.medication_rounded,
      'vet' => Icons.local_hospital_rounded,
      'poop' => Icons.eco_rounded,
      'pee' => Icons.opacity_rounded,
      'snack' => Icons.cookie_rounded,
      // 칫솔이 머티리얼에 없다. 솔 모양 중 빗질(`brush`)과 제일 덜 닮은 것을 골랐다.
      'tooth' => Icons.cleaning_services_rounded,
      'bath' => Icons.shower_rounded,
      'brush' => Icons.brush_rounded,
      'nail' => Icons.content_cut_rounded,
      'heart' => Icons.favorite_rounded,
      'play' => Icons.sports_baseball_rounded,
      'weight' => Icons.monitor_weight_rounded,
      'etc' => Icons.more_horiz_rounded,
      // 모르는 열쇠말. 체크가 아니어야 한다 — 위 머리말 참조.
      _ => Icons.label_outline_rounded,
    };

/// 고르는 목록에 붙는 짧은 이름 — 그림만으로는 무엇인지 모를 칸이 있다.
String careIconLabel(String key) => switch (key) {
      'water' => '물',
      'meal' => '밥',
      'walk' => '산책',
      'med' => '투약',
      'vet' => '병원',
      'poop' => '배변',
      'pee' => '마킹',
      'snack' => '간식',
      'tooth' => '양치',
      'bath' => '목욕',
      'brush' => '빗질',
      'nail' => '발톱',
      'heart' => '건강',
      'play' => '놀이',
      'weight' => '체중',
      _ => '기타',
    };
