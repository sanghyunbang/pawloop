// 글쓰기 화면의 사진 칸 — 고르고, 다시 인코딩하고, 올리고, 순서를 든다. 이슈 #429.
//
// ## 업로드가 먼저고 글이 나중이다
//
// 사진을 고르는 순간 올리기 시작한다. 글을 저장할 때 서버에 보내는 것은 파일이 아니라
// **올라간 사진의 id 목록**이다. 그래서 이 위젯이 밖으로 내는 것은 `PostMediaSelection` —
// 지금까지 올라간 id 들과 "아직 올리는 중인 것이 있는가" 다. 글쓰기 화면은 올리는 중이면
// 저장을 잠근다.
//
// ## 순서는 올린 순서다
//
// 서버가 `id` 순으로 돌려주고 그 id 는 올린 순이다. 그래서 **한 장씩 순서대로** 올린다 —
// 동시에 올리면 두 기기가 다른 순서를 만든다. 사용자가 고른 순서가 곧 카드의 순서다.
//
// ## 레거시 `MediaGridField` 를 안 쓴다
//
// 그것은 `context.read<MediaRepository>()` 로 Provider 를 찾는다. v2 화면은 저장소를
// 생성자로 받는다 — 테스트가 가짜를 꽂는 자리다. 모양은 비슷하지만 배선이 다르다.
//
// ## 위치 정보는 여기서 빠진다
//
// 고른 원본은 `ImagePrep` 을 지나서만 서버로 간다. 원본 바이트를 저장소에 넘기는 길이 없다.

import 'package:flutter/material.dart';

import '../data/image_prep.dart';
import '../data/media_picker.dart';
import '../data/post_media_repository.dart';
import '../domain/post_media.dart';
import '../theme/app_tokens.dart';

/// 이 위젯이 밖으로 내는 상태.
@immutable
class PostMediaSelection {
  /// 지금까지 올라가 있는 사진의 id — 고른 순서. 글 저장에 그대로 싣는다.
  final List<int> ids;

  /// 아직 올리는 중이거나 다시 인코딩 중인 칸이 있는가. 있으면 저장을 잠근다.
  final bool busy;

  /// 실패한 칸이 있는가. 사용자가 그 칸을 눌러 다시 올리거나 뗀다.
  final bool hasFailure;

  const PostMediaSelection({
    required this.ids,
    required this.busy,
    required this.hasFailure,
  });

  static const empty = PostMediaSelection(ids: [], busy: false, hasFailure: false);
}

class PostMediaField extends StatefulWidget {
  final PostMediaRepository repository;
  final MediaPicker picker;

  /// 고쳐 쓰는 글에 이미 붙어 있던 것. 떼기만 되고 다시 올리지 않는다.
  final List<PostMedia> initial;

  final ValueChanged<PostMediaSelection> onChanged;

  /// 다시 인코딩하는 함수. 기본은 격리 스레드의 `ImagePrep.prepare` 다. 테스트가
  /// 동기 버전을 꽂아 시간을 안 기다린다.
  final ImagePreparer prepare;

  /// 한 글의 상한. 서버와 같은 10 이다.
  final int max;

  const PostMediaField({
    super.key,
    required this.repository,
    required this.picker,
    required this.onChanged,
    this.initial = const [],
    this.prepare = ImagePrep.prepare,
    this.max = PostMediaRepository.maxPerPost,
  });

  @override
  State<PostMediaField> createState() => _PostMediaFieldState();
}

/// 칸 하나의 생애 — 골랐다 → 다시 인코딩 → 올리는 중 → 올라감 / 실패.
class _Slot {
  final int key;

  /// 이미 붙어 있던 것(고치기). 서버에 있으니 올릴 것이 없다.
  final PostMedia? existing;

  /// 새로 고른 원본. `existing` 이면 `null`.
  final PickedImage? picked;

  PreparedImage? prepared;
  UploadedPostMedia? uploaded;
  Object? error;
  bool working = false;

  _Slot.existing(this.key, PostMedia media)
      : existing = media,
        picked = null;

  _Slot.picked(this.key, PickedImage image)
      : existing = null,
        picked = image;

  int? get id => existing?.id ?? uploaded?.id;

  bool get done => id != null;
}

