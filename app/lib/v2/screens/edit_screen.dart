import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 프로필 수정 (edit).
class EditScreen extends StatefulWidget {
  const EditScreen({super.key});
  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final _nick = TextEditingController(text: 'tester');
  final _name = TextEditingController(text: 'tester');
  final _email = TextEditingController(text: 'localtest@example.com');
  final _age = TextEditingController();
  int gender = 1; // 0 여성 1 남성 2 기타
  final Set<int> travels = {0}; // 0 힐링

  static const _sig = LinearGradient(begin: Alignment(-0.7, -1), end: Alignment(0.7, 1), colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]);
  static const _coral = Color(0xFFFF7A59);
  static const _genders = [(Icons.female, '여성'), (Icons.male, '남성'), (Icons.transgender, '기타')];
  static const _travels = [(Icons.self_improvement, '힐링'), (Icons.directions_run, '액티비티'), (Icons.palette, '문화·예술'), (Icons.restaurant, '미식')];

  @override
  void dispose() {
    _nick.dispose(); _name.dispose(); _email.dispose(); _age.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('프로필이 저장됐어요'), duration: Duration(milliseconds: 1400)),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                const Text('프로필 수정', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                children: [
                  Center(child: _avatar()),
                  const SizedBox(height: 18),
                  _field('닉네임', _nick, counter: true),
                  const SizedBox(height: 18),
                  _field('이름', _name),
                  const SizedBox(height: 18),
                  _field('이메일', _email),
                  const SizedBox(height: 20),
                  const Text('성별', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  const SizedBox(height: 12),
                  Row(children: [
                    for (int i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: _genderCell(i)),
                    ],
                  ]),
                  const SizedBox(height: 18),
                  Row(children: const [
                    Expanded(child: Divider(color: Color(0x268C7BFF))),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('선택사항', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFBBB3CC)))),
                    Expanded(child: Divider(color: Color(0x268C7BFF))),
                  ]),
                  const SizedBox(height: 6),
                  _ageField(),
                  const SizedBox(height: 20),
                  Row(children: const [
                    Text('여행 타입 ', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                    Text('(선택)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: T.textMuted)),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 10, children: [for (int i = 0; i < _travels.length; i++) _travelChip(i)]),
                  const SizedBox(height: 24),
                  _saveButton(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _avatar() => SizedBox(
        width: 88, height: 88,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 88, height: 88, alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFD9C2), Color(0xFFE9C9FF)]),
                boxShadow: [BoxShadow(color: Color(0x66D89BFF), blurRadius: 28, offset: Offset(0, 12))]),
            child: const Text('t', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          Positioned(
            right: -2, bottom: -2,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF8E7BFF), border: Border.all(color: const Color(0xFFF7F0FB), width: 3)),
              child: const Icon(Icons.edit, size: 15, color: Colors.white),
            ),
          ),
        ]),
      );

  Widget _field(String label, TextEditingController ctrl, {bool counter = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4), child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: T.textSecondary))),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: const Color(0x9EFFFFFF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x338C7BFF))),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLength: counter ? 20 : null,
              onChanged: counter ? (_) => setState(() {}) : null,
              style: const TextStyle(fontSize: 15, color: T.textPrimary),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true, counterText: '', contentPadding: EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          if (counter) Text('${_nick.text.characters.length}/20', style: const TextStyle(fontSize: 12, color: Color(0xFFBBB3CC))),
        ]),
      ),
    ]);
  }

  Widget _ageField() {
    return Container(
      decoration: BoxDecoration(color: const Color(0x9EFFFFFF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x338C7BFF))),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _age,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 15, color: T.textPrimary),
        decoration: const InputDecoration(hintText: '나이', hintStyle: TextStyle(fontSize: 15, color: T.textMuted), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 14)),
      ),
    );
  }

  Widget _genderCell(int i) {
    final on = gender == i;
    return GestureDetector(
      onTap: () => setState(() => gender = i),
      child: Column(children: [
        Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? const Color(0x24FF7A59) : const Color(0x99FFFFFF),
            shape: BoxShape.circle,
            border: Border.all(color: on ? _coral : const Color(0x66FFFFFF), width: on ? 1.6 : 1),
          ),
          child: SizedBox(
            width: 56, height: 56,
            child: Icon(_genders[i].$1, size: 24, color: on ? _coral : const Color(0xFF9B8FC4)),
          ),
        ),
        const SizedBox(height: 8),
        Text(_genders[i].$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: T.textSecondary)),
      ]),
    );
  }

  Widget _travelChip(int i) {
    final on = travels.contains(i);
    return GestureDetector(
      onTap: () => setState(() => on ? travels.remove(i) : travels.add(i)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: on ? _sig : null,
          color: on ? null : const Color(0x99FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? Colors.transparent : const Color(0x66FFFFFF)),
          boxShadow: on ? const [BoxShadow(color: Color(0x4DD89BFF), blurRadius: 14, offset: Offset(0, 6))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_travels[i].$1, size: 18, color: on ? Colors.white : T.textSecondary),
          const SizedBox(width: 7),
          Text(_travels[i].$2, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
        ]),
      ),
    );
  }

  Widget _saveButton() {
    return GestureDetector(
      onTap: _save,
      child: Container(
        height: 58, alignment: Alignment.center,
        decoration: BoxDecoration(gradient: _sig, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x73D89BFF), blurRadius: 30, offset: Offset(0, 14))]),
        child: const Text('저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    );
  }
}
