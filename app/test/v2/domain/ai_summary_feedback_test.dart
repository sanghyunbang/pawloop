// AI 요약의 id 와 평가 (#486 후속) — 옛 서버(id 없음)와도 그려지고, 새 서버의 평가를 읽는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/domain/weekly_summary.dart';

void main() {
  test('id 와 feedback 을 읽는다', () {
    final ai = AiSummary.parse({
      'id': 12,
      'text': '이번 주는 3회 걸었어요.\n좋아요.\n한 번 더 어떠세요?',
      'generatedAt': '2026-09-14T09:30:00Z',
      'feedback': 'up',
    })!;

    expect(ai.id, 12);
    expect(ai.feedback, 'up');
  });

  test('옛 서버가 id 를 안 주면 null 이고, feedback 이 null 이면 null', () {
    final ai = AiSummary.parse({'text': '문장', 'generatedAt': '2026-09-14T09:30:00Z', 'feedback': null})!;

    expect(ai.id, isNull);
    expect(ai.feedback, isNull);
  });

  test('withFeedback 은 문장과 id 를 지키고 평가만 바꾼다', () {
    const ai = AiSummary(id: 3, text: '문장', feedback: 'down');

    final changed = ai.withFeedback(null);

    expect(changed.id, 3);
    expect(changed.text, '문장');
    expect(changed.feedback, isNull);
  });
}
