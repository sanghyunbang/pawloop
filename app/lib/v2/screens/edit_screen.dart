import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../theme/themes.dart';
import '../data/avatar_border_store.dart';
import '../data/pet_sync.dart';
import '../data/image_prep.dart';
import '../data/media_picker.dart';
import '../data/post_media_repository.dart';
import '../widgets/dog_avatar.dart';
import '../data/walk_repository.dart' show WalkFailure, WalkFailureKind, WalkFailureKindX;
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import '../widgets/pet_character_picker.dart';

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

  /// 아바타 테두리 색을 남기는 자리 — 테스트가 가짜를 꽂는다.
  final AvatarBorderStore borders;

  /// 사진 바꾸기(#448)의 부품 — 테스트가 물린다.
  final PostMediaRepository? media;
  final MediaPicker? picker;
  final ImagePreparer prepare;

  const EditScreen({
    super.key,
    required this.pet,
    this.sync,
    this.borders = const AvatarBorderStore(),
    this.media,
    this.picker,
    this.prepare = ImagePrep.prepare,
  });
  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _breed;
  late final TextEditingController _age;
  late PetSpecies _species;
  late DogSize _size;

  /// 고른 얼굴 — `null` 은 "안 골랐다"(#585). 저장할 때 처음 값과 비교해 보낼지 정한다.
  String? _character;
  late bool _neutered;

  static const _sig = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [T.sigStart, T.sigEnd],
  );
  static const _coral = Color(0xFFFF7A59);

  late final PetSync _sync = widget.sync ?? PetSync();
  bool _deleting = false;
  bool _saving = false;

  late final PostMediaRepository _media = widget.media ?? PostMediaRepository();
  late final MediaPicker _picker = widget.picker ?? ImagePickerMediaPicker();
  bool _photoBusy = false;

  /// 사진 바꾸기 — 고르기 → 줄이기 → 올리기 → 그 아이에 붙이기. **바로 서버에 저장된다**(이 화면의
  /// "저장" 은 아직 이 기기에만 반영되지만 사진은 서버 API 가 있다, #448).
  Future<void> _changePhoto() async {
    if (_photoBusy || _deleting) return;
    final picked = await _picker.pickImages(limit: 1);
    if (picked.isEmpty || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      final prepared = await widget.prepare(picked.first.bytes);
      final uploaded = await _media.upload(
        jpegBytes: prepared.bytes,
        width: prepared.width,
        height: prepared.height,
        filename: picked.first.name,
        category: PostMediaRepository.profileCategory,
      );
      await _sync.setPhoto(kMyDog.value ?? widget.pet, uploaded.id);
      notifyPetsChanged();
      if (!mounted) return;
      _toast('사진을 바꿨어요');
    } on PostMediaFailure catch (e) {
      if (mounted) _toast(e.label);
    } on WalkFailure catch (e) {
      if (mounted) _toast(e.message);
    } on ImagePrepException {
      if (mounted) _toast('이 사진은 읽을 수 없어요');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_photoBusy || _deleting) return;
    setState(() => _photoBusy = true);
    try {
      await _sync.clearPhoto(kMyDog.value ?? widget.pet);
      notifyPetsChanged();
      if (mounted) _toast('사진을 지웠어요');
    } on WalkFailure catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    final dog = widget.pet;
    _name = TextEditingController(text: dog.name);
    _breed = TextEditingController(text: dog.breed);
    _age = TextEditingController(text: dog.ageMonths.toString());
    _species = dog.species;
    _size = dog.size;
    _character = dog.characterKey;
    _neutered = dog.neutered;
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _age.dispose();
    super.dispose();
  }

  /// 편집 저장 — **서버에 간다**(#516).
  ///
  /// 2026-09-15 이전에는 메모리의 `kMyPets` 만 바꾸고 "이 기기에만 반영했어요 · 서버 저장은
  /// 준비 중이에요" 라고 말했다. 그 말도 사실이 아니었다 — 기기에도 안 남아서, 앱을 껐다
  /// 켜면 `PetSync.load()` 가 서버 목록으로 통째로 갈아끼웠다. 한 번의 콜드 스타트에 편집이
  /// 전부 사라졌다.
  ///
  /// **나이는 개월 수로 편집하지만 서버가 드는 것은 `birth` 다** — `ageMonths` 는 거기서
  /// 나오는 파생값이라 저장할 자리가 없다. 그래서 `오늘 − N개월` 로 바꿔 보낸다. 칸이
  /// 비었거나 0 이면 안 보낸다: 0 을 보내면 생일이 오늘이 되어 "갓 태어났다" 가 된다.
  ///
  /// **안 바뀐 필드는 안 보낸다.** 부분 수정이라 보낸 것만 반영되고, 그래야 두 기기에서
  /// 같은 아이를 고쳐도 서로의 편집을 덮지 않는다.
  Future<void> _save() async {
    if (_saving || _deleting) return;
    final base = widget.pet;
    final serverId = base.serverId;
    final name = _name.text.trim();
    final breed = _breed.text.trim();
    final months = int.tryParse(_age.text.trim());

    if (serverId == null) {
      // 서버에 없는 아이다(등록 전 임시 상태). 화면 안에서만 바꾸고 그 사실을 말한다.
      _applyLocally(name, breed, months);
      _tell('이 기기에만 반영했어요 · 아직 서버에 등록되지 않은 아이예요');
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    final changedName = name.isNotEmpty && name != base.name ? name : null;
    final changedBreed = breed.isNotEmpty && breed != base.breed ? breed : null;
    final changedSpecies = _species == base.species ? null : _species;
    final changedSize = _size == base.size ? null : _size;
    final changedNeutered = _neutered == base.neutered ? null : _neutered;
    // 얼굴은 "안 바꿈" 과 "기본으로 되돌림" 이 다르다 — 되돌림은 서버에 `null` 을 **보내야**
    // 지워진다(#586). `null` 하나로는 그 둘을 못 가르므로 깃발을 따로 든다.
    final characterChanged = _character != base.characterKey;
    final clearCharacter = characterChanged && _character == null;
    // 안 건드렸으면 **안 보낸다.** 같은 값이라도 실어 보내면, 그 사이 다른 기기에서 바꾼
    // 얼굴을 이 저장이 덮는다 — 부분 수정을 쓰는 이유가 그것이다.
    final changedCharacter = characterChanged && !clearCharacter ? _character : null;
    // 나이는 개월 수로 편집하지만 서버가 드는 것은 birth 다 — ageMonths 는 거기서 나오는
    // 파생값이라 저장할 자리가 없다. 칸이 비었거나 0 이면 안 보낸다: 0 을 보내면 생일이
    // 오늘이 되어 "갓 태어났다" 가 된다.
    final now = DateTime.now();
    final changedBirth = (months != null && months > 0 && months != base.ageMonths)
        ? DateTime(now.year, now.month - months, now.day)
        : null;

    if (changedName == null &&
        changedBreed == null &&
        changedSpecies == null &&
        changedSize == null &&
        changedNeutered == null &&
        changedBirth == null &&
        !characterChanged) {
      // 바뀐 것이 없다. 빈 본문은 서버가 400 이고, 그건 오류가 아니라 할 일이 없는 것이다.
      Navigator.of(context).maybePop();
      return;
    }

    setState(() => _saving = true);
    try {
      await _sync.edit(
        serverId,
        name: changedName,
        species: changedSpecies,
        size: changedSize,
        breed: changedBreed,
        birth: changedBirth,
        neutered: changedNeutered,
        character: changedCharacter,
        clearCharacter: clearCharacter,
      );
      if (!mounted) return;
      _tell('저장했어요');
      Navigator.of(context).maybePop();
    } on WalkFailure catch (failure) {
      if (!mounted) return;
      _tell(switch (failure.kind) {
        WalkFailureKind.network => '저장하지 못했어요 · 연결을 확인해 주세요',
        WalkFailureKind.notFound => '그 아이를 찾을 수 없어요',
        WalkFailureKind.rateLimited => '요청이 많아요 · 잠시 뒤 다시 시도해 주세요',
        _ => '저장하지 못했어요 · 입력을 확인해 주세요',
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 서버에 없는 아이를 화면 안에서만 고친다.
  void _applyLocally(String name, String breed, int? months) {
    final base = widget.pet;
    updateSelectedPet(base.copyWith(
      name: name.isEmpty ? base.name : name,
      breed: breed.isEmpty ? base.breed : breed,
      species: _species,
      size: _size,
      ageMonths: (months == null || months < 0) ? base.ageMonths : months,
      neutered: _neutered,
      characterKey: _character,
      clearCharacter: _character == null,
    ));
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(milliseconds: 2000)),
    );
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
                    Center(
                      child: GestureDetector(
                        key: const Key('edit-photo-pick'),
                        onTap: _changePhoto,
                        behavior: HitTestBehavior.opaque,
                        child: _avatar(),
                      ),
                    ),
                    ValueListenableBuilder<DogProfile?>(
                      valueListenable: kMyDog,
                      builder: (_, dog, __) => Center(
                        child: TextButton(
                          key: const Key('edit-photo-clear'),
                          onPressed: (dog ?? widget.pet).photoUrl == null || _photoBusy ? null : _removePhoto,
                          child: Text(
                            _photoBusy
                                ? '사진 올리는 중…'
                                : (dog ?? widget.pet).photoUrl == null
                                    ? '사진을 누르면 바꿀 수 있어요'
                                    : '사진 지우기',
                            style: const TextStyle(fontSize: 12.5, color: T.textMuted),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _characterPicker(),
                    const SizedBox(height: 18),
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
              builder: (_, dog, __) => DogAvatar(dog: dog ?? widget.pet, size: 89, emojiSize: 60),
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
            child: const Icon(Icons.photo_camera_rounded, size: 15, color: Colors.white),
          ),
        ),
      ],
    ),
  );

  /// 사진이 없을 때의 얼굴(#585).
  ///
  /// 사진 바로 아래다 — 둘이 같은 것을 정하고, **사진이 이긴다.** 사진을 지운 사람이 다음에
  /// 볼 화면이 여기서 고른 얼굴이라, 사진 지우기 줄과 붙어 있는 편이 읽기 쉽다.
  Widget _characterPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
          child: Text(
            '사진이 없을 때의 얼굴',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: T.textSecondary),
          ),
        ),
        const SizedBox(height: 11),
        PetCharacterPicker(
          selected: _character,
          species: _species,
          onPick: (key) => setState(() => _character = key),
        ),
      ],
    );
  }

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
                  key: Key('avatar-border-${c.toARGB32()}'),
                  // 고른 색을 남긴다(#516). 예전에는 메모리만 바뀌어서 앱을 껐다 켜면
                  // 기본색으로 돌아갔다 — 고르는 칸을 그려 놓고 안 지킨 셈이다.
                  onTap: () => widget.borders.save(c),
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
                petSpeciesAsset(s),
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
