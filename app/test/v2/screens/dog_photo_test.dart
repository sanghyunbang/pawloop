// 아이 사진 — 이슈 #448 (#451 5번의 앞 조각).
//
// 등록 시트에서 고르면 줄여서 올리고(PROFILE_IMAGE) 등록 뒤 그 아이에 붙인다 · 편집 화면에서 바꾸고 지운다 ·
// 홈 히어로·내 정보·아이 고르기는 사진이 있으면 사진, 없으면 종 이모지다.
//
// 진짜 `WalkRepository`·`PostMediaRepository` 에 `MockClient`. 사진 준비(`ImagePrep`)는 물려 넣어 격리
// 프로세스를 안 띄운다 — `post_media_field_test` 와 같은 방식.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/image_prep.dart';
import 'package:heat_trip_flutter/v2/data/media_picker.dart';
import 'package:heat_trip_flutter/v2/data/pet_sync.dart';
import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/edit_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/dog_avatar.dart';
import 'package:heat_trip_flutter/v2/widgets/pet_registration_sheet.dart';

import '../support/fake_media_picker.dart';
import '../support/gps_jpeg.dart';
import '../support/multipart.dart';

const _base = 'https://api.example.test';
const _cdn = 'https://cdn.example.test/profiles/7/';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT-1';

  @override
  Future<String?> readRefreshToken() async => 'RT-1';

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _dogJson(int id, String name, {String? avatarUrl}) => {
      'id': id,
      'name': name,
      'species': 'dog',
      'size': 'small',
      'breed': null,
      'ageMonths': 30,
      'neutered': false,
      'avatarUrl': avatarUrl,
    };

/// 서버 흉내 — `/media` 업로드, `/api/dogs` 등록, `/api/dogs/{id}/avatar` 붙이기·떼기.
class _Server {
  final requests = <http.Request>[];
  final uploads = <List<MultipartPart>>[];
  int nextMedia = 41;
  int nextDog = 7;
  int avatarStatus = 200;
  final avatars = <int, String>{};

  Future<http.Response> call(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'POST' && path == '/media') {
      final parts = parseMultipart(request);
      uploads.add(parts);
      final id = nextMedia++;
      return _json([
        {'id': id, 'url': '$_cdn$id.jpg', 'width': 800, 'height': 800}
      ]);
    }
    if (request.method == 'POST' && path == '/api/dogs') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = nextDog++;
      return _json(_dogJson(id, body['name'] as String), status: 201);
    }
    final avatar = RegExp(r'^/api/dogs/(\d+)/avatar$').firstMatch(path);
    if (avatar != null) {
      final dogId = int.parse(avatar.group(1)!);
      if (avatarStatus != 200) return _json({'error': {'code': 'X', 'message': '거절'}}, status: avatarStatus);
      if (request.method == 'PUT') {
        final mediaId = (jsonDecode(request.body) as Map)['mediaId'];
        avatars[dogId] = '$_cdn$mediaId.jpg';
        return _json(_dogJson(dogId, '보리', avatarUrl: avatars[dogId]));
      }
      if (request.method == 'DELETE') {
        avatars.remove(dogId);
        return _json(_dogJson(dogId, '보리'));
      }
    }
    if (request.method == 'GET' && path == '/api/dogs') {
      return _json([for (final e in avatars.entries) _dogJson(e.key, '보리', avatarUrl: e.value)]);
    }
    return _json({'error': 'no route $path'}, status: 404);
  }

  List<String> get avatarCalls => [
        for (final r in requests)
          if (r.url.path.contains('/avatar')) '${r.method} ${r.url.path}',
      ];
}

({_Server server, PetSync sync, PostMediaRepository media}) _fixture() {
  final server = _Server();
  final client = AuthedClient(inner: MockClient(server.call), baseUrl: _base, store: _FakeTokenStore());
  return (
    server: server,
    sync: PetSync(repository: WalkRepository(baseUrl: _base, client: client)),
    media: PostMediaRepository(baseUrl: _base, client: client),
  );
}

/// 진짜 디코더를 안 부른다 — 바이트를 그대로 800×800 JPEG 라고 친다.
Future<PreparedImage> _prepare(Uint8List original) async =>
    PreparedImage(bytes: original, width: 800, height: 800);

