// 코스 — 내가 걸은 길 중에 "여기 좋다" 고 남긴 것 (#339).
//
// **선을 보내지 않는다.** `walkId` 만 보내면 서버가 그 산책의 선을 베껴 와 양 끝 100m 를
// 자른다. 앱이 자른 선을 보내는 모양이면 "잘랐다" 는 약속을 앱 버전마다 다시 지켜야 하고,
// 안 자르는 옛 앱 하나가 그 사람의 집 앞을 공개한다. 미리보기용 사본은
// `domain/course_path.dart` 에 있고, 저장 뒤에는 **서버가 돌려준 선**을 그린다.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../core/net/authed_client.dart';

/// 코스 하나 — 계약의 `Course`.
class Course {
  final int id;

  /// 어느 산책에서 왔나. **그 산책을 지우면 `null`** 이다 — 코스는 남는다.
  final int? walkId;

  final String name;
  final String? note;

  /// `leash`(목줄 규정) · `poopbag`(배변봉투통) · `shade`(그늘·물).
  final List<String> tags;

  /// 잘라 낸 선(`[경도, 위도]`). **목록에서는 시작점 하나뿐**이고 상세에서만 전체가 온다.
  final List<List<double>> path;

  /// 자른 **뒤**의 길이. 원래 산책의 거리가 아니다.
  final int distanceM;
  final int durationS;

  /// `private` 또는 `public`.
  final String visibility;

  /// 내 코스인가. 공개 목록에서 내 것을 가리는 데 쓴다.
  final bool mine;

  final DateTime createdAt;

  const Course({
    required this.id,
    required this.name,
    required this.distanceM,
    required this.durationS,
    required this.visibility,
    required this.mine,
    required this.createdAt,
    this.walkId,
    this.note,
    this.tags = const [],
    this.path = const [],
  });

  bool get isPublic => visibility == 'public';

  double get km => distanceM / 1000.0;

  /// 목록에서 지도에 점을 찍을 자리. 선이 없으면 `null`.
  List<double>? get start => path.isEmpty ? null : path.first;

  /// 모양이 다르면 `null` — 하나가 이상하다고 목록 전체를 잃지 않는다.
  static Course? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String) return null;

    final rawPath = json['path'];
    final path = rawPath is List
        ? rawPath
            .whereType<List>()
            .map((p) => p.whereType<num>().map((n) => n.toDouble()).toList())
            .where((p) => p.length == 2)
            .toList()
        : <List<double>>[];

    final rawTags = json['tags'];
    return Course(
      id: id,
      walkId: (json['walkId'] as num?)?.toInt(),
      name: name,
      note: json['note'] as String?,
      tags: rawTags is List ? rawTags.whereType<String>().toList() : const [],
      path: path,
      distanceM: (json['distanceM'] as num?)?.toInt() ?? 0,
      durationS: (json['durationS'] as num?)?.toInt() ?? 0,
      visibility: json['visibility'] as String? ?? 'private',
      mine: json['mine'] == true,
      createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal() ?? DateTime.now(),
    );
  }

  static List<Course> parseList(Object? json) {
    if (json is! List) return const [];
    return json.map(Course.tryParse).whereType<Course>().toList();
  }
}

/// 코스를 만들 수 없는 이유. 화면이 그대로 말한다 — "실패했어요" 로 뭉개지 않는다.
enum CourseFailureKind {
  /// 경로가 없거나 양 끝을 자르면 남는 것이 없다(300m 쯤은 걸어야 한다).
  tooShort,

  /// 그 산책·코스가 없거나 내 것이 아니다.
  notFound,

  /// 연결이 없다. 다시 보내면 된다.
  network,
}

class CourseFailure implements Exception {
  final CourseFailureKind kind;
  final String? message;

  const CourseFailure(this.kind, {this.message});

  @override
  String toString() => 'CourseFailure($kind, $message)';
}

class CourseRepository {
  static const Duration timeout = Duration(seconds: 12);

  final String baseUrl;
  final AuthedClient _authed;

  CourseRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = (baseUrl ?? Env.apiBase).replaceAll(RegExp(r'/+$'), ''),
        _authed = client ?? AuthedClient.instance;

  /// 산책 하나를 코스로. **선은 안 보낸다** — 서버가 베껴 와 자른다.
  Future<Course> create({
    required int walkId,
    required String name,
    String? note,
    List<String> tags = const [],
    bool isPublic = false,
  }) async {
    final json = await _send(() => _authed.postJson(
          Uri.parse('$baseUrl/api/courses'),
          body: {
            'walkId': walkId,
            'name': name,
            if (note != null && note.isNotEmpty) 'note': note,
            if (tags.isNotEmpty) 'tags': tags,
            'visibility': isPublic ? 'public' : 'private',
          },
        ));
    final course = Course.tryParse(json);
    if (course == null) throw const CourseFailure(CourseFailureKind.network);
    return course;
  }

  /// 내 코스 목록. 선은 시작점 하나뿐이다.
  Future<List<Course>> mine() async =>
      Course.parseList(await _send(() => _authed.getJson(Uri.parse('$baseUrl/api/courses/me'))));

  /// 공개 코스 한 벌 — 지도의 "이웃 코스". **좌표를 안 보낸다**(A안 #235).
  Future<List<Course>> publicCourses() async =>
      Course.parseList(await _send(() => _authed.getJson(Uri.parse('$baseUrl/api/courses/public'))));

  /// 하나 — 선을 실어. 내 것이거나 공개된 것만.
  Future<Course> one(int courseId) async {
    final course = Course.tryParse(
        await _send(() => _authed.getJson(Uri.parse('$baseUrl/api/courses/$courseId'))));
    if (course == null) throw const CourseFailure(CourseFailureKind.network);
    return course;
  }

  Future<Course> setVisibility(int courseId, {required bool isPublic}) async {
    final course = Course.tryParse(await _send(() => _authed.putJson(
          Uri.parse('$baseUrl/api/courses/$courseId/visibility'),
          body: {'visibility': isPublic ? 'public' : 'private'},
        )));
    if (course == null) throw const CourseFailure(CourseFailureKind.network);
    return course;
  }

  Future<void> delete(int courseId) async {
    await _send(() => _authed.deleteJson(Uri.parse('$baseUrl/api/courses/$courseId')));
  }

  /// 한 번의 왕복. **상태 코드를 실패의 종류로 옮기는 곳이 여기 하나다.**
  ///
  /// 400 은 "이 산책으로는 코스를 못 만든다"(짧다·경로가 없다)라서 화면이 그 이유를 그대로
  /// 말한다. 404 는 남의 것과 없는 것을 구분하지 않는 서버의 답이고, 나머지는 네트워크다.
  Future<Object?> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } catch (_) {
      throw const CourseFailure(CourseFailureKind.network);
    }

    if (res.statusCode == 400) {
      throw CourseFailure(CourseFailureKind.tooShort, message: _messageOf(res.bodyBytes));
    }
    if (res.statusCode == 404) throw const CourseFailure(CourseFailureKind.notFound);
    if (res.statusCode >= 400) throw const CourseFailure(CourseFailureKind.network);
    if (res.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static String? _messageOf(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return null;
    try {
      final json = jsonDecode(utf8.decode(bodyBytes));
      if (json is Map && json['error'] is Map) {
        return (json['error'] as Map)['message'] as String?;
      }
    } catch (_) {
      // 본문이 계약과 다르면 이유를 모르는 것이다 — 지어내지 않는다.
    }
    return null;
  }
}
