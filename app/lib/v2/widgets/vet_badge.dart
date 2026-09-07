// "24시" 배지 — **이름 기준**이라는 것을 늘 함께 적는다 (#337).
//
// 진료시간을 주는 공공 데이터가 없다(`vet_hours.dart` 머리말). 그래서 이 배지는 우리가
// 확인한 사실이 아니라 **이름에 그렇게 적혀 있다**는 말이다. 그 단서를 떼면, 밤 11시에
// 전화를 걸 사람에게 우리가 확인하지 않은 것을 확인한 척하는 것이 된다.
import 'package:flutter/material.dart';

class VetTwentyFourBadge extends StatelessWidget {
  const VetTwentyFourBadge({super.key});

  /// 배지에 적히는 말. 테스트와 화면이 같은 문자열을 본다.
  static const String label = '24시 · 이름 기준';

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x1AD7263D),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          label,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFD7263D)),
        ),
      );
}
