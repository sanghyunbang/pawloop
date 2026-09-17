import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/chat_polling_policy.dart';

/// 적응형 폴링 간격 정책. (이슈 #81 완료 조건 6 · 이슈 #672)
///
/// 이 파일이 지키는 것은 **간격이 상태에 따라 달라진다**는 것이다. 상수 3초로 되돌리면
/// 여기가 빨간불이어야 한다 — 그게 완료 조건 6이 요구하는 것이고, 아래 두 그룹이 그 역할을 한다.
///
/// #672 이 인자를 하나 더했다(`consecutiveFailedPolls`). 위 그룹들은 그 자리에 0을 **명시해서**
/// 넘긴다 — 판정하는 값은 하나도 안 바뀌었고, 빈손 축만 재는 단언이라는 것이 눈에 보인다.
/// 실패 축과 둘이 섞였을 때는 아래 '실패는 따로 센다' 그룹이 값으로 잠근다.
void main() {
  group('포그라운드 복귀', () {
    test('돌아온 직후에는 기다리지 않는다 — 낡은 화면이 가장 눈에 띈다', () {
      expect(
        ChatPollingPolicy.nextInterval(
          inForeground: true,
          consecutiveEmptyPolls: 0,
          consecutiveFailedPolls: 0,
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
          consecutiveFailedPolls: 0,
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
          consecutiveFailedPolls: 0,
          justResumed: true,
        ),
        Duration.zero,
      );
    });
  });

  group('백그라운드', () {
    test('뒤로 가면 30초 — 배지 숫자만 맞으면 되므로 실시간일 이유가 없다', () {
      expect(
        ChatPollingPolicy.nextInterval(
            inForeground: false, consecutiveEmptyPolls: 0, consecutiveFailedPolls: 0),
        const Duration(seconds: 30),
      );
    });

    test('백그라운드에서는 빈 응답이 이어져도 간격이 그대로다 — 이미 최대다', () {
      for (final empties in [0, 1, 5, 50]) {
        expect(
          ChatPollingPolicy.nextInterval(
            inForeground: false,
            consecutiveEmptyPolls: empties,
            consecutiveFailedPolls: 0,
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
        ChatPollingPolicy.nextInterval(
            inForeground: true, consecutiveEmptyPolls: 0, consecutiveFailedPolls: 0),
        const Duration(seconds: 3),
      );
    });

    test('빈 응답이 이어지면 간격이 커진다 — 상수 3초로 되돌리면 여기가 빨간불이다', () {
      final intervals = [
        for (var empties = 0; empties <= 4; empties++)
          ChatPollingPolicy.nextInterval(
            inForeground: true,
            consecutiveEmptyPolls: empties,
            consecutiveFailedPolls: 0,
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
            consecutiveFailedPolls: 0,
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
          consecutiveFailedPolls: 0,
        );
        if (previous != null) {
          expect(current >= previous, isTrue, reason: '빈 응답 $empties 회에서 줄었다');
        }
        previous = current;
      }
    });
  });

  group('실패는 따로 센다 — 빈손과 더하지 않는다 (#672)', () {
    test('실패도 물러난다 — 떼 버리면 서버가 죽은 동안 9초짜리 요청이 3초마다 쌓인다', () {
      final intervals = [
        for (var fails = 0; fails <= 4; fails++)
          ChatPollingPolicy.nextInterval(
            inForeground: true,
            consecutiveEmptyPolls: 0,
            consecutiveFailedPolls: fails,
          ),
      ];

      expect(
        intervals,
        [
          const Duration(seconds: 3),
          const Duration(seconds: 6),
          const Duration(seconds: 12),
          const Duration(seconds: 24),
          const Duration(seconds: 30), // 빈손과 같은 상한이다
        ],
        reason: '실패 백오프를 떼면 여기가 전부 3초가 되어 빨간불이다',
      );
    });

    test('빈손 둘 · 실패 둘은 12초다 — 넷을 더해 30초로 내려앉지 않는다', () {
      expect(
        ChatPollingPolicy.nextInterval(
          inForeground: true,
          consecutiveEmptyPolls: 2,
          consecutiveFailedPolls: 2,
        ),
        const Duration(seconds: 12),
        reason: '''
한 카운터에 같이 넣으면 2 + 2 = 4 라 상한 30초다. 둘은 다른 사실이므로 각자 물러난 뒤
느린 쪽(12초)을 쓴다 — 하나로 합치면 이 단언이 빨간불이다.''',
      );
    });

    test('느린 쪽을 쓴다 — 어느 한쪽만 물러나도 그만큼은 기다린다', () {
      expect(
        ChatPollingPolicy.nextInterval(
          inForeground: true,
          consecutiveEmptyPolls: 3,
          consecutiveFailedPolls: 0,
        ),
        const Duration(seconds: 24),
        reason: '망은 멀쩡하지만 조용한 방',
      );
      expect(
        ChatPollingPolicy.nextInterval(
          inForeground: true,
          consecutiveEmptyPolls: 0,
          consecutiveFailedPolls: 3,
        ),
        const Duration(seconds: 24),
        reason: '방은 한창이지만 망이 끊긴다',
      );
    });

    test('망이 돌아오면 그쪽만 0이 된다 — 대화 중이던 방은 곧바로 3초로 돌아온다', () {
      expect(
        ChatPollingPolicy.nextInterval(
          inForeground: true,
          consecutiveEmptyPolls: 0,
          consecutiveFailedPolls: 0,
        ),
        const Duration(seconds: 3),
        reason: '''
실패 넷(30초) 뒤에 왕복이 한 번 성공하면 실패 카운터는 0이다. 그때 방이 한창이었다면
빈손 카운터도 0이라 3초다 — 완료 조건 2 "망이 흔들려도 대화가 한창인 방은 3초를 지킨다".''',
      );
    });

    test('실패가 이어져도 30초를 넘지 않는다 — 상한은 하나다', () {
      for (final fails in [5, 10, 100]) {
        expect(
          ChatPollingPolicy.nextInterval(
            inForeground: true,
            consecutiveEmptyPolls: 0,
            consecutiveFailedPolls: fails,
          ),
          const Duration(seconds: 30),
          reason: '실패 $fails 회',
        );
      }
    });

    test('백그라운드는 실패와 상관없이 30초다', () {
      for (final fails in [0, 1, 50]) {
        expect(
          ChatPollingPolicy.nextInterval(
            inForeground: false,
            consecutiveEmptyPolls: 0,
            consecutiveFailedPolls: fails,
          ),
          const Duration(seconds: 30),
          reason: '실패 $fails 회',
        );
      }
    });

    test('복귀는 실패 이력보다도 우선한다 — 돌아온 순간은 즉시 한 번', () {
      expect(
        ChatPollingPolicy.nextInterval(
          inForeground: true,
          consecutiveEmptyPolls: 0,
          consecutiveFailedPolls: 10,
          justResumed: true,
        ),
        Duration.zero,
      );
    });
  });

  group('잘못된 입력', () {
    test('음수가 들어와도 폴링이 멈추지 않는다 — 부르는 쪽의 실수가 기능을 죽이면 안 된다', () {
      expect(
        ChatPollingPolicy.nextInterval(
            inForeground: true, consecutiveEmptyPolls: -1, consecutiveFailedPolls: 0),
        const Duration(seconds: 3),
      );
    });

    test('실패 쪽 음수도 같다 — 두 축 모두 0으로 떨어진다', () {
      expect(
        ChatPollingPolicy.nextInterval(
            inForeground: true, consecutiveEmptyPolls: -1, consecutiveFailedPolls: -5),
        const Duration(seconds: 3),
      );
      expect(
        ChatPollingPolicy.nextInterval(
            inForeground: true, consecutiveEmptyPolls: 2, consecutiveFailedPolls: -5),
        const Duration(seconds: 12),
        reason: '한쪽이 잘못 들어와도 다른 쪽 판단은 살아 있다',
      );
    });
  });
}
