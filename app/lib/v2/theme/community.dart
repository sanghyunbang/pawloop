import 'package:flutter/material.dart';

/// 장소일기 댓글.
class PostComment {
  final String nick;
  final String text;
  const PostComment(this.nick, this.text);
}

/// 장소일기 (커뮤니티 글) — 핸드오프 communityData.
class CommunityPost {
  final String nick;
  final String title;
  final String community; // 대표 카테고리
  final List<String> communities; // 복수 카테고리(없으면 [community])
  final int from;
  final int to;
  final String? loc;
  final String story;
  final List<int> base; // [나도그랬어, 응원해, 평온해보여]
  final List<PostComment> cmts;
  const CommunityPost({
    required this.nick,
    required this.title,
    required this.community,
    this.communities = const [],
    required this.from,
    required this.to,
    this.loc,
    required this.story,
    required this.base,
    this.cmts = const [],
  });

  List<String> get cats => communities.isNotEmpty ? communities : [community];
  int get commentCount => cmts.length;
}

/// 커뮤니티 카테고리(필터).
const List<String> kCommunities = ['전체', '취업·진로', '연애·관계', '일·업무', '외로움', '번아웃', '마이펫', '막연함'];

/// 카테고리 색.
const Map<String, Color> kCatColor = {
  '취업·진로': Color(0xFF5B79F5),
  '연애·관계': Color(0xFFFF6B7E),
  '일·업무': Color(0xFFFF8F63),
  '외로움': Color(0xFF7E68F0),
  '번아웃': Color(0xFF33BFA6),
  '마이펫': Color(0xFFFF9E7D),
  '막연함': Color(0xFF9B8FC4),
};
Color catColor(String c) => kCatColor[c] ?? const Color(0xFF8E7BFF);

/// 감정 리액션 3종.
const List<String> kReactionLabels = ['나도 그랬어', '응원해', '평온해 보여'];
const List<String> kReactionEmojis = ['🫶', '💪', '🌿'];

const List<CommunityPost> kCommunityPosts = [
  CommunityPost(nick: '빗소리', title: '면접 전날, 서울숲에서', community: '취업·진로', from: 2, to: 4, loc: '서울숲', story: '면접 전날 불안에 잠 못 들다 서울숲을 걸었어요. 호숫가를 한 바퀴 도니 마음이 천천히 가라앉았어요.', base: [1, 0, 2], cmts: [PostComment('온기', '저도 여기서 위로받았어요 🌿'), PostComment('민트', '내일 면접 잘 보길 응원해요!')]),
  CommunityPost(nick: '밤샘러', title: '스무 번째 탈락, 그래도 버팁니다', community: '취업·진로', from: 3, to: 2, story: '벌써 스무 번째 탈락이에요. 그래도 오늘 또 이력서를 고쳐 써봅니다. 다들 어떻게 버티세요?', base: [4, 3, 0], cmts: [PostComment('합격기원', '그 꾸준함이 결국 빛 봐요.')]),
  CommunityPost(nick: '워킹독맘', title: '야근 끝, 강아지와 밤 산책', community: '번아웃', communities: ['번아웃', '마이펫'], from: 3, to: 4, loc: '한강 뚝섬', story: '야근으로 지친 날, 강아지랑 강변을 걷다 보니 쌓였던 스트레스가 스르륵 풀렸어요. 반려견은 나의 번아웃 치료제.', base: [3, 2, 2], cmts: [PostComment('집사', '우리도 야간 산책해요 🐶'), PostComment('댕댕맘', '강변 산책 최고죠')]),
  CommunityPost(nick: '익명', title: '3년 연애가 끝났어요', community: '연애·관계', from: 1, to: 1, story: '3년 만난 사람과 헤어졌어요. 시간이 약이라는 말, 정말일까요.', base: [6, 2, 1], cmts: [PostComment('토닥', '천천히 흘려보내도 괜찮아요.'), PostComment('봄날', '저도 그랬어요. 분명 나아져요.')]),
  CommunityPost(nick: '두근', title: '화가 머리끝까지 났던 날', community: '번아웃', from: 3, to: 4, loc: '서울숲', story: '화가 머리끝까지 났던 날, 벤치에 앉아 바람을 맞으니 신기하게 풀렸다.', base: [3, 1, 0], cmts: [PostComment('바다', '바람이 약이죠')]),
  CommunityPost(nick: '하루', title: '혼자인 오후를 채운 라떼 한 잔', community: '외로움', from: 1, to: 0, loc: '성수 연무장길', story: '울적한 오후, 볕 좋은 골목 카페에서 라떼 한 잔에 기분이 환기됐어요.', base: [1, 0, 0]),
  CommunityPost(nick: '익명', title: '좋아하는 전시 앞에서', community: '막연함', from: 4, to: 5, loc: '디뮤지엄', story: '평온하던 마음이 좋아하는 전시 앞에서 설렘으로 가득 찼어요.', base: [0, 2, 0]),
  CommunityPost(nick: '온기', title: '강바람에 화를 식히고', community: '번아웃', from: 3, to: 4, loc: '한강 뚝섬', story: '화가 잔뜩 났던 날, 강바람 맞으니 거짓말처럼 풀렸다.', base: [2, 1, 1], cmts: [PostComment('빗소리', '노을 시간에 가면 더 좋아요!')]),
  CommunityPost(nick: '바람', title: '복잡한 머리, 남산 둘레길에서', community: '막연함', from: 2, to: 4, loc: '남산 둘레길', story: '복잡한 생각을 잔뜩 안고 올랐는데, 트인 전망을 보니 마음이 정리됐어요.', base: [0, 1, 0]),
  CommunityPost(nick: '댕댕맘', title: '강아지와 노을 산책', community: '마이펫', from: 2, to: 4, loc: '한강 뚝섬', story: '불안한 하루였는데 우리 강아지랑 강변을 걸으니 마음이 사르르 풀렸어요. 역시 산책이 최고.', base: [2, 1, 3], cmts: [PostComment('집사', '댕댕이 사진 보고 싶어요 🐶')]),
];
