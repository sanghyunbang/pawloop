// 영상 파일에서 위치 정보가 사는 상자를 제자리에서 지운다 — 이슈 #429.
//
// ## 왜 순수 Dart 인가
//
// 720p 재인코딩(`video_compress`)은 네이티브라 `flutter test` 에서 안 돈다. 그러면 "나간 파일에
// 촬영 좌표가 없다" 를 CI 에서 값으로 못 잰다 — 사진은 `image_prep_test` 가 그것을 잰다. 그래서
// 재인코딩 **뒤에** 이 단계를 한 번 더 둔다. 재인코더가 메타데이터를 옮겨 적든 말든, 여기를
// 지난 파일에는 위치 상자가 없고, 그것을 `mp4_metadata_scrubber_test` 가 바이트로 잰다.
//
// ## 어디에 사나
//
// MP4/MOV 는 상자(box) 트리다 — 4바이트 크기 + 4바이트 타입 + 내용. 촬영 위치는 `moov` 아래에
// 산다:
//
// - Android — `moov/udta/©xyz`(3GPP 위치 문자열 `+37.5665+126.9780/`), 드물게 `loci`
// - iPhone — `moov/meta/keys` 의 `com.apple.quicktime.location.ISO6709` 와 `ilst` 의 값
// - `trak` 안에도 `udta`·`meta` 가 올 수 있다
//
// 그래서 `moov` 와 `trak` 바로 아래의 `udta`·`meta` 를 통째로 다룬다. 그 둘에는 위치 말고도
// 기기 모델·제작 도구 같은 것이 들어 있는데, 글에 붙는 영상에 그중 어느 것도 필요 없다.
//
// ## 지우는 대신 덮는다 — 크기를 안 바꾼다
//
// 상자를 잘라 내면 `moov` 가 줄고, `moov` 가 `mdat` 앞에 있는 파일(요즘 인코더 대부분)에서는
// `stco`/`co64` 의 청크 오프셋이 전부 어긋나 영상이 깨진다. 대신 **타입을 `free` 로 바꾸고 안을
// 0 으로 덮는다.** `free` 는 규격상 "무시하라" 는 상자라 어느 플레이어도 안 읽고, 크기가 그대로라
// 오프셋도 그대로다. 문자열은 바이트 수준에서 사라진다.
//
// ## 확인 스캔이 판정이다
//
// 덮은 뒤 [findLocationTraces] 가 `moov` 를 다시 훑는다 — 위치 상자 타입이 남았거나 `ISO6709` ·
// `com.apple.quicktime.location` 문자열이 남았으면 그 파일은 **올리지 않는다**(`VideoPrep`).
// "지웠다" 가 아니라 "없다" 를 잰다.
import 'dart:io';
import 'dart:typed_data';

/// 상자 하나의 자리.
class Mp4Box {
  final String type;

  /// 파일(또는 버퍼)에서의 시작.
  final int offset;

  /// 헤더 포함 전체 크기.
  final int size;

  /// 헤더 길이 — 8, 큰 상자면 16.
  final int headerSize;

  const Mp4Box({
    required this.type,
    required this.offset,
    required this.size,
    required this.headerSize,
  });

  int get payloadOffset => offset + headerSize;
  int get end => offset + size;

  @override
  String toString() => '$type@$offset+$size';
}

/// 상자 트리가 아니다 — 재인코더가 낸 파일이 이 모양이면 올리지 않는다.
class Mp4FormatException implements Exception {
  final String message;
  const Mp4FormatException(this.message);

  @override
  String toString() => 'Mp4FormatException($message)';
}

/// 덮은 뒤의 보고. 무엇을 덮었는지 — 로그와 테스트용.
class Mp4ScrubReport {
  /// 덮은 상자들. 비어 있으면 원래 없었다.
  final List<Mp4Box> neutralized;

  const Mp4ScrubReport(this.neutralized);

  bool get changedAnything => neutralized.isNotEmpty;
}

class Mp4MetadataScrubber {
  const Mp4MetadataScrubber._();

  /// 통째로 `free` 로 바꾸는 상자. 위치가 사는 자리 둘.
  static const Set<String> carriers = {'udta', 'meta'};

  /// 안으로 내려가 보는 상자. `trak` 안의 `udta`·`meta` 도 잡으려고.
  static const Set<String> containers = {'moov', 'trak'};

