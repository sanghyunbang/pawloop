import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:heat_trip_flutter/features/record/data/dto/schedule_request.dart';
import 'package:heat_trip_flutter/features/record/data/model/schedule_response.dart';
import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/errors/app_exception.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';

class ScheduleRepositoryImpl {
  final String baseUrl = Env.apiBase ?? '';

  /// 인증 헤더 부착과 401 갱신은 전부 여기가 한다 (#11).
  final AuthedClient _client = AuthedClient.instance;

  // ------------------- 스케쥴 생성
  Future<String?> schedulePost(ScheduleRequest request) async {
    final url = Uri.parse('$baseUrl/public/schedules');

    final response = await _client.postJson(url, body: request.toJson());

    if (response.statusCode == 201) {
      return null;
    } else {
      if (kDebugMode) debugPrint('[X] 포스팅 실패: ${response.statusCode}');
      return '저장 실패 (${response.statusCode})';
    }
  }

  // ------------------- 스케쥴 전체 조회
  Future<List<ScheduleResponse>> fetchSchedules() async {
    final url = Uri.parse('$baseUrl/public/schedules');
    final response = await _client.getJson(url);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => ScheduleResponse.fromJson(item)).toList();
    }
    // 스케줄이 전혀 없을 때 204를 빈 리스트로 간주
    if (response.statusCode == 204) {
      return <ScheduleResponse>[];
    }
    throw AuthRequiredException();
  }

  // ------------------- 스케쥴 삭제
  Future<String?> deleteSchedule(int scheduleId) async {
    final url = Uri.parse('$baseUrl/public/schedules/$scheduleId');
    final response = await _client.deleteJson(url);

    if (response.statusCode == 200 || response.statusCode == 204) {
      return null;
    } else {
      if (kDebugMode) debugPrint('[X] 삭제 실패: ${response.statusCode}');
      return '삭제 실패 (${response.statusCode})';
    }
  }

  // ------------------- D-Day 계산
  String getDDayText(DateTime from, DateTime to) {
    final now = DateTime.now();
    if (now.isAfter(to)) {
      return '종료됨';
    } else {
      final daysLeft = from.difference(now).inDays;
      return 'D-${daysLeft + 1}';
    }
  }

  // ------------------- 현재 진행 중인 스케쥴 필터링
  List<ScheduleResponse> getOngoingSchedules(List<ScheduleResponse> all) {
    final now = DateTime.now();
    return all.where((schedule) {
      return now.isAfter(schedule.dateFrom.subtract(const Duration(days: 1))) &&
          now.isBefore(schedule.dateTo.add(const Duration(days: 1)));
    }).toList();
  }

  // ------------------- 조건에 따른 필터링
  List<ScheduleResponse> filterSchedules({
    required List<ScheduleResponse> all,
    String title = '',
    DateTime? date,
    String filterType = '전체', // '전체', '지나간', '앞으로'
  }) {
    final now = DateTime.now();

    return all.where((schedule) {
      final titleMatch = schedule.title.toLowerCase().contains(
        title.toLowerCase(),
      );

      final dateMatch =
          date == null ||
          (date.isAfter(schedule.dateFrom.subtract(const Duration(days: 1))) &&
              date.isBefore(schedule.dateTo.add(const Duration(days: 1))));

      final isPast = schedule.dateTo.isBefore(now);
      final isFuture = schedule.dateFrom.isAfter(now);

      final filterMatch =
          filterType == '전체' ||
          (filterType == '지나간' && isPast) ||
          (filterType == '앞으로' && isFuture);

      return titleMatch && dateMatch && filterMatch;
    }).toList();
  }
}
