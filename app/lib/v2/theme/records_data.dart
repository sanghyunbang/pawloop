/// 내 기록(myRecords) 데이터 — 핸드오프 calendar/records.

/// 전체 기록 카드 1건.
class MyRecord {
  final String title;
  final String date; // 표시용 '6월 12일'
  final String loc;
  final int from;
  final int to;
  final String weather; // '맑음 22°'
  final String story;
  const MyRecord({
    required this.title,
    required this.date,
    required this.loc,
    required this.from,
    required this.to,
    required this.weather,
    required this.story,
  });
}

const String kCalTitle = '2026년 6월 감정 캘린더';
const int kCalStreak = 2; // 연속 N일
const int kCalDays = 30; // 6월
const int kCalLeadBlanks = 1; // 2026-06-01 = 월요일 → 앞 빈칸 1
const int kCalToday = 29; // 오늘

/// 날짜 → 감정 인덱스 (기록 있는 날). (핸드오프 calMap)
const Map<int, int> kCalEmotions = {12: 4, 15: 0, 18: 5, 21: 1, 24: 2, 26: 4, 27: 0};

const List<MyRecord> kMyRecords = [
  MyRecord(
    title: '서울숲 아침 산책',
    date: '6월 12일',
    loc: '서울숲',
    from: 2,
    to: 4,
    weather: '맑음 22°',
    story: '면접 생각에 불안했는데, 숲을 한 바퀴 걷고 나니 마음이 한결 가벼워졌다.',
  ),
  MyRecord(
    title: '성수동 카페 나들이',
    date: '6월 15일',
    loc: '성수동',
    from: 1,
    to: 0,
    weather: '구름 24°',
    story: '울적한 날이었는데 볕 드는 창가에서 라떼 한 잔에 기분이 풀렸다.',
  ),
];
