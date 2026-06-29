import 'package:flutter/material.dart';
import '../../state/foryou_vm.dart';
import 'loading_screen.dart';
import 'analysis_screen.dart';
import 'today_checkin.dart';

/// "오늘" 홈: 무드 체크인 → 처리 → 결과 스위처 (F0-3)
class ForYouHomeScreen extends StatelessWidget {
  final ForYouVM vm;
  const ForYouHomeScreen({super.key, required this.vm});

  @override
  Widget build(BuildContext context) {
    // 👇 ChangeNotifier(vm)을 직접 구독해 상태 변경 시 자동 리빌드
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        final collecting = vm.phase == ForYouPhase.collecting;
        Widget body;
        switch (vm.phase) {
          case ForYouPhase.collecting:
            body = TodayCheckIn(vm: vm);
            break;
          case ForYouPhase.processing:
            body = const LoadingScreen(); // VM이 최소 로딩시간 보장
            break;
          case ForYouPhase.error:
            body = Center(child: Text(vm.error ?? '문제가 발생했어요.'));
            break;
          case ForYouPhase.ready:
            body = AnalysisScreen(vm: vm);
            break;
        }

        return Scaffold(
          backgroundColor: const Color(0xFFFFFAF8),
          appBar: AppBar(
            elevation: 0.6,
            backgroundColor: Colors.white,
            title: const Text(
              '오늘',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              // 결과/처리 상태에서 다시 무드부터 입력하도록 되돌리기
              if (!collecting)
                IconButton(
                  tooltip: '다시 체크인',
                  icon: const Icon(Icons.refresh),
                  onPressed: vm.resetToCheckIn,
                ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}