  /// 확인 스캔이 남아 있으면 안 되는 것으로 보는 상자 타입 — 위치가 사는 둘과 그 안의 위치 상자 둘.
  static const Set<String> locationTypes = {'udta', 'meta', '©xyz', 'loci'};

  /// 확인 스캔이 `moov` 바이트에서 찾는 문자열. 길어서 우연히 나올 수 없다.
  static const List<String> locationMarkers = ['com.apple.quicktime.location', 'ISO6709'];

  /// `moov` 가 이보다 크면 정상 파일이 아니다 — 통째로 메모리에 올리는 상한.
  static const int maxMoovBytes = 64 * 1024 * 1024;

  static const String _free = 'free';

  // ───────────────────────── 파일 ─────────────────────────

  /// 파일을 제자리에서 덮는다. `moov`(와 최상위 `udta`·`meta`)만 읽어 들이고 그 자리만 다시 쓴다 —
  /// `mdat` 은 손대지도 읽지도 않는다.
  static Future<Mp4ScrubReport> scrubFile(String path) async {
    final file = File(path);
    final length = await file.length();
    final raf = await file.open(mode: FileMode.append);
    try {
      final tops = await _topLevelBoxes(raf, length);
      if (!tops.any((b) => b.type == 'moov')) {
        throw const Mp4FormatException('moov 상자가 없다');
      }
      final neutralized = <Mp4Box>[];
      for (final box in tops) {
        final isCarrier = carriers.contains(box.type);
        if (!containers.contains(box.type) && !isCarrier) continue;
        if (box.size > maxMoovBytes) {
          throw Mp4FormatException('${box.type} 이 ${box.size} 바이트다 — 정상 파일이 아니다');
        }
        await raf.setPosition(box.offset);
        final bytes = await raf.read(box.size);
        if (bytes.length != box.size) {
          throw const Mp4FormatException('상자가 파일 끝을 넘는다');
        }
        final touched = <Mp4Box>[];
        if (isCarrier) {
          _neutralize(bytes, Mp4Box(type: box.type, offset: 0, size: box.size, headerSize: box.headerSize));
          touched.add(box);
        } else {
          _scrubRegion(bytes, box.headerSize, box.size, touched, base: box.offset);
        }
        if (touched.isNotEmpty) {
          await raf.setPosition(box.offset);
          await raf.writeFrom(bytes);
          neutralized.addAll(touched);
        }
      }
      await raf.flush();
      return Mp4ScrubReport(neutralized);
    } finally {
      await raf.close();
    }
  }

  /// 파일에서 위치의 흔적을 찾는다. 비어 있으면 깨끗하다. [scrubFile] 뒤에 부르는 판정이다.
  static Future<List<String>> findLocationTracesInFile(String path) async {
    final file = File(path);
    final length = await file.length();
    final raf = await file.open(mode: FileMode.read);
    try {
      final tops = await _topLevelBoxes(raf, length);
      final traces = <String>[];
      for (final box in tops) {
        if (!containers.contains(box.type) && !locationTypes.contains(box.type)) continue;
        if (locationTypes.contains(box.type)) {
          traces.add('${box.type} (최상위)');
          continue;
        }
        if (box.size > maxMoovBytes) {
          throw Mp4FormatException('${box.type} 이 ${box.size} 바이트다 — 정상 파일이 아니다');
        }
        await raf.setPosition(box.offset);
        final bytes = await raf.read(box.size);
        traces.addAll(_tracesInContainer(bytes, box.headerSize, box.size, prefix: box.type));
        traces.addAll(_markerTraces(bytes));
      }
      return traces;
    } finally {
      await raf.close();
    }
  }

  // ───────────────────────── 버퍼 ─────────────────────────

  /// 버퍼 안의 파일을 덮는다 — 테스트와 작은 파일용. 같은 규칙, 같은 결과.
  static Mp4ScrubReport scrubBytes(Uint8List bytes) {
    final tops = parseBoxes(bytes, 0, bytes.length);
    if (!tops.any((b) => b.type == 'moov')) {
      throw const Mp4FormatException('moov 상자가 없다');
    }
    final touched = <Mp4Box>[];
    for (final box in tops) {
      if (carriers.contains(box.type)) {
        _neutralize(bytes, box);
        touched.add(box);
      } else if (containers.contains(box.type)) {
        _scrubRegion(bytes, box.payloadOffset, box.end, touched);
      }
    }
    return Mp4ScrubReport(touched);
  }

