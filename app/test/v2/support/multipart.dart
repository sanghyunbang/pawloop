// `MockClient` 가 받은 multipart 요청을 파트로 가른다 — 업로드 테스트가 "어떤 필드와
// 어떤 바이트가 나갔는가" 를 값으로 재기 위한 것.
//
// `MockClient` 는 `MultipartRequest` 를 바이트로 굽힌 `http.Request` 를 넘긴다. latin1 은
// 바이트 ↔ 문자가 1:1 이라 경계 문자열로 자르고 다시 바이트로 돌려도 손실이 없다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class MultipartPart {
  final Map<String, String> headers;
  final Uint8List body;

  MultipartPart(this.headers, this.body);

  String? _disposition(String key) =>
      RegExp('$key="([^"]*)"').firstMatch(headers['content-disposition'] ?? '')?.group(1);

  String? get name => _disposition('name');
  String? get filename => _disposition('filename');
  String? get contentType => headers['content-type'];
  String get text => utf8.decode(body);
}

List<MultipartPart> parseMultipart(http.Request request) {
  final contentType = request.headers['content-type'] ?? '';
  final boundary = RegExp(r'boundary=([^;]+)').firstMatch(contentType)?.group(1);
  if (boundary == null) throw StateError('multipart 가 아니다: $contentType');

  final raw = latin1.decode(request.bodyBytes);
  final parts = <MultipartPart>[];
  for (var chunk in raw.split('--$boundary')) {
    if (chunk.isEmpty || chunk.startsWith('--')) continue; // 머리말 · 꼬리 `--`
    if (chunk.startsWith('\r\n')) chunk = chunk.substring(2);
    final split = chunk.indexOf('\r\n\r\n');
    if (split < 0) continue;
    final headers = <String, String>{};
    for (final line in chunk.substring(0, split).split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        headers[line.substring(0, colon).trim().toLowerCase()] = line.substring(colon + 1).trim();
      }
    }
    var body = chunk.substring(split + 4);
    if (body.endsWith('\r\n')) body = body.substring(0, body.length - 2);
    parts.add(MultipartPart(headers, Uint8List.fromList(latin1.encode(body))));
  }
  return parts;
}

/// 이름으로 파트 하나. 없으면 실패 — 테스트가 잡는다.
MultipartPart partNamed(List<MultipartPart> parts, String name) =>
    parts.firstWhere((p) => p.name == name, orElse: () => throw StateError('파트 $name 이 없다'));