/// 진짜 JPEG — 미리보기(`Image.memory`)가 디코딩하므로 아무 바이트나 넣으면 "Invalid image data" 다.
final _photo = PickedImage(name: 'bori.jpg', bytes: gpsJpeg());

const _bori = DogProfile(serverId: 7, name: '보리', breed: '', size: DogSize.small, ageMonths: 30);
const _boriWithPhoto = DogProfile(
    serverId: 7, name: '보리', breed: '', size: DogSize.small, ageMonths: 30, photoUrl: '${_cdn}old.jpg');

void main() {
  setUp(() {
    replacePets(const []);
  });
  tearDown(() {
    replacePets(const []);
  });

  group('저장소 · 동기화', () {
    test('avatarUrl 을 읽고, 붙이기는 PUT · 떼기는 DELETE 다 — 응답의 아이로 목록의 그 자리를 갈아 끼운다', () async {
      final f = _fixture();
      replacePets(const [_bori]);

      final withPhoto = await f.sync.setPhoto(_bori, 41);
      expect(f.server.avatarCalls, ['PUT /api/dogs/7/avatar']);
      expect(jsonDecode(f.server.requests.last.body), {'mediaId': 41});
      expect(withPhoto.photoUrl, '${_cdn}41.jpg');
      expect(kMyPets.value.single.photoUrl, '${_cdn}41.jpg', reason: '목록도 서버 응답으로 바뀐다');
      expect(kMyDog.value?.photoUrl, '${_cdn}41.jpg');

      final cleared = await f.sync.clearPhoto(withPhoto);
      expect(f.server.avatarCalls.last, 'DELETE /api/dogs/7/avatar');
      expect(cleared.photoUrl, isNull);
      expect(kMyDog.value?.photoUrl, isNull);
    });

    test('서버에 없는 아이(serverId 없음)에는 붙일 수 없다', () async {
      final f = _fixture();
      expect(() => f.sync.setPhoto(const DogProfile(name: '임시', breed: '', size: DogSize.small, ageMonths: 1), 1),
          throwsA(isA<WalkFailure>()));
      expect(f.server.requests, isEmpty);
    });

    test('copyWith 는 사진을 지우는 길이 따로 있다 — null 을 넘기면 "그대로" 라서', () {
      expect(_boriWithPhoto.copyWith(name: '보리2').photoUrl, _boriWithPhoto.photoUrl);
      expect(_boriWithPhoto.copyWith(clearPhoto: true).photoUrl, isNull);
    });
  });

  group('DogAvatar', () {
    testWidgets('사진이 있으면 사진(원), 없으면 종 이모지', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Column(children: [
          DogAvatar(dog: _boriWithPhoto, size: 96, emojiSize: 60),
          DogAvatar(dog: _bori, size: 96, emojiSize: 60),
          DogAvatar(dog: null, size: 96, emojiSize: 60),
        ]),
      ));
      await tester.pump();

      expect(find.byKey(const Key('dog-photo')), findsOneWidget);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.whereType<Image>().where((i) => i.image is NetworkImage).length, 1);
      // 테스트에서는 네트워크 그림이 못 불러와 errorBuilder 의 이모지가 하나 더 그려진다 — 그것도 설계다.
      expect(images.where((i) => i.image is AssetImage).length, greaterThanOrEqualTo(2),
          reason: '사진 없는 아이와 아이 없음은 이모지');
      expect(tester.getSize(find.byKey(const Key('dog-photo'))), const Size(96, 96));
    });
  });

  group('등록 시트', () {
    Future<_Server> pumpSheet(WidgetTester tester, {FakeMediaPicker? picker}) async {
      final f = _fixture();
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PetRegistrationSheet(
              sync: f.sync,
              media: f.media,
              picker: picker ?? FakeMediaPicker((_) => [_photo]),
              prepare: _prepare,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return f.server;
    }

    testWidgets('사진을 고르면 PROFILE_IMAGE 로 올려 미리보기가 뜨고, 등록 뒤 그 아이에 붙인다', (tester) async {
      final server = await pumpSheet(tester);
      expect(find.text('사진 고르기 (선택)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pet-photo-pick')));
      await tester.pumpAndSettle();

      expect(server.uploads, hasLength(1));
      expect(partNamed(server.uploads.single, 'category').text, 'PROFILE_IMAGE', reason: '아이 사진은 글 사진과 다른 칸에 산다');
      expect(partNamed(server.uploads.single, 'files').filename, 'bori.jpg');
      expect(find.byKey(const Key('pet-photo-preview')), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '보리');
      await tester.tap(find.text('등록하기'));
      await tester.pumpAndSettle();

      final calls = [for (final r in server.requests) '${r.method} ${r.url.path}'];
      expect(calls, ['POST /media', 'POST /api/dogs', 'PUT /api/dogs/7/avatar'],
          reason: '등록이 먼저다 — 아이의 id 가 있어야 붙일 수 있다');
      expect(kMyPets.value.single.photoUrl, '${_cdn}41.jpg');
    });

    testWidgets('사진을 안 고르면 올리지도 붙이지도 않는다 — 등록만', (tester) async {
      final server = await pumpSheet(tester, picker: FakeMediaPicker((_) => const []));

      await tester.enterText(find.byType(TextField).first, '보리');
      await tester.tap(find.text('등록하기'));
      await tester.pumpAndSettle();

      expect([for (final r in server.requests) '${r.method} ${r.url.path}'], ['POST /api/dogs']);
      expect(kMyPets.value.single.photoUrl, isNull);
    });

    testWidgets('붙이기가 거절돼도 등록은 된 채다 — 아이는 남고 사진만 없다', (tester) async {
      final server = await pumpSheet(tester);
      server.avatarStatus = 400;

      await tester.tap(find.byKey(const Key('pet-photo-pick')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '보리');
      await tester.tap(find.text('등록하기'));
      await tester.pumpAndSettle();

      expect(server.avatarCalls, ['PUT /api/dogs/7/avatar']);
      expect(kMyPets.value.single.name, '보리', reason: '등록은 성공했다');
      expect(kMyPets.value.single.photoUrl, isNull);
    });
  });

  group('편집 화면', () {
    Future<_Server> pumpEdit(WidgetTester tester, DogProfile pet, {FakeMediaPicker? picker}) async {
      final f = _fixture();
      replacePets([pet]);
      selectPet(0);
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: EditScreen(
          pet: pet,
          sync: f.sync,
          media: f.media,
          picker: picker ?? FakeMediaPicker((_) => [_photo]),
          prepare: _prepare,
        ),
      ));
      await tester.pumpAndSettle();
      return f.server;
    }

    testWidgets('아바타를 누르면 고르고 올려 바로 서버에 붙인다 — 화면의 아이가 사진으로 바뀐다', (tester) async {
      final server = await pumpEdit(tester, _bori);
      expect(find.byKey(const Key('dog-photo')), findsNothing);
      expect(find.text('사진을 누르면 바꿀 수 있어요'), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit-photo-pick')));
      await tester.pumpAndSettle();

      expect(server.avatarCalls, ['PUT /api/dogs/7/avatar']);
      expect(partNamed(server.uploads.single, 'category').text, 'PROFILE_IMAGE');
      expect(kMyDog.value?.photoUrl, '${_cdn}41.jpg');
      expect(find.byKey(const Key('dog-photo')), findsOneWidget);
      expect(find.text('사진 지우기'), findsOneWidget);
      expect(find.text('사진을 바꿨어요'), findsOneWidget);
    });

    testWidgets('"사진 지우기" 는 DELETE 를 보내고 이모지로 돌아간다', (tester) async {
      final server = await pumpEdit(tester, _boriWithPhoto);
      expect(find.byKey(const Key('dog-photo')), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit-photo-clear')));
      await tester.pumpAndSettle();

      expect(server.avatarCalls, ['DELETE /api/dogs/7/avatar']);
      expect(kMyDog.value?.photoUrl, isNull);
      expect(find.byKey(const Key('dog-photo')), findsNothing);
      expect(find.text('사진을 지웠어요'), findsOneWidget);
    });

    testWidgets('고르기를 닫으면 아무것도 안 보낸다', (tester) async {
      final server = await pumpEdit(tester, _bori, picker: FakeMediaPicker((_) => const []));

      await tester.tap(find.byKey(const Key('edit-photo-pick')));
      await tester.pumpAndSettle();

      expect(server.requests, isEmpty);
    });
  });
}