  /// 버퍼에서 위치의 흔적. [findLocationTracesInFile] 과 같은 규칙.
  static List<String> findLocationTraces(Uint8List bytes) {
    final traces = <String>[];
    for (final box in parseBoxes(bytes, 0, bytes.length)) {
      if (locationTypes.contains(box.type)) {
        traces.add('${box.type} (최상위)');
      } else if (containers.contains(box.type)) {
        traces.addAll(_tracesInContainer(bytes, box.payloadOffset, box.end, prefix: box.type));
        traces.addAll(_markerTraces(Uint8List.sublistView(bytes, box.offset, box.end)));
      }
    }
    return traces;
  }

  /// `[start, end)` 안의 상자 목록. 크기가 0 이면 끝까지, 1 이면 8바이트 큰 크기다.
  /// 깨진 상자(끝을 넘는 것)를 만나면 거기서 멈춘다 — 예외가 아니라 "여기까지" 다.
  static List<Mp4Box> parseBoxes(Uint8List bytes, int start, int end) {
    final data = ByteData.sublistView(bytes);
    final boxes = <Mp4Box>[];
    var at = start;
    while (at + 8 <= end) {
      var size = data.getUint32(at);
      final type = String.fromCharCodes(bytes, at + 4, at + 8);
      var header = 8;
      if (size == 1) {
        if (at + 16 > end) break;
        final large = data.getUint64(at + 8);
        if (large > 0x7fffffff) break;
        size = large;
        header = 16;
      } else if (size == 0) {
        size = end - at;
      }
      if (size < header || at + size > end) break;
      boxes.add(Mp4Box(type: type, offset: at, size: size, headerSize: header));
      at += size;
    }
    return boxes;
  }

  // ───────────────────────── 안쪽 ─────────────────────────

  static void _scrubRegion(Uint8List bytes, int start, int end, List<Mp4Box> touched, {int base = 0}) {
    for (final box in parseBoxes(bytes, start, end)) {
      if (carriers.contains(box.type)) {
        _neutralize(bytes, box);
        touched.add(Mp4Box(
            type: box.type, offset: base + box.offset, size: box.size, headerSize: box.headerSize));
      } else if (containers.contains(box.type)) {
        _scrubRegion(bytes, box.payloadOffset, box.end, touched, base: base);
      }
    }
  }

  /// 타입을 `free` 로, 내용을 0 으로. 크기 필드는 그대로다.
  static void _neutralize(Uint8List bytes, Mp4Box box) {
    final typeAt = box.offset + 4;
    for (var i = 0; i < 4; i++) {
      bytes[typeAt + i] = _free.codeUnitAt(i);
    }
    bytes.fillRange(box.payloadOffset, box.end, 0);
  }

  static List<String> _tracesInContainer(Uint8List bytes, int start, int end, {required String prefix}) {
    final traces = <String>[];
    for (final box in parseBoxes(bytes, start, end)) {
      if (locationTypes.contains(box.type)) {
        traces.add('$prefix/${box.type}');
      } else if (containers.contains(box.type)) {
        traces.addAll(_tracesInContainer(bytes, box.payloadOffset, box.end, prefix: '$prefix/${box.type}'));
      }
    }
    return traces;
  }

  /// 긴 ASCII 문자열을 그대로 찾는다 — 상자 구조와 무관하게, 어디에 숨어 있든.
  static List<String> _markerTraces(Uint8List bytes) {
    final text = String.fromCharCodes(bytes);
    return [
      for (final marker in locationMarkers)
        if (text.contains(marker)) '문자열 $marker',
    ];
  }

  static Future<List<Mp4Box>> _topLevelBoxes(RandomAccessFile raf, int length) async {
    final boxes = <Mp4Box>[];
    var at = 0;
    while (at + 8 <= length) {
      await raf.setPosition(at);
      final head = await raf.read(16);
      if (head.length < 8) break;
      final data = ByteData.sublistView(head);
      var size = data.getUint32(0);
      final type = String.fromCharCodes(head, 4, 8);
      var header = 8;
      if (size == 1) {
        if (head.length < 16) break;
        final large = data.getUint64(8);
        if (large > 0x7fffffffffff) break;
        size = large;
        header = 16;
      } else if (size == 0) {
        size = length - at;
      }
      if (size < header || at + size > length) {
        throw Mp4FormatException('$type 상자가 파일 끝을 넘는다 (@$at, $size)');
      }
      boxes.add(Mp4Box(type: type, offset: at, size: size, headerSize: header));
      at += size;
    }
    return boxes;
  }
}
