// 테스트용 MP4 — 위치 상자를 실은 것과 안 실은 것 (#429).
//
// 진짜 영상 파일은 저장소에 안 넣는다. 상자(box) 트리만 맞춘 작은 파일이면 스크러버가 보는 것은
// 전부 있다 — `ftyp` · `moov`(`mvhd` · `trak` · `udta` · `meta`) · `mdat`. 좌표(37.5665, 126.978)는
// 서울시청 앞이고, 사진 픽스처의 (37, 127)처럼 지어낸 값이다.
import 'dart:convert';
import 'dart:typed_data';

/// 3GPP `©xyz` 와 Apple `ISO6709` 가 같이 쓰는 형식.
const String mp4FixtureLocation = '+37.5665+126.9780/';

/// Apple 이 `moov/meta/keys` 에 두는 키.
const String mp4FixtureAppleKey = 'com.apple.quicktime.location.ISO6709';

List<int> _u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

List<int> _u64(int v) => [..._u32(v >> 32), ..._u32(v & 0xffffffff)];

/// 타입 4바이트를 직접 준다 — `ilst` 항목의 타입은 문자가 아니라 번호다.
Uint8List mp4BoxRaw(List<int> type, List<int> payload) =>
    Uint8List.fromList([..._u32(8 + payload.length), ...type, ...payload]);

Uint8List mp4Box(String type, List<int> payload) => mp4BoxRaw(latin1.encode(type), payload);

/// version(1) + flags(3) 가 앞에 오는 상자.
Uint8List mp4FullBox(String type, List<int> payload) => mp4Box(type, [0, 0, 0, 0, ...payload]);

/// `size == 1` 에 8바이트 큰 크기가 따라오는 상자 — 4GB 넘는 `mdat` 이 이 모양이다.
Uint8List mp4LargeBox(String type, List<int> payload) =>
    Uint8List.fromList([..._u32(1), ...latin1.encode(type), ..._u64(16 + payload.length), ...payload]);

/// `©xyz` — 3GPP 위치 문자열. 앞 2바이트가 길이, 다음 2바이트가 언어(und).
Uint8List mp4XyzBox() =>
    mp4Box('©xyz', [0, mp4FixtureLocation.length, 0x55, 0xC4, ...latin1.encode(mp4FixtureLocation)]);

/// `loci` — 3GPP 위치 정보 상자. 이름·역할·좌표.
Uint8List mp4LociBox() => mp4FullBox('loci',
    [0x55, 0xC4, ...latin1.encode('home'), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ...latin1.encode('Seoul'), 0]);

/// Apple 식 `meta` — `hdlr(mdta)` · `keys` · `ilst`. 값은 `ilst/1/data` 에 있다.
Uint8List mp4AppleMetaBox() {
  final hdlr = mp4FullBox('hdlr', [0, 0, 0, 0, ...latin1.encode('mdta'), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  final keyEntry = [..._u32(8 + mp4FixtureAppleKey.length), ...latin1.encode('mdta'), ...latin1.encode(mp4FixtureAppleKey)];
  final keys = mp4FullBox('keys', [..._u32(1), ...keyEntry]);
  final data = mp4Box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...latin1.encode(mp4FixtureLocation)]);
  final ilst = mp4Box('ilst', mp4BoxRaw([0, 0, 0, 1], data));
  return mp4FullBox('meta', [...hdlr, ...keys, ...ilst]);
}

/// `mdat` 의 내용 — 결정적이다. 덮기 전후를 바이트로 대조한다.
List<int> mp4FixtureMdat() => List<int>.generate(4096, (i) => (i * 7) % 251);

/// 파일 전체.
///
/// [withLocation] 이면 `moov/trak/udta/©xyz` · `moov/udta/{©xyz,loci}` · `moov/meta/…ISO6709` 셋을
/// 싣는다. [hiddenMarkerInMvhd] 는 위치 문자열을 **위치 상자가 아닌 곳**(`mvhd` 안)에 숨긴다 —
/// 스크러버가 못 지우는 자리라 확인 스캔이 잡아야 한다.
Uint8List mp4Fixture({bool withLocation = true, bool largeMdat = false, bool hiddenMarkerInMvhd = false}) {
  final ftyp = mp4Box('ftyp', [...latin1.encode('isom'), 0, 0, 2, 0, ...latin1.encode('isomiso2mp41')]);

  final mvhdPayload = List<int>.filled(96, 0);
  if (hiddenMarkerInMvhd) {
    mvhdPayload.setRange(20, 20 + mp4FixtureAppleKey.length, latin1.encode(mp4FixtureAppleKey));
  }
  final mvhd = mp4FullBox('mvhd', mvhdPayload);
  final tkhd = mp4FullBox('tkhd', List<int>.filled(80, 0x11));
  final trak = mp4Box('trak', [...tkhd, if (withLocation) ...mp4Box('udta', mp4XyzBox())]);
  final moov = mp4Box('moov', [
    ...mvhd,
    ...trak,
    if (withLocation) ...mp4Box('udta', [...mp4XyzBox(), ...mp4LociBox()]),
    if (withLocation) ...mp4AppleMetaBox(),
  ]);

  final mdat = largeMdat ? mp4LargeBox('mdat', mp4FixtureMdat()) : mp4Box('mdat', mp4FixtureMdat());
  return Uint8List.fromList([...ftyp, ...moov, ...mdat]);
}
