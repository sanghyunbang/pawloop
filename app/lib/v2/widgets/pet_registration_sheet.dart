// lib/v2/widgets/pet_registration_sheet.dart
//
// 반려동물을 서버에 등록하는 **유일한 폼** — 이슈 #159.
//
// ## 왜 한 곳인가
//
// 등록이 필요한 자리가 셋이다.
//
//   1. 온보딩 — 처음 들어온 사람에게 권한다
//   2. 산책 저장 — 온보딩을 건너뛴 사람이 저장하려는 순간. **여기가 사용자가 "왜
//      필요한지" 아는 유일한 시점이다**
//   3. 프로필 '추가' — 두 번째 아이
//
// 셋이 각자 폼을 그리면 필드가 갈라지고, 한 곳만 고쳐지는 날이 온다.
//
// ## 등록을 강제하지 않는다
//
// 로그인 화면에 "그냥 둘러보기" 가 있다. 온보딩에서 등록을 필수로 만들면 구경만 하려는
// 사람도 폼을 채워야 한다. 그래서 권하되 건너뛸 수 있게 하고, **산책을 저장하려는
// 순간에 잡는다** — 그때는 이유가 분명하다.
library;

import 'package:flutter/material.dart';

import 'dart:typed_data';

import '../data/image_prep.dart';
import '../data/media_picker.dart';
import '../data/pet_sync.dart';
import '../data/post_media_repository.dart';
import '../data/walk_repository.dart';
import '../domain/pet.dart';
import '../domain/pet_characters.dart';
import '../theme/app_tokens.dart';
import 'form_kit.dart';
import 'pet_character_picker.dart';

/// 등록 시트를 띄운다.
///
/// @param reason 왜 지금 등록을 권하는지. 산책 저장에서 부를 때는 그 이유를 준다 —
///               맥락 없이 폼만 뜨면 사용자는 왜 막혔는지 모른다
/// @return 등록했으면 그 프로필. 닫았으면 `null`
Future<DogProfile?> showPetRegistrationSheet(
  BuildContext context, {
  String? reason,
  PetSync? sync,
  PostMediaRepository? media,
  MediaPicker? picker,
  ImagePreparer prepare = ImagePrep.prepare,
}) {
  return showModalBottomSheet<DogProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PetRegistrationSheet(
        reason: reason, sync: sync, media: media, picker: picker, prepare: prepare),
  );
}

/// 등록 폼. 시트 밖에서도 띄울 수 있게 공개다 — 테스트가 저장소·고르기·준비를 물린다.
class PetRegistrationSheet extends StatefulWidget {
  final String? reason;
  final PetSync? sync;
  final PostMediaRepository? media;
  final MediaPicker? picker;
  final ImagePreparer prepare;

  const PetRegistrationSheet({
    super.key,
    this.reason,
    this.sync,
    this.media,
    this.picker,
    this.prepare = ImagePrep.prepare,
  });

  @override
  State<PetRegistrationSheet> createState() => _PetRegistrationSheetState();
}

class _PetRegistrationSheetState extends State<PetRegistrationSheet> {
  final _name = TextEditingController();
  final _breed = TextEditingController();

  PetSpecies _species = PetSpecies.dog;
  DogSize _size = DogSize.small;

  /// 고른 얼굴 — 안 고르면 `null` 이고, 그러면 종류 기본 그림이다(#585).
  String? _character;

  bool _saving = false;
  String? _error;

  late final PetSync _sync = widget.sync ?? PetSync();
  late final PostMediaRepository _media = widget.media ?? PostMediaRepository();
  late final MediaPicker _picker = widget.picker ?? ImagePickerMediaPicker();

  /// 고른 사진 — 미리보기 바이트와 올라간 미디어 id. 등록이 끝난 뒤 그 아이에 붙인다(#448).
  Uint8List? _photoBytes;
  int? _photoMediaId;
  bool _uploading = false;
  String? _photoError;

