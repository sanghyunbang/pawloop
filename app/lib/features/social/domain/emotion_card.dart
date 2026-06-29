/// 공유된 감정 카드 (소셜 "함께" 피드).
class EmotionCard {
  final int id;
  final String? handle; // null → 익명
  final String moodKey;
  final String? placeName;
  final String body;
  final String createdAt;

  /// 리액션 타입별 개수 (SAME/CHEER/CALM).
  final Map<String, int> reactions;

  /// 내가 누른 리액션 타입들.
  final List<String> myReactions;

  /// 댓글 수.
  final int commentCount;

  const EmotionCard({
    required this.id,
    required this.handle,
    required this.moodKey,
    required this.placeName,
    required this.body,
    required this.createdAt,
    required this.reactions,
    required this.myReactions,
    required this.commentCount,
  });

  factory EmotionCard.fromJson(Map<String, dynamic> j) => EmotionCard(
        id: (j['id'] as num).toInt(),
        handle: j['handle'] as String?,
        moodKey: (j['moodKey'] ?? '') as String,
        placeName: j['placeName'] as String?,
        body: (j['body'] ?? '') as String,
        createdAt: (j['createdAt'] ?? '').toString(),
        reactions: _intMap(j['reactions']),
        myReactions:
            (j['myReactions'] as List? ?? const []).map((e) => '$e').toList(),
        commentCount: (j['commentCount'] as num?)?.toInt() ?? 0,
      );

  static Map<String, int> _intMap(dynamic v) {
    final m = <String, int>{};
    if (v is Map) {
      v.forEach((k, val) => m['$k'] = (val as num?)?.toInt() ?? 0);
    }
    return m;
  }

  EmotionCard copyWith({
    Map<String, int>? reactions,
    List<String>? myReactions,
    int? commentCount,
  }) =>
      EmotionCard(
        id: id,
        handle: handle,
        moodKey: moodKey,
        placeName: placeName,
        body: body,
        createdAt: createdAt,
        reactions: reactions ?? this.reactions,
        myReactions: myReactions ?? this.myReactions,
        commentCount: commentCount ?? this.commentCount,
      );

  EmotionCard withReactions(Map<String, int> r, List<String> mine) =>
      copyWith(reactions: r, myReactions: mine);
}

/// 감정 카드 댓글.
class CardComment {
  final int id;
  final String? handle; // null → 익명
  final String body;
  final String createdAt;

  const CardComment({
    required this.id,
    required this.handle,
    required this.body,
    required this.createdAt,
  });

  factory CardComment.fromJson(Map<String, dynamic> j) => CardComment(
        id: (j['id'] as num).toInt(),
        handle: j['handle'] as String?,
        body: (j['body'] ?? '') as String,
        createdAt: (j['createdAt'] ?? '').toString(),
      );
}

/// 감정 리액션 3종 (좋아요 아님).
class Reactions {
  Reactions._();
  static const same = 'SAME';
  static const cheer = 'CHEER';
  static const calm = 'CALM';
  static const all = [same, cheer, calm];

  static String label(String type) {
    switch (type) {
      case same:
        return '나도 그랬어';
      case cheer:
        return '응원해';
      case calm:
        return '평온해 보여';
      default:
        return type;
    }
  }

  static String emoji(String type) {
    switch (type) {
      case same:
        return '🫶';
      case cheer:
        return '💪';
      case calm:
        return '🌿';
      default:
        return '·';
    }
  }
}
