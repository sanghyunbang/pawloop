/// 흐름(insight) 화면 데이터 — 핸드오프 chart 데이터.

/// 상단 통계 3종.
class InsightStat {
  final String value;
  final String label;
  final String tipKey; // 'total' | 'better' | 'places'
  const InsightStat(this.value, this.label, this.tipKey);
}

const List<InsightStat> kInsightStats = [
  InsightStat('7', '총 기록', 'total'),
  InsightStat('8/10', '나아진 비율', 'better'),
  InsightStat('5곳', '나의 장소', 'places'),
];

/// 통계 툴팁(ℹ️).
const Map<String, (String, String)> kStatTips = {
  'total': ('총 기록', '지금까지 남긴 마음 기록의 총 개수예요.'),
  'better': ('나아진 비율', '마음을 기록한 10번 중, 떠날 무렵 도착했을 때보다 나아져 있던 적이 8번이에요. 장소와 시간이 내 마음을 얼마나 자주 풀어줬는지 보여줘요.'),
  'places': ('나의 장소', '마음의 변화를 기록한 장소의 수예요.'),
};

/// 주간 마음 캔들 (월~일). 점수 0~100. (핸드오프 WEEK)
class Candle {
  final String lab;
  final int o, c, h, l; // 시가/종가/고가/저가
  const Candle(this.lab, this.o, this.c, this.h, this.l);
  bool get up => c >= o;
}

const List<Candle> kWeekCandles = [
  Candle('월', 45, 66, 70, 40),
  Candle('화', 66, 52, 72, 48),
  Candle('수', 50, 80, 84, 46),
  Candle('목', 80, 64, 84, 60),
  Candle('금', 60, 84, 90, 56),
  Candle('토', 84, 88, 92, 80),
  Candle('일', 38, 84, 84, 25), // 오늘
];
const int kTodayCandle = 6; // '일'

/// 차트 가이드선 (점수, 라벨).
const List<(int, String)> kGridLines = [(84, '기쁨·설렘'), (66, '평온'), (30, '불안·슬픔')];

/// 하루의 흐름 (시간대, 감정 인덱스). (핸드오프 DAY)
const List<(String, int)> kDayFlow = [('아침', 2), ('점심', 1), ('오후', 4), ('저녁', 0)];

/// 주간 통계 4종.
const List<(String, String)> kWeekStats = [
  ('주간 평균 기분', '74점'),
  ('최고의 날', '토요일'),
  ('가장 흔들린 날', '일요일'),
  ('나아진 날', '5일'),
];

const String kChartInsight = '이번 주, 당신의 마음은 아침에 가장 자주 흔들렸고 오후를 지나며 회복됐어요.';

/// 나를 바꿔준 곳 (자주 마음이 나아진 장소). (핸드오프 myShiftsData)
class MyShift {
  final String name;
  final int from, to;
  final String count;
  const MyShift(this.name, this.from, this.to, this.count);
}

const List<MyShift> kMyShifts = [
  MyShift('서울숲', 2, 4, '3회'),
  MyShift('성수동 책방', 1, 0, '2회'),
  MyShift('한강 뚝섬', 3, 4, '2회'),
];
