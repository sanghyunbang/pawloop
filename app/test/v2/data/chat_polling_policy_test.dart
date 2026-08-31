import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/chat_polling_policy.dart';

/// 적응형 폴링 간격 정책. (이슈 #81 완료 조건 6)
///
/// 이 파일이 지키는 것은 **간격이 상태에 따라 달라진다**는 것이다. 상수 3초로 되돌리면
/// 여기가 빨간불이어야 한다 — 그게 완료 조건 6이 요구하는 것이고, 아래 두 그룹이 그 역할을 한다.
void main() {
  group('포그라운드 복귀', () {
    test('돌아온 직후에는 기다리지 않는다 — 낡은 화면이 가장 눈에 띈다', () {
      expect(
        ChatPollingPolicy.nextInterval(
          inForeground: true,
          consecutiveEmptyPolls: 0,
          justResumed: true,
        ),
        Duration.zero,
      );
    });

    test('복귀는 빈 응답 이력보다 우선한다 — 오래 비어 있었어도 즉시 한 번 받아온다', () {
      expect(
        ChatPollingPolicy.nextInterval(
          inForeground: true,
          consecutiveEmptyPolls: 10,
          justResumed: true,
        ),
        Duration.zero,
      );
    });

    test('백그라운드에서 돌아오는 것도 즉시다', () {
      expect(
        ChatPollingPolicy.nextInterval(
          inForeground: false,
          consecutiveEmptyPolls: 3,
          justResumed: true,
        ),
        Duration.zero,
      );
    });
  });

  group('백그라운드', () {
    test('뒤로 가면 30초 — 배지 숫자만 맞으면 되므로 실시간일 이유가 없다', () {
      expect(
        ChatPollingPolicy.nextInterval(inForeground: false, consecutiveEmptyPolls: 0),
        const Duration(seconds: 30),
      );
    });

    test('백그라운드에서는 빈 응답이 이어져도 간격이 그대로다 — 이미 최대다', () {
      for (final empties in [0, 1, 5, 50]) {
        expect(
          ChatPollingPolicy.nextInterval(
            inForeground: false,
            consecutiveEmptyPolls: empties,
          ),
          const Duration(seconds: 30),
          reason: '빈 응답 $empties 회',
        );
      }
    });
  });

  group('적응 — 이 그룹이 상수 3초와 갈리는 자리다', () {
    test('대화가 살아 있으면 3초', () {
      expect(
        ChatPollingPolicy.nextInterval(inForeground: true, consecutiveEmptyPolls: 0),
        const Duration(seconds: 3),
      );
    });

    test('빈 응답이 이어지면 간격이 커진다 — 상수 3초로 되돌리면 여기가 빨간불이다', () {
      final intervals = [
        for (var empties = 0; empties <= 4; empties++)
          ChatPollingPolicy.nextInterval(
            inForeground: true,
            consecutiveEmptyPolls: empties,
          ),
      ];

      expect(
        intervals,
        [
          const Duration(seconds: 3),
          const Duration(seconds: 6),
          const Duration(seconds: 12),
          const Duration(seconds: 24),
          const Duration(seconds: 30), // 48초가 아니라 상한에서 멈춘다
        ],
        reason: '''
빈 응답이 이어지는 것은 사람이 대화를 쉬고 있다는 뜻이다. 그때도 3초로 계속 두드리면
서버의 chat.poll{result=empty} 비율만 올라가고 아무도 얻는 것이 없다 (#80).

이 단언이 상수 3초를 막는다.''',
      );
    });

    test('아무리 비어 있어도 30초를 넘지 않는다 — 넘으면 대화 재개를 놓친다', () {
      for (final empties in [5, 10, 100]) {
        expect(
          ChatPollingPolicy.nextInterval(
            inForeground: true,
            consecutiveEmptyPolls: empties,
          ),
          const Duration(seconds: 30),
          reason: '빈 응답 $empties 회',
        );
      }
    });

    test('간격은 단조 증가한다 — 중간에 줄어드는 구간이 없다', () {
      Duration? previous;
      for (var empties = 0; empties <= 8; empties++) {
        final current = ChatPollingPolicy.nextInterval(
          inForeground: true,
          consecutiveEmptyPolls: empties,
        );
        if (previous != null) {
          expect(current >= previous, isTrue, reason: '빈 응답 $empties 회에서 줄었다');
        }
        previous = current;
      }
    });
  });

  group('잘못된 입력', () {
    test('음수가 들어와도 폴링이 멈추지 않는다 — 부르는 쪽의 실수가 기능을 죽이면 안 된다', () {
      expect(
        ChatPollingPolicy.nextInterval(inForeground: true, consecutiveEmptyPolls: -1),
        const Duration(seconds: 3),
      );
    });
  });
}
