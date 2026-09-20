// 케어 기록 한 줄 — `10:39  아빠  물`. 홈 카드의 "오늘 한 일"(#570)과 날짜별 기록 화면(#737)이
// 같은 줄을 쓴다.
//
// 시각 · 사람 · 무엇, 셋 다 왼쪽에 맞춘다. 사람 칸에 고정 폭을 주는 이유: 이름 길이가
// 제각각이라 그냥 두면 종류가 들쭉날쭉 앉는다. 훑을 때 눈이 따라가는 세로줄이 "무엇" 이라
// 그 줄이 흔들리면 안 읽힌다.
//
// 폭 [CareLogLine.nameWidth] 는 에뮬레이터에서 보고 늘린 값이다 — 58 로 뒀더니 `CrewOwner` 가
// `CrewOw…` 로 잘렸다. 그보다 긴 이름은 여전히 줄임표로 접는다(잘리는 편이 종류 줄이
// 흔들리는 것보다 낫다).
import 'package:flutter/material.dart';

import '../data/family_repository.dart';
import '../theme/app_tokens.dart';

class CareLogLine extends StatelessWidget {
  final CareLogEntry log;

  /// 무엇을 했나 — 그 집의 칸 이름([CareLogEntry.nameAmong]). 부르는 쪽이 항목 목록을 든다.
  final String name;

  const CareLogLine({super.key, required this.log, required this.name});

  /// 사람 칸 폭. 390dp 에서 `CrewOwner` 가 들어가는 값이다.
  static const double nameWidth = 78;

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
          width: 42,
          child: Text(log.timeLabel,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: T.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
        SizedBox(
          width: nameWidth,
          child: Text(log.doneByName.isEmpty ? '누군가' : log.doneByName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: T.textSecondary)),
        ),
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: T.textSecondary)),
        ),
      ]);
}