class _PostMediaFieldState extends State<PostMediaField> {
  final List<_Slot> _slots = [];
  int _nextKey = 0;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    for (final media in widget.initial) {
      _slots.add(_Slot.existing(_nextKey++, media));
    }
  }

  int get _remaining => widget.max - _slots.length;

  PostMediaSelection get _selection => PostMediaSelection(
        ids: [for (final s in _slots) if (s.id case final id?) id],
        busy: _picking || _slots.any((s) => s.working),
        hasFailure: _slots.any((s) => s.error != null),
      );

  /// 부모에게 알린다. 부모도 `setState` 를 하므로 이 위젯이 내려간 뒤에는 부르지 않는다.
  void _emit() {
    if (mounted) widget.onChanged(_selection);
  }

  Future<void> _pick() async {
    if (_picking || _remaining <= 0) return;
    setState(() => _picking = true);
    _emit();
    List<PickedImage> picked;
    try {
      picked = await widget.picker.pickImages(limit: _remaining);
    } catch (_) {
      picked = const [];
    }
    if (!mounted) return;
    // 고르기 화면에 오래 머물 수 있다. 그 사이 다른 칸이 사라졌으면 남은 자리로 다시 잰다.
    picked = picked.take(_remaining.clamp(0, widget.max)).toList();
    final fresh = [for (final image in picked) _Slot.picked(_nextKey++, image)];
    setState(() {
      _slots.addAll(fresh);
      _picking = false;
    });
    _emit();
    // 한 장씩 순서대로 — 순서가 곧 카드의 순서다.
    for (final slot in fresh) {
      await _upload(slot);
      if (!mounted) return;
    }
  }

  Future<void> _upload(_Slot slot) async {
    if (!_slots.contains(slot) || slot.working || slot.done) return;
    setState(() {
      slot.working = true;
      slot.error = null;
    });
    _emit();
    try {
      // 위치 정보가 빠지는 자리 — 원본은 여기서 끝나고 다시 인코딩한 것만 나간다.
      slot.prepared ??= await widget.prepare(slot.picked!.bytes);
      if (!mounted || !_slots.contains(slot)) return;
      final prepared = slot.prepared!;
      slot.uploaded = await widget.repository.upload(
        jpegBytes: prepared.bytes,
        width: prepared.width,
        height: prepared.height,
        filename: _jpegName(slot.picked!.name),
      );
    } catch (e) {
      slot.error = e;
    } finally {
      slot.working = false;
      if (mounted) setState(() {});
    }
    _emit();
  }

  void _remove(_Slot slot) {
    setState(() => _slots.remove(slot));
    _emit();
    // 올려 뒀는데 안 쓰기로 한 것은 지운다. 실패해도 하루 뒤 서버가 거둔다 — 기다리지 않는다.
    final uploaded = slot.uploaded;
    if (uploaded != null) {
      widget.repository.delete(uploaded.id).catchError((_) {});
    }
  }

  static String _jpegName(String original) {
    final dot = original.lastIndexOf('.');
    final base = dot > 0 ? original.substring(0, dot) : original;
    return '${base.isEmpty ? 'photo' : base}.jpg';
  }

  /// 칸 한 변. 화면 폭의 1/3 이 아니라 **고정**이다 — 폰(360px)에서 세 칸이 한 줄이고, 넓은
  /// 화면에서는 더 들어간다. 폭에 비례하면 태블릿·가로 모드에서 칸 하나가 화면을 삼킨다.
  static const double tileSize = 96;

  @override
  Widget build(BuildContext context) {
    final canAdd = _remaining > 0 && !_picking;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 고른 것이 있을 때만 칸이 생긴다 — 빈 글쓰기 화면에서 빈 격자가 자리를 먹지 않는다.
      if (_slots.isNotEmpty) ...[
        Wrap(
          key: const Key('post-media-grid'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final slot in _slots) SizedBox.square(dimension: tileSize, child: _tile(slot)),
          ],
        ),
        const SizedBox(height: 10),
      ],
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (canAdd) ...[_addButton(), const SizedBox(width: 10)],
        Expanded(
          child: Text(
            '${_slots.length} / ${widget.max}장 · 위치 정보는 지우고 올려요',
            key: const Key('post-media-count'),
            style: const TextStyle(fontSize: 11.5, color: T.textMuted, height: 1.3),
          ),
        ),
      ]),
    ]);
  }

  Widget _addButton() => OutlinedButton.icon(
        key: const Key('post-media-add'),
        onPressed: _pick,
        style: OutlinedButton.styleFrom(
          foregroundColor: T.textSecondary,
          backgroundColor: const Color(0x99FFFFFF),
          side: const BorderSide(color: T.accentLine),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
        label: const Text('사진 추가', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _tile(_Slot slot) {
    final Widget picture;
    if (slot.existing case final existing?) {
      picture = _network(existing.thumbnailUrl);
    } else {
      final bytes = slot.prepared?.bytes ?? slot.picked!.bytes;
      picture = Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        // 읽을 수 없는 파일이면 회색 칸 — 그 위에 "올리지 못했어요" 가 덮인다.
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x22000000)),
      );
    }

    return GestureDetector(
      key: Key('post-media-slot-${slot.key}'),
      // 실패한 칸은 누르면 다시 올린다.
      onTap: slot.error != null ? () => _upload(slot) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          picture,
          if (slot.working)
            Container(
              key: Key('post-media-working-${slot.key}'),
              color: const Color(0x66000000),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                ),
              ),
            ),
          if (slot.error != null)
            Container(
              key: Key('post-media-error-${slot.key}'),
              color: const Color(0x99000000),
              padding: const EdgeInsets.all(6),
              child: const Center(
                child: Text('올리지 못했어요\n눌러서 다시',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white, height: 1.3)),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              key: Key('post-media-remove-${slot.key}'),
              onTap: () => _remove(slot),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xB3000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// 네트워크 그림. 못 불러오면 조용히 회색 칸이다 — 테스트에는 HTTP 가 없고, 실기기에서도
  /// 잠깐 끊긴 것으로 글쓰기 화면이 깨지면 안 된다.
  static Widget _network(String? url) {
    if (url == null) return const ColoredBox(color: Color(0x22000000));
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x22000000)),
    );
  }
}
