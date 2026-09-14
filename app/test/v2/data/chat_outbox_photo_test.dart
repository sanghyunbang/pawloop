// 대기 사진 메시지 — 이슈 #452. 올린 id 는 실패 · 재시도를 지나도 남는다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/chat_outbox.dart';

void main() {
  final photo = PendingPhoto(bytes: Uint8List.fromList([1, 2]), width: 720, height: 1280);

  test('사진 메시지는 본문이 비고 사진을 들며, 올린 id 는 실패 · 재시도를 지나도 그대로다', () {
    final pending = PendingMessage.photo(photo);
    expect(pending.isPhoto, isTrue);
    expect(pending.body, '');
    expect(pending.mediaId, isNull);

    final uploaded = pending.uploaded(31);
    final failed = uploaded.failed();
    final retrying = failed.retrying();

    expect(uploaded.mediaId, 31);
    expect(uploaded.state, PendingState.sending);
    expect(failed.mediaId, 31, reason: '실패해도 올린 사진을 잊지 않는다 — 다시 보낼 때 또 올리지 않게');
    expect(failed.photo, same(photo));
    expect(retrying.mediaId, 31);
    expect(retrying.clientMsgId, pending.clientMsgId, reason: '멱등키는 그대로');
  });

  test('글자 메시지는 사진이 없다 — 예전 그대로', () {
    final pending = PendingMessage.create('글자');
    expect(pending.isPhoto, isFalse);
    expect(pending.failed().mediaId, isNull);
  });

  test('대기 사진의 가로세로비는 서버 사진과 같은 4:5 ~ 1.91:1 규칙이다', () {
    expect(photo.aspectRatio, closeTo(0.8, 0.001), reason: '9:16 은 4:5 로');
    expect(PendingPhoto(bytes: Uint8List(0), width: 3000, height: 1000).aspectRatio, closeTo(1.91, 0.001));
    expect(PendingPhoto(bytes: Uint8List(0), width: 0, height: 0).aspectRatio, 1);
  });
}