  /// 사진 고르기 → 줄이기(EXIF 지움) → 올리기. 등록 전에 올려 두고 id 만 들고 있는다 — 글쓰기의
  /// 사진 칸과 같은 두 단계라 업로드 검증이 서버 한 곳에 산다.
  Future<void> _pickPhoto() async {
    if (_uploading || _saving) return;
    final picked = await _picker.pickImages(limit: 1);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _uploading = true;
      _photoError = null;
    });
    try {
      final prepared = await widget.prepare(picked.first.bytes);
      final uploaded = await _media.upload(
        jpegBytes: prepared.bytes,
        width: prepared.width,
        height: prepared.height,
        filename: picked.first.name,
        category: PostMediaRepository.profileCategory,
      );
      if (!mounted) return;
      setState(() {
        _photoBytes = prepared.bytes;
        _photoMediaId = uploaded.id;
        _uploading = false;
      });
    } on PostMediaFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _photoError = e.label;
      });
    } on ImagePrepException {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _photoError = '이 사진은 읽을 수 없어요';
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '이름을 입력해 주세요.');
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      var saved = await _sync.register(
        name: name,
        species: _species,
        size: _size,
        breed: _breed.text.trim(),
        character: _character,
      );
      // 사진은 등록된 뒤에 붙는다 — 아이의 id 가 있어야 하니까. 붙이기가 실패해도 등록은 됐다:
      // 아이는 남고 사진만 없다(편집 화면에서 다시 고를 수 있다).
      final mediaId = _photoMediaId;
      if (mediaId != null) {
        try {
          saved = await _sync.setPhoto(saved, mediaId);
        } on WalkFailure {
          // 등록은 성공했다 — 여기서 시트를 붙들지 않는다.
        }
      }
      notifyPetsChanged();
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on WalkFailure catch (e) {
      // 실패를 삼키지 않는다. 사용자는 왜 안 됐는지 알아야 다시 시도할지 정한다.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '등록하지 못했어요 · 잠시 후 다시 시도해 주세요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 틀·입력칸·버튼은 폼 부품이다(#445) — 예전엔 흰 시트에 머티리얼 아웃라인 칸과 색 없는
    // FilledButton(머티리얼 기본 보라)이라 앱의 결과 어긋났다.
    return SheetFrame(
      title: '우리 아이를 등록해 주세요',
      subtitle: widget.reason,
      children: [
            // 사진이 먼저다(#448) — 홈 한가운데가 이 사진이 된다. 안 골라도 등록은 된다.
            Center(child: _photoPicker()),
            const SizedBox(height: 14),

            // 사진을 안 올리는 사람이 있다(사장님, 2026-09-16). 그 사람의 아이도 이름을 읽기
            // 전에 갈려야 한다 — 종류당 한 얼굴이면 홈의 고르기 칩이 같은 얼굴 둘로 선다.
            _label('얼굴 (사진이 없을 때)'),
            PetCharacterPicker(
              selected: _character,
              species: _species,
              onPick: (key) => setState(() => _character = key),
            ),
            const SizedBox(height: 14),

            _label('이름'),
            GlassField(
              controller: _name,
              hint: '예) 보리',
              maxLength: 50,
              autofocus: true,
            ),
            const SizedBox(height: 14),

            _label('종'),
            _chips<PetSpecies>(
              values: PetSpecies.values,
              selected: _species,
              labelOf: (v) => v.label,
              onTap: (v) => setState(() => _species = v),
            ),
            const SizedBox(height: 14),

            _label('몸집'),
            _chips<DogSize>(
              values: DogSize.values,
              selected: _size,
              // 종류 칩을 바꾸면 이 라벨도 따라 바뀐다 — 고양이면 소형묘(#719).
              labelOf: (v) => v.labelFor(_species),
              onTap: (v) => setState(() => _size = v),
            ),
            const SizedBox(height: 14),

            _label('품종 (선택)'),
            GlassField(
              controller: _breed,
              hint: '모르면 비워 두세요',
              maxLength: 50,
            ),

            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFD9534F)),
              ),
            ],

            const SizedBox(height: 14),
            PrimaryButton(
              label: _saving ? '등록하는 중…' : '등록하기',
              onPressed: _saving ? null : _submit,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('나중에', style: TextStyle(color: T.textMuted)),
            ),
      ],
    );
  }

  /// 원형 사진 칸 — 고르기 전엔 종 이모지에 카메라 배지, 고른 뒤엔 사진.
  Widget _photoPicker() {
    final bytes = _photoBytes;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        key: const Key('pet-photo-pick'),
        onTap: _pickPhoto,
        behavior: HitTestBehavior.opaque,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [T.glowStart, T.glowEnd]),
              border: Border.all(color: T.accentLine, width: 1.5),
            ),
            child: bytes == null
                // 사진을 안 골랐으면 **고른 얼굴**이 뜬다 — 등록하고 나서 볼 화면 그대로다.
                ? Image.asset(
                    petCharacterAsset(_character) ?? petSpeciesAsset(_species),
                    width: 52,
                    height: 52)
                : ClipOval(
                    key: const Key('pet-photo-preview'),
                    child: Image.memory(bytes, width: 84, height: 84, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: T.accent,
                border: Border.all(color: T.cardBg, width: 2.5),
              ),
              child: _uploading
                  ? const Padding(
                      padding: EdgeInsets.all(7),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Text(
        _photoError ?? (bytes == null ? '사진 고르기 (선택)' : '사진을 바꾸려면 다시 눌러 주세요'),
        style: TextStyle(fontSize: 12, color: _photoError == null ? T.textMuted : const Color(0xFFD9534F)),
      ),
    ]);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: T.textSecondary,
          ),
        ),
      );

  Widget _chips<T2>({
    required List<T2> values,
    required T2 selected,
    required String Function(T2) labelOf,
    required void Function(T2) onTap,
  }) =>
      Row(
        children: [
          for (final v in values) ...[
            Expanded(
              child: PillChip(
                label: labelOf(v),
                selected: v == selected,
                onTap: () => onTap(v),
                stretch: true,
              ),
            ),
            if (v != values.last) const SizedBox(width: 8),
          ],
        ],
      );
}
