import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/places.dart';
import '../theme/community.dart';
import '../widgets/aurora.dart';
import 'create_screen.dart';
import 'post_detail_screen.dart';

/// 장소 상세 (placeDetail) — 장소별 감정 변화 + 이곳은 + 장소일기.
class PlaceDetailScreen extends StatelessWidget {
  final Place place;
  const PlaceDetailScreen({super.key, required this.place});

  static const _sig = LinearGradient(begin: Alignment(-0.7, -1), end: Alignment(0.7, 1), colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]);

  List<CommunityPost> get _diaries => kCommunityPosts.where((p) => p.loc == place.name).toList();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final to = kEmotions[place.to], from = kEmotions[place.from];
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 40, height: 40, alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0x80FFFFFF))),
                    child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
                  ),
                ),
                const SizedBox(width: 14),
                const Text('장소', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                children: [
                  _overviewCard(to, from),
                  const SizedBox(height: 14),
                  _aboutCard(),
                  const SizedBox(height: 14),
                  _writeCta(context),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
                    child: Row(children: const [
                      Icon(Icons.menu_book, size: 19, color: Color(0xFF8E7BFF)),
                      SizedBox(width: 7),
                      Text('이곳의 장소일기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (_diaries.isEmpty) _emptyDiaries() else for (final d in _diaries) ...[_diaryCard(context, d), const SizedBox(height: 12)],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _overviewCard(Emotion to, Emotion from) {
    return GlassCard(
      child: Column(children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 60, height: 60, alignment: Alignment.center,
              decoration: BoxDecoration(gradient: to.grad, borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: to.c2.withOpacity(0.33), blurRadius: 14, offset: const Offset(0, 6))]),
              child: Text(to.emoji, style: const TextStyle(fontSize: 26)),
            ),
            if (place.pet)
              Positioned(
                right: -4, bottom: -4,
                child: Container(
                  width: 22, height: 22, alignment: Alignment.center,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4)]),
                  child: const Text('🐾', style: TextStyle(fontSize: 11)),
                ),
              ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(place.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: T.textPrimary))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: to.c2.withOpacity(0.14), borderRadius: BorderRadius.circular(9)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.trending_up, size: 13, color: to.c2),
                    const SizedBox(width: 2),
                    Text('+${place.lift}%', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: to.c2)),
                  ]),
                ),
              ]),
              const SizedBox(height: 3),
              Text('${place.cat} · ${place.dist}', style: const TextStyle(fontSize: 12.5, color: Color(0xA8463C64))),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Container(height: 1, color: const Color(0x1F8C7BFF)),
        const SizedBox(height: 14),
        Row(children: [
          _dot(from, 28),
          const SizedBox(width: 7),
          const Icon(Icons.arrow_forward, size: 17, color: Color(0xFFBBB3CC)),
          const SizedBox(width: 7),
          _dot(to, 28),
          const SizedBox(width: 8),
          Text(place.from == place.to ? '${to.label} 유지' : '${from.label} → ${to.label}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3A3550))),
          const Spacer(),
          Text('${place.n}명의 발자취', style: const TextStyle(fontSize: 11.5, color: Color(0x99463C64))),
        ]),
      ]),
    );
  }

  Widget _aboutCard() {
    Widget mapBtn(IconData icon, Color ic, String label, String url) => Expanded(
          child: GestureDetector(
            onTap: () => _open(url),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0x66FFFFFF))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 16, color: ic),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
              ]),
            ),
          ),
        );
    final enc = Uri.encodeComponent(place.name);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.tips_and_updates, size: 19, color: Color(0xFFFF7A59)),
          SizedBox(width: 7),
          Text('이곳은', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ]),
        const SizedBox(height: 10),
        Text(place.about, style: const TextStyle(fontSize: 13.5, height: 1.65, color: Color(0xD63C345A))),
        const SizedBox(height: 14),
        Row(children: [
          mapBtn(Icons.map, const Color(0xFF33BFA6), '네이버 지도', 'https://map.naver.com/p/search/$enc'),
          const SizedBox(width: 9),
          mapBtn(Icons.map, const Color(0xFF5B79F5), '구글 지도', 'https://www.google.com/maps/search/$enc'),
        ]),
      ]),
    );
  }

  Widget _writeCta(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreateScreen(initialPlace: place))),
      child: Container(
        height: 56, alignment: Alignment.center,
        decoration: BoxDecoration(gradient: _sig, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x73D89BFF), blurRadius: 28, offset: Offset(0, 12))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.edit, size: 20, color: Colors.white),
          SizedBox(width: 8),
          Text('여기서 장소일기 쓰기', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }

  Widget _emptyDiaries() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(color: const Color(0x73FFFFFF), borderRadius: BorderRadius.circular(T.radius), border: Border.all(color: const Color(0x66FFFFFF))),
      child: Column(children: const [
        Icon(Icons.menu_book, size: 34, color: Color(0xFFCABFDC)),
        SizedBox(height: 10),
        Text('아직 공개된 장소일기가 없어요.\n첫 기록을 남겨보세요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xA8463C64))),
      ]),
    );
  }

  Widget _diaryCard(BuildContext context, CommunityPost d) {
    final from = kEmotions[d.from], to = kEmotions[d.to];
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: d))),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 34, height: 34, alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: to.grad),
              child: Text(d.nick.characters.first, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(width: 9),
            Text(d.nick, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const Spacer(),
            const Text('2026.06.27', style: TextStyle(fontSize: 11.5, color: Color(0x80463C64))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _dot(from, 22), const SizedBox(width: 6),
            const Icon(Icons.arrow_forward, size: 14, color: Color(0xFFBBB3CC)), const SizedBox(width: 6),
            _dot(to, 22), const SizedBox(width: 8),
            Text(d.from == d.to ? '${to.label} 유지' : '${from.label} → ${to.label}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3A3550))),
          ]),
          const SizedBox(height: 11),
          Text(d.story, style: const TextStyle(fontSize: 13.5, height: 1.55, color: Color(0xD13C345A))),
          const SizedBox(height: 11),
          Row(children: [
            const Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFFBBB3CC)),
            const SizedBox(width: 5),
            Text('댓글 ${d.commentCount}', style: const TextStyle(fontSize: 12, color: Color(0x99463C64))),
          ]),
        ]),
      ),
    );
  }

  Widget _dot(Emotion e, double s) => Container(
        width: s, height: s, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad),
        child: Text(e.emoji, style: TextStyle(fontSize: s * 0.5)),
      );
}
