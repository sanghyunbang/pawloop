import 'package:flutter/foundation.dart';
import 'package:heat_trip_flutter/features/profile/domain/repository/feedback_repository.dart';
import 'package:heat_trip_flutter/features/profile/data/dto/feedback_request.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';

class FeedbackRepositoryImpl implements FeedbackRepository {
  final String baseUrl = Env.apiBase ?? '';

  /// 인증 헤더 부착과 401 갱신은 전부 여기가 한다 (#11).
  final AuthedClient _client = AuthedClient.instance;

  @override
  Future<bool> sendFeedback({
    required String content,
    String? category,
    String? appVersion,
    String? deviceInfo,
  }) async {
    final uri = Uri.parse('$baseUrl/feedback');
    final req = FeedbackRequest(
      content: content,
      category: category,
      appVersion: appVersion,
      deviceInfo: deviceInfo,
    );

    try {
      final res = await _client.postJson(uri, body: req.toJson());

      if (res.statusCode == 200) return true;

      if (kDebugMode) {
        debugPrint('[X] sendFeedback 실패: ${res.statusCode}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[X] sendFeedback 예외: ${e.runtimeType}');
      }
      return false;
    }
  }
}
