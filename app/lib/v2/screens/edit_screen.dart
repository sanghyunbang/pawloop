import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../theme/themes.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';

/// 프로필 수정 (edit). 우리 아이(강아지) 프로필 편집.
class EditScreen extends StatefulWidget {
  const EditScreen({super.key});
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
    colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)],
  );
  static const _coral = Color(0xFFFF7A59);

  @override
  void initState() {
    super.initState();
    final dog = kMyDog.value;
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

  void _save() {
    final months = int.tryParse(_age.text.trim());
    // 선택된 아이(kMyPets[kSelectedPetIdx])를 갱신 — 여러 마리 지원.
    updateSelectedPet(
      kMyDog.value.copyWith(
        name: _name.text.trim().isEmpty ? kMyDog.value.name : _name.text.trim(),
        breed: _breed.text.trim().isEmpty
            ? kMyDog.value.breed
            : _breed.text.trim(),
        species: _species,
        size: _size,
        ageMonths: (months == null || months < 0)
            ? kMyDog.value.ageMonths
            : months,
        neutered: _neutered,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('우리 아이 프로필이 저장됐어요'),
        duration: Duration(milliseconds: 1400),
      ),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
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
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x80FFFFFF)),
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
                    color: Color(0x4DD89BFF),
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
                colors: [Color(0xFFFFE7D2), Color(0xFFFFD0C0)],
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
            child: ValueListenableBuilder<DogProfile>(
              valueListenable: kMyDog,
              builder: (_, dog, __) => Image.asset(
                dog.avatarAsset,
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
              color: const Color(0xFF8E7BFF),
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
                            ? const Color(0xFF2C2740)
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
            color: const Color(0x9EFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x338C7BFF)),
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
            color: on ? null : const Color(0x99FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: on ? Colors.transparent : const Color(0x66FFFFFF),
            ),
            boxShadow: on
                ? const [
                    BoxShadow(
                      color: Color(0x4DD89BFF),
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
          color: on ? null : const Color(0x99FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on ? Colors.transparent : const Color(0x66FFFFFF),
          ),
          boxShadow: on
              ? const [
                  BoxShadow(
                    color: Color(0x4DD89BFF),
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
        color: const Color(0x9EFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x338C7BFF)),
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
          color: const Color(0x9EFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x338C7BFF)),
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
        color: on ? null : const Color(0x1F8C7BFF),
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
