// 산책 사진의 자리 둘 — 문서 폴더의 파일과 서버로의 올리기 (#450).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/image_prep.dart';
import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_photos.dart';

class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'token';
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('walk_photos_test_');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('WalkPhotoStore', () {
    test('찍은 바이트를 문서 폴더 아래 walk_photos/<산책> 에 두고 경로를 돌려준다', () async {
      final store = WalkPhotoStore(root: () async => tmp);

      final path = await store.save('1757800000000', Uint8List.fromList([1, 2, 3]));

      expect(path, contains('${WalkPhotoStore.folder}${Platform.pathSeparator}1757800000000'));
      expect(await File(path).readAsBytes(), [1, 2, 3]);
    });

    test('산책 이름의 이상한 글자는 폴더 이름에서 빠진다 — 경로 구분자가 들어가면 폴더가 갈라진다', () async {
      final store = WalkPhotoStore(root: () async => tmp);

      final path = await store.save('a/b:c', Uint8List.fromList([9]));

      expect(path, isNot(contains('a/b:c')));
      expect(await File(path).exists(), isTrue);
    });

    test('discard 는 파일을 지우고, 이미 없는 파일은 조용히 넘어간다', () async {
      final store = WalkPhotoStore(root: () async => tmp);
      final path = await store.save('k', Uint8List.fromList([1]));

      await store.discard([path, '${tmp.path}${Platform.pathSeparator}없는파일.jpg']);

      expect(await File(path).exists(), isFalse);
    });

    test('read 는 파일 바이트를 주고, 없는 파일이면 null — 시트가 죽지 않는다', () async {
      final store = WalkPhotoStore(root: () async => tmp);
      final path = await store.save('k', Uint8List.fromList([4, 5]));

      expect(await store.read(path), [4, 5]);
      expect(await store.read('${tmp.path}${Platform.pathSeparator}없는파일.jpg'), isNull);
    });
  });

  group('WalkPhotoUploader', () {
    test('경로를 읽어 다시 인코딩한 것을 WALK_IMAGE 로 올리고 서버 id 를 돌려준다', () async {
      final file = File('${tmp.path}${Platform.pathSeparator}shot.jpg');
      await file.writeAsBytes([7, 7, 7]);
      http.MultipartRequest? sent;
      final media = PostMediaRepository(
        baseUrl: 'https://api.example.test',
        client: AuthedClient(
          // multipart 는 스트림으로 보내므로 `MockClient.streaming` 이어야 원래 요청(필드 · 파일)이 보인다.
          inner: MockClient.streaming((request, bodyStream) async {
            sent = request as http.MultipartRequest;
            await bodyStream.drain<void>();
            return http.StreamedResponse(
                Stream.value(utf8.encode(
                    '[{"id":31,"key":"walks/1/a.jpg","url":"https://cdn/a.jpg","category":"WALK_IMAGE","status":"ready"}]')),
                200,
                headers: {'content-type': 'application/json'});
          }),
          baseUrl: 'https://api.example.test',
          store: _NoTokens(),
        ),
      );
      final uploader = WalkPhotoUploader(
        media: media,
        prepare: (bytes) async => PreparedImage(bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]), width: 1200, height: 1600),
      );

      final id = await uploader.upload(file.path);

      expect(id, 31);
      expect(sent, isNotNull);
      expect(sent!.fields['category'], 'WALK_IMAGE');
      expect(sent!.fields['width'], '1200');
      expect(sent!.fields['height'], '1600');
      expect(sent!.files.single.filename, 'walk.jpg');
    });
  });
}
