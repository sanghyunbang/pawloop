import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../theme/themes.dart';
import '../data/pet_sync.dart';
import '../data/walk_repository.dart' show WalkFailure, WalkFailureKindX;
import '../domain/pet.dart';
import '../widgets/aurora.dart';

/// 프로필 수정 (edit). 우리 아이(강아지) 프로필 편집.
class EditScreen extends StatefulWidget {
  /// 편집할 아이. **필수다** — 한 마리도 없으면 이 화면에 올 수 없다.
  ///
  /// 예전에는 전역 `kMyDog` 를 직접 읽었는데, 그 값이 `null` 일 수 있게 되면서(#159)
  /// 이 화면이 "없는 아이" 를 편집하려 들 수 있었다. 인자로 받으면 그 경우가 애초에
  /// 생기지 않는다.
  final DogProfile pet;

  /// 테스트가 가짜 서버를 꽂는 자리. 운영 경로에서는 null 이다.
  final PetSync? sync;

  const EditScreen({super.key, required this.pet, this.sync});
  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _breed;
  late final TextEditingController _age;
  late PetSpecies _species;
  late DogSize _size;
  late bool _neutered;

  static const _sig = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [T.sigStart, T.sigEnd],
  );
  static const _coral = Color(0xFFFF7A59);

  late final PetSync _sync = widget.sync ?? PetSync();
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final dog = widget.pet;
    _name = TextEditingController(text: dog.name);
    _breed = TextEditingController(text: dog.breed);
    _age = TextEditingController(text: dog.ageMonths.toString());
    _species = dog.species;
    _size = dog.size;
    _neutered = dog.neutered;
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _age.dispose();
    super.dispose();
  }

  /// 편집 저장.
  ///
  /// **이 화면의 편집은 아직 서버에 가지 않는다.** 계약에 `PATCH /api/dogs/{dogId}` 가
  /// 선언돼 있지만 서버에 구현이 없고(#145 가 미뤘다), 계약이 생성용 `DogInput` 을
  /// 그대로 재사용해서 **계약대로면 부분 수정이 불가능**하다 — `DogPatch` 분리는
  /// 이슈 #24 가 소유한다.
  ///
  /// 그래서 화면이 "저장됐어요" 라고만 말하면 거짓말이 된다. 앱 안에서만 바뀐다는 것을
  /// 문구로 밝힌다(#159).
  void _save() {
    final months = int.tryParse(_age.text.trim());
    final base = widget.pet;
    // 선택된 아이(kMyPets[kSelectedPetIdx])를 갱신 — 여러 마리 지원.
    updateSelectedPet(
      base.copyWith(
        name: _name.text.trim().isEmpty ? base.name : _name.text.trim(),
        breed: _breed.text.trim().isEmpty ? base.breed : _breed.text.trim(),
        species: _species,
        size: _size,
        ageMonths: (months == null || months < 0) ? base.ageMonths : months,
        neutered: _neutered,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이 기기에만 반영했어요 · 서버 저장은 준비 중이에요'),
        duration: Duration(milliseconds: 2000),
      ),
    );
    Navigator.of(context).maybePop();
  }

  /// 프로필 지우기 — 서버는 소프트 삭제다(#156). 산책 기록은 남고 통계에도 계속 센다.
  ///
  /// 되살리기가 없어서 확인 문구가 그 두 가지를 분명히 말한다: 기록은 남는다, 프로필은
  /// 못 되돌린다. 실패하면 목록을 건드리지 않고 이유만 보여 준다.
  Future<void> _confirmAndDelete() async {
    if (_deleting) return;
    final pet = widget.pet;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${pet.name} 프로필을 지울까요?',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: const Text(
          '산책 기록은 그대로 남고 통계에도 계속 세요. 프로필은 되돌릴 수 없어요.',
          style: TextStyle(fontSize: 13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              '지우기',
              style: TextStyle(fontWeight: FontWeight.w800, color: _coral),
            ),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    setState(() => _deleting = true);
    try {
      await _sync.remove(pet);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${pet.name} 프로필을 지웠어요 · 산책 기록은 남아 있어요')),
      );
      Navigator.of(context).maybePop();
    } on WalkFailure catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.kind.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                  children: [
                    Center(child: _avatar()),
                    const SizedBox(height: 16),
                    _borderPicker(),
                    const SizedBox(height: 22),
                    _field('이름', _name, hint: '우리 아이 이름'),
                    const SizedBox(height: 20),
                    const _Label('종류'),
                    const SizedBox(height: 12),
                    _speciesSegment(),
                    const SizedBox(height: 18),
                    _field('품종', _breed, hint: '예: 믹스견, 포메라니안, 코리안숏헤어'),
                    const SizedBox(height: 20),
                    const _Label('크기'),
                    const SizedBox(height: 12),
                    _sizeSegment(),
                    const SizedBox(height: 20),
                    const _Label('나이'),
                    const SizedBox(height: 12),
                    _ageField(),
                    const SizedBox(height: 20),
                    _neuterToggle(),
                    const SizedBox(height: 26),
                    _saveButton(),
                    const SizedBox(height: 14),
                    _deleteButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: T.cardBorder),
              ),
              child: const Icon(
                Icons.arrow_back,
                size: 22,
                color: T.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            '프로필 편집',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: T.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _save,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: _sig,
                borderRadius: BorderRadius.circular(13),
                boxShadow: const [
                  BoxShadow(
                    color: T.sigGlow,
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Text(
                '저장',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() => SizedBox(
    width: 96,
    height: 96,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        ValueListenableBuilder<Color>(
          valueListenable: AppThemeCtl.avatarBorder,
          builder: (_, border, __) => Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [T.glowStart, T.glowEnd],
              ),
              border: Border.all(color: border, width: 3.5),
              boxShadow: [
                BoxShadow(
                  color: border.withValues(alpha: 0.4),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ValueListenableBuilder<DogProfile?>(
              valueListenable: kMyDog,
              builder: (_, dog, __) => Image.asset(
                (dog ?? widget.pet).avatarAsset,
                width: 60,
                height: 60,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: T.accent,
              border: Border.all(color: const Color(0xFFF7F0FB), width: 3),
            ),
            child: const Icon(Icons.pets, size: 15, color: Colors.white),
          ),
        ),
      ],
    ),
  );

  Widget _borderPicker() {
    return ValueListenableBuilder<Color>(
      valueListenable: AppThemeCtl.avatarBorder,
      builder: (_, sel, __) => Column(
        children: [
          const Text(
            '프로필 테두리 색',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: T.textSecondary,
            ),
          ),
          const SizedBox(height: 11),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final c in kAvatarBorders)
                GestureDetector(
                  onTap: () => AppThemeCtl.avatarBorder.value = c,
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c,
                      border: Border.all(
                        color: sel.toARGB32() == c.toARGB32()
                            ? T.textPrimary
                            : const Color(0x33000000),
                        width: sel.toARGB32() == c.toARGB32() ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4), child: _Label(label)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: T.accentLine),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 15, color: T.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 15, color: T.textMuted),
              border: InputBorder.none,
              isDense: true,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _speciesSegment() {
    Widget cell(PetSpecies s) {
      final on = _species == s;
      return GestureDetector(
        onTap: () => setState(() => _species = s),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? _sig : null,
            color: on ? null : T.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: on ? Colors.transparent : T.cardBorder,
            ),
            boxShadow: on
                ? const [
                    BoxShadow(
                      color: T.sigGlow,
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                switch (s) {
                  PetSpecies.dog => 'assets/emoji/dog.png',
                  PetSpecies.cat => 'assets/emoji/cat.png',
                  PetSpecies.other => 'assets/emoji/paw.png',
                },
                width: 20,
                height: 20,
                gaplessPlayback: true,
              ),
              const SizedBox(width: 6),
              Text(
                s.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : T.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        for (int i = 0; i < PetSpecies.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: cell(PetSpecies.values[i])),
        ],
      ],
    );
  }

  Widget _sizeSegment() {
    return Row(
      children: [
        for (int i = 0; i < DogSize.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _sizeCell(DogSize.values[i])),
        ],
      ],
    );
  }

  Widget _sizeCell(DogSize s) {
    final on = _size == s;
    return GestureDetector(
      onTap: () => setState(() => _size = s),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: on ? _sig : null,
          color: on ? null : T.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on ? Colors.transparent : T.cardBorder,
          ),
          boxShadow: on
              ? const [
                  BoxShadow(
                    color: T.sigGlow,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Text(
          s.label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: on ? Colors.white : T.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _ageField() {
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: T.accentLine),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _age,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 15, color: T.textPrimary),
              decoration: const InputDecoration(
                hintText: '나이 (개월)',
                hintStyle: TextStyle(fontSize: 15, color: T.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const Text(
            '개월',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: T.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _neuterToggle() {
    return GestureDetector(
      onTap: () => setState(() => _neutered = !_neutered),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: T.accentLine),
        ),
        child: Row(
          children: [
            Icon(
              Icons.medical_services_rounded,
              size: 20,
              color: _neutered ? _coral : const Color(0xFF9B8FC4),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '중성화 완료',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: T.textPrimary,
                ),
              ),
            ),
            _switch(_neutered),
          ],
        ),
      ),
    );
  }

  Widget _switch(bool on) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 50,
      height: 30,
      padding: const EdgeInsets.all(3),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        gradient: on ? _sig : null,
        color: on ? null : T.line,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }

  /// 저장 버튼 아래의 조용한 글자 버튼 — 눌러서 지워지는 것이 아니라 묻는다.
  Widget _deleteButton() {
    return Center(
      child: TextButton(
        onPressed: _deleting ? null : _confirmAndDelete,
        child: const Text(
          '프로필 지우기',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textMuted),
        ),
      ),
    );
  }

  Widget _saveButton() {
    return GestureDetector(
      onTap: _save,
      child: Container(
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _sig,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73D89BFF),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: const Text(
          '저장하기',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w800,
      color: T.textPrimary,
    ),
  );
}
