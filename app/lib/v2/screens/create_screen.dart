import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/situations.dart';
import '../theme/places.dart';
import '../theme/community.dart';
import '../widgets/aurora.dart';
import 'pin_picker_screen.dart';

/// 기록 작성 (create) — 장소일기/심플일기. 도착→떠날 감정, 상황, 공개설정.
class CreateScreen extends StatefulWidget {
  final Place? initialPlace; // 장소 상세 "여기서 장소일기 쓰기"에서 prefill
  const CreateScreen({super.key, this.initialPlace});
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  String type = 'place'; // 'place' | 'diary'
  final _title = TextEditingController();
  final _story = TextEditingController();
  String? placeName;
  int cFrom = 2; // 불안
  int cTo = 4; // 평온

  @override
  void initState() {
    super.initState();
    final p = widget.initialPlace;
    if (p != null) {
      placeName = p.name;
      cFrom = p.from;
      cTo = p.to;
    }
  }
  int cSitu = 0; // 취업·진로
  bool cPublic = true;
  final Set<String> cComms = {'취업·진로'};

  static const _sig = LinearGradient(begin: Alignment(-0.7, -1), end: Alignment(0.7, 1), colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]);
  static const _coral = Color(0xFFFF7A59);

  @override
  void dispose() {
    _title.dispose();
    _story.dispose();
    super.dispose();
  }

  bool get _place => type == 'place';

  void _save() {
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('기록이 저장됐어요 ✨'), duration: Duration(milliseconds: 1500)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _modeToggle(),
                  const SizedBox(height: 14),
                  _basicCard(),
                  const SizedBox(height: 14),
                  _shiftCard(),
                  const SizedBox(height: 14),
                  _situCard(),
                  const SizedBox(height: 14),
                  _photoCard(),
                  const SizedBox(height: 14),
                  _storyCard(),
                  const SizedBox(height: 14),
                  _publicCard(),
                  const SizedBox(height: 18),
                  _saveButton(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x80FFFFFF)),
              ),
              child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          const Text('기록 작성', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: _save,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Text('저장', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF8E7BFF))),
            ),
          ),
        ]),
      );

  Widget _modeToggle() {
    Widget seg(String v, String label) {
      final on = type == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => type = v),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: on ? _sig : null, borderRadius: BorderRadius.circular(12)),
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textMuted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xC2FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(children: [seg('place', '장소일기'), seg('diary', '심플일기')]),
    );
  }

  // 라벨 + 입력박스 헬퍼
  Widget _label(String t) => Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: T.textSecondary));

  BoxDecoration get _fieldDeco => BoxDecoration(
        color: const Color(0xB3FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x2E8C7BFF)),
      );

  Widget _basicCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('제목'),
        const SizedBox(height: 7),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: TextField(
            controller: _title,
            style: const TextStyle(fontSize: 14, color: T.textPrimary),
            decoration: const InputDecoration(
              hintText: '예: 서울숲에서 숨 고른 오후',
              hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
              border: InputBorder.none, isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('날짜'),
              const SizedBox(height: 7),
              Container(
                decoration: _fieldDeco,
                padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
                child: Row(children: const [
                  Text('06.29', style: TextStyle(fontSize: 14, color: Color(0xFF3A3550))),
                  Spacer(),
                  Icon(Icons.calendar_month, size: 18, color: T.textMuted),
                ]),
              ),
            ]),
          ),
          if (_place) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('장소'),
                const SizedBox(height: 7),
                GestureDetector(
                  onTap: _openPlacePicker,
                  child: Container(
                    decoration: _fieldDeco,
                    padding: const EdgeInsets.fromLTRB(13, 13, 12, 13),
                    child: Row(children: [
                      const Icon(Icons.place, size: 17, color: Color(0xFFFF9E7D)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(placeName ?? '장소 선택',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: placeName == null ? T.textMuted : const Color(0xFF3A3550))),
                      ),
                      const Icon(Icons.expand_more, size: 18, color: Color(0xFFBBB3CC)),
                    ]),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _shiftCard() {
    final f = kEmotions[cFrom], t = kEmotions[cTo];
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(_place ? '이곳에서 마음의 변화' : '오늘 마음의 변화',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
          if (_place) ...[
            const Spacer(),
            const Flexible(
              child: Text('이 기록이 다른 사람의 길잡이가 돼요',
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: Color(0x99463C64))),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x8CFFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x298C7BFF)),
          ),
          child: Row(children: [
            _orb(f, 40),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward, size: 20, color: Color(0xFFBBB3CC)),
            const SizedBox(width: 10),
            _orb(t, 40),
            const SizedBox(width: 12),
            Text(cFrom == cTo ? '${t.label} 유지' : '${f.label} → ${t.label}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF3A3550))),
          ]),
        ),
        const SizedBox(height: 16),
        _label(_place ? '도착했을 때의 마음' : '하루 시작 마음'),
        const SizedBox(height: 9),
        _emoGrid(cFrom, (i) => setState(() => cFrom = i)),
        const SizedBox(height: 16),
        _label(_place ? '떠날 때의 마음' : '지금 마음'),
        const SizedBox(height: 9),
        _emoGrid(cTo, (i) => setState(() => cTo = i)),
        const SizedBox(height: 16),
        _label('날씨'),
        const SizedBox(height: 7),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(children: const [
            Icon(Icons.wb_sunny, size: 19, color: Color(0xFFFF9E7D)),
            SizedBox(width: 9),
            Text('맑음 · 24°C', style: TextStyle(fontSize: 14, color: Color(0xFF3A3550))),
          ]),
        ),
      ]),
    );
  }

  Widget _orb(Emotion e, double s) => Container(
        width: s, height: s, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad,
            boxShadow: [BoxShadow(color: e.c2.withOpacity(0.38), blurRadius: 10, offset: const Offset(0, 4))]),
        child: e.icon((s * 0.45) * 1.4),
      );

  Widget _emoGrid(int selected, void Function(int) onPick) {
    Widget chip(int i) {
      final e = kEmotions[i];
      final on = i == selected;
      return GestureDetector(
        onTap: () => onPick(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? e.grad : null,
            color: on ? null : const Color(0xB3FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? Colors.transparent : const Color(0x66FFFFFF)),
            boxShadow: on ? [BoxShadow(color: e.c2.withOpacity(0.32), blurRadius: 12, offset: const Offset(0, 5))] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            e.icon(21),
            const SizedBox(width: 5),
            Text(e.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
          ]),
        ),
      );
    }

    Widget rowOf(int a, int b, int c) => Row(children: [
          Expanded(child: chip(a)), const SizedBox(width: 8),
          Expanded(child: chip(b)), const SizedBox(width: 8),
          Expanded(child: chip(c)),
        ]);
    return Column(children: [rowOf(0, 1, 2), const SizedBox(height: 8), rowOf(3, 4, 5)]);
  }

  Widget _situCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Text('무엇이 마음을 움직였나요?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
          SizedBox(width: 6),
          Icon(Icons.auto_awesome, size: 16, color: Color(0xFFD89BFF)),
        ]),
        const SizedBox(height: 6),
        const Text('AI 추천과 마음 패턴 분석에 함께 쓰여요.', style: TextStyle(fontSize: 12, color: Color(0xA8463C64))),
        const SizedBox(height: 13),
        for (int r = 0; r < 3; r++) ...[
          if (r > 0) const SizedBox(height: 9),
          Row(children: [
            Expanded(child: _situChip(r * 2)),
            const SizedBox(width: 9),
            Expanded(child: _situChip(r * 2 + 1)),
          ]),
        ],
      ]),
    );
  }

  Widget _situChip(int i) {
    final s = kSituations[i];
    final on = i == cSitu;
    return GestureDetector(
      onTap: () => setState(() => cSitu = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: on ? const Color(0x24FF7A59) : const Color(0x99FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? _coral : const Color(0x66FFFFFF), width: on ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(s.icon, size: 20, color: on ? _coral : const Color(0xFF9B8FC4)),
          const SizedBox(width: 9),
          Text(s.label, style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: on ? _coral : T.textSecondary)),
        ]),
      ),
    );
  }

  Widget _photoCard() {
    Widget thumb(List<Color> c) => Container(
          width: 74, height: 74,
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
            borderRadius: BorderRadius.circular(16),
          ),
        );
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('사진', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 14),
        Row(children: [
          Container(
            width: 74, height: 74, alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x59836FFF), width: 1.5, style: BorderStyle.solid),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.add_a_photo, size: 22, color: Color(0xFF9B8FC4)),
              SizedBox(height: 3),
              Text('추가', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF9B8FC4))),
            ]),
          ),
          const SizedBox(width: 10),
          thumb(const [Color(0xFFFFD9C2), Color(0xFFE9D4FF)]),
          const SizedBox(width: 10),
          thumb(const [Color(0xFFD4ECFF), Color(0xFFD9F5EC)]),
        ]),
      ]),
    );
  }

  Widget _storyCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('오늘의 이야기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 12),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
          child: TextField(
            controller: _story,
            maxLines: 4,
            style: const TextStyle(fontSize: 14, height: 1.6, color: T.textPrimary),
            decoration: const InputDecoration(
              hintText: '무엇이 마음을 움직였는지 천천히 적어보세요...',
              hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
              border: InputBorder.none, isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _publicCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(cPublic ? Icons.public : Icons.lock, size: 21, color: const Color(0xFF8E7BFF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('공개 설정', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const SizedBox(height: 2),
              Text(cPublic ? '커뮤니티에 공유돼요' : '나만 볼 수 있어요',
                  style: const TextStyle(fontSize: 12, color: Color(0x9E463C64))),
            ]),
          ),
        ]),
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: const Color(0x99FFFFFF), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            _pubSeg('공개', true),
            _pubSeg('나만 보기', false),
          ]),
        ),
        if (cPublic) ...[
          const SizedBox(height: 14),
          Row(children: const [
            Text('어느 커뮤니티에 올릴까요? ', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: T.textSecondary)),
            Text('(복수 선택)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: T.textMuted)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 7, runSpacing: 7, children: [
            for (final c in kCommunities.skip(1)) _commChip(c),
          ]),
        ],
      ]),
    );
  }

  Widget _pubSeg(String label, bool v) {
    final on = cPublic == v;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => cPublic = v),
        child: Container(
          height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(gradient: on ? _sig : null, borderRadius: BorderRadius.circular(11)),
          child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
        ),
      ),
    );
  }

  Widget _commChip(String c) {
    final on = cComms.contains(c);
    final col = catColor(c);
    return GestureDetector(
      onTap: () => setState(() => on ? cComms.remove(c) : cComms.add(c)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: on ? col : const Color(0x99FFFFFF),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: on ? Colors.transparent : const Color(0x66FFFFFF)),
          boxShadow: on ? [BoxShadow(color: col.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 5))] : null,
        ),
        child: Text(c, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
      ),
    );
  }

  Widget _saveButton() {
    return GestureDetector(
      onTap: _save,
      child: Container(
        height: 58, alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _sig,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x73D89BFF), blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.check, size: 21, color: Colors.white),
          SizedBox(width: 8),
          Text('기록 저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }

  // ── 장소 선택 시트 ───────────────────────────
  void _openPlacePicker() {
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x57281E30),
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          final q = searchCtrl.text.trim();
          final list = q.isEmpty ? kPlaces : kPlaces.where((p) => p.name.contains(q)).toList();
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.76),
            decoration: const BoxDecoration(
              color: Color(0xFAFCFAFF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(child: Text('어디였나요?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary))),
                GestureDetector(onTap: () => Navigator.pop(sheetCtx), child: const Icon(Icons.close, size: 22, color: Color(0xFFBBB3CC))),
              ]),
              const SizedBox(height: 4),
              const Text('다녀온 곳을 고르면 그곳의 마음 변화를 함께 기록해요.', style: TextStyle(fontSize: 12.5, color: Color(0xA8463C64))),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(color: const Color(0xD9FFFFFF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x2E8C7BFF))),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  const Icon(Icons.search, size: 19, color: T.textMuted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setSheet(() {}),
                      style: const TextStyle(fontSize: 14, color: T.textPrimary),
                      decoration: const InputDecoration(hintText: '장소 검색', hintStyle: TextStyle(fontSize: 14, color: T.textMuted), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              if (q.isNotEmpty)
                GestureDetector(
                  onTap: () { setState(() => placeName = q); Navigator.pop(sheetCtx); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x66836FFF))),
                    child: Row(children: [
                      const Icon(Icons.edit_location_alt, size: 19, color: Color(0xFF8E7BFF)),
                      const SizedBox(width: 9),
                      Flexible(child: Text("'$q'(으)로 기록하기", style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary))),
                    ]),
                  ),
                ),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final res = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const PinPickerScreen()),
                  );
                  if (res != null && mounted) setState(() => placeName = res);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0x29FF9E7D), Color(0x24D89BFF)]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x4DD89BFF)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.add_location_alt, size: 20, color: _coral),
                    const SizedBox(width: 9),
                    const Expanded(child: Text('찾는 곳이 없나요? 지도에서 직접 찍기', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary))),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBB3CC)),
                  ]),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final to = kEmotions[p.to];
                    return GestureDetector(
                      onTap: () { setState(() { placeName = p.name; cFrom = p.from; cTo = p.to; }); Navigator.pop(sheetCtx); },
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x66FFFFFF))),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40, alignment: Alignment.center,
                            decoration: BoxDecoration(gradient: to.grad, borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: to.c2.withOpacity(0.27), blurRadius: 10, offset: const Offset(0, 4))]),
                            child: to.icon(25.2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                              const SizedBox(height: 2),
                              Text('${p.cat} · ${p.dist}', style: const TextStyle(fontSize: 12, color: Color(0x9E463C64))),
                            ]),
                          ),
                          const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCABFDC)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          );
        });
      },
    );
  }
}
