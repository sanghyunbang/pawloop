// 글쓰기 화면의 사진·영상 칸 — 고르고, 다시 인코딩하고, 올리고, 순서를 든다. 이슈 #429.
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
// ## 영상은 하나고, 세 단계다
//
// 서버가 한 글에 영상을 하나만 받는다. 그래서 "영상 추가" 는 영상 칸이 없을 때만 있다. 고르면
// `VideoPrep`(720p · 위치 상자 덮기 · 포스터)을 지나고, 저장소가 세 단계(자리 잡기 · S3 PUT ·
// complete)로 올린다. 칸은 압축 중 → 올리는 중(%) → 올라감을 그린다. 원본 파일은 여기서 끝나고
// 720p 만 나간다 — 사진의 `ImagePrep` 과 같은 자리다.
//
// ## 레거시 `MediaGridField` 를 안 쓴다
//
// 그것은 `context.read<MediaRepository>()` 로 Provider 를 찾는다. v2 화면은 저장소를
// 생성자로 받는다 — 테스트가 가짜를 꽂는 자리다. 모양은 비슷하지만 배선이 다르다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/image_prep.dart';
import '../data/media_picker.dart';
import '../data/post_media_repository.dart';
import '../data/video_prep.dart';
import '../domain/post_media.dart';
import '../theme/app_tokens.dart';

/// 이 위젯이 밖으로 내는 상태.
@immutable
class PostMediaSelection {
  /// 지금까지 올라가 있는 사진·영상의 id — 고른 순서. 글 저장에 그대로 싣는다.
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

  /// 사진을 다시 인코딩하는 함수. 기본은 격리 스레드의 `ImagePrep.prepare` 다. 테스트가
  /// 동기 버전을 꽂아 시간을 안 기다린다.
  final ImagePreparer prepare;

  /// 영상을 준비하는 함수(720p · 위치 상자 덮기 · 포스터). 기본은 `VideoPrep.prepare` 다.
  /// 네이티브 재인코더가 테스트에서 안 돌아 테스트는 가짜를 꽂는다.
  final VideoPreparer prepareVideo;

  /// 한 글의 상한. 서버와 같은 10 이다 — 사진·영상을 합쳐서.
  final int max;

  const PostMediaField({
    super.key,
    required this.repository,
    required this.picker,
    required this.onChanged,
    this.initial = const [],
    this.prepare = ImagePrep.prepare,
    this.prepareVideo = VideoPrep.prepare,
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

  /// 새로 고른 사진 원본. 아니면 `null`.
  final PickedImage? picked;

  /// 새로 고른 영상. 아니면 `null`.
  final PickedVideo? pickedVideo;

  PreparedImage? prepared;
  PreparedVideo? preparedVideo;
  UploadedPostMedia? uploaded;
  Object? error;
  bool working = false;

  /// S3 로 올린 비율(0..1). 영상만. 0 이면 아직 압축 중이다.
  double progress = 0;

  _Slot.existing(this.key, PostMedia media)
      : existing = media,
        picked = null,
        pickedVideo = null;

  _Slot.picked(this.key, PickedImage image)
      : existing = null,
        picked = image,
        pickedVideo = null;

  _Slot.video(this.key, PickedVideo video)
      : existing = null,
        picked = null,
        pickedVideo = video;

  int? get id => existing?.id ?? uploaded?.id;

  bool get done => id != null;

  bool get isVideo => pickedVideo != null || (existing?.kind.isVideo ?? false);

  /// 칸에 쓸 길이. 준비된 영상은 나가는 파일의 길이, 붙어 있던 영상은 서버가 준 길이.
  String? get durationLabel {
    if (preparedVideo case final video?) return formatMediaDuration(video.durationMs);
    return existing?.durationLabel;
  }
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

  /// 영상 칸이 이미 있는가 — 서버가 한 글에 하나만 받는다.
  bool get _hasVideo => _slots.any((s) => s.isVideo);

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

  Future<void> _pickVideo() async {
    if (_picking || _remaining <= 0 || _hasVideo) return;
    setState(() => _picking = true);
    _emit();
    PickedVideo? video;
    try {
      video = await widget.picker.pickVideo();
    } catch (_) {
      video = null;
    }
    if (!mounted) return;
    if (video == null || _hasVideo || _remaining <= 0) {
      setState(() => _picking = false);
      _emit();
      return;
    }
    final slot = _Slot.video(_nextKey++, video);
    setState(() {
      _slots.add(slot);
      _picking = false;
    });
    _emit();
    await _upload(slot);
  }

  Future<void> _upload(_Slot slot) async {
    if (!_slots.contains(slot) || slot.working || slot.done) return;
    setState(() {
      slot.working = true;
      slot.error = null;
      slot.progress = 0;
    });
    _emit();
    try {
      if (slot.pickedVideo case final video?) {
        // 위치 상자가 덮이는 자리 — 원본은 여기서 끝나고 720p 만 나간다.
        slot.preparedVideo ??= await widget.prepareVideo(video.path);
        if (!mounted || !_slots.contains(slot)) return;
        final prepared = slot.preparedVideo!;
        setState(() {}); // 포스터가 생겼다
        slot.uploaded = await widget.repository.uploadVideo(
          prepared,
          onProgress: (fraction) {
            if (mounted) setState(() => slot.progress = fraction);
          },
        );
        // 720p 파일은 올라갔으니 지운다 — 원본은 갤러리에 그대로다. 기다리지 않는다: 캐시 파일 하나
        // 지우는 일이 칸의 상태를 붙들 이유가 없고, 가짜 시계 안에서는 파일 IO 가 안 끝난다.
        unawaited(prepared.discard());
      } else {
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
      }
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
    slot.preparedVideo?.discard();
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
    final canAddVideo = canAdd && !_hasVideo;
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
      // 버튼 둘과 안내문이 한 Wrap 이다 — 폰 폭에서는 한 줄이고, 좁은 화면·큰 글씨에서는 안내문이
      // 다음 줄로 내려간다. Row 로 두면 그때 넘친다.
      Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (canAdd) _addButton(),
          if (canAddVideo) _addVideoButton(),
          Text(
            '${_slots.length} / ${widget.max}장 · 위치 정보는 지우고 올려요',
            key: const Key('post-media-count'),
            style: const TextStyle(fontSize: 11.5, color: T.textMuted, height: 1.3),
          ),
        ],
      ),
    ]);
  }

  ButtonStyle get _buttonStyle => OutlinedButton.styleFrom(
        foregroundColor: T.textSecondary,
        backgroundColor: const Color(0x99FFFFFF),
        side: const BorderSide(color: Color(0x338C7BFF)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _addButton() => OutlinedButton.icon(
        key: const Key('post-media-add'),
        onPressed: _pick,
        style: _buttonStyle,
        icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
        label: const Text('사진 추가', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _addVideoButton() => OutlinedButton.icon(
        key: const Key('post-media-add-video'),
        onPressed: _pickVideo,
        style: _buttonStyle,
        icon: const Icon(Icons.videocam_outlined, size: 18),
        label: const Text('영상 추가', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _tile(_Slot slot) {
    final Widget picture;
    if (slot.existing case final existing?) {
      picture = _network(existing.thumbnailUrl);
    } else if (slot.preparedVideo case final video?) {
      picture = Image.memory(
        video.poster,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF2B2440)),
      );
    } else if (slot.pickedVideo != null) {
      // 압축이 끝나야 포스터가 있다 — 그전엔 어두운 칸이다.
      picture = const ColoredBox(color: Color(0xFF2B2440));
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
          if (slot.isVideo && !slot.working && slot.error == null)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded, size: 28, color: Colors.white),
            ),
          if (slot.durationLabel case final label? when !slot.working && slot.error == null)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xB3000000),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(label,
                    key: Key('post-media-duration-${slot.key}'),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          if (slot.working)
            Container(
              key: Key('post-media-working-${slot.key}'),
              color: const Color(0x66000000),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  ),
                  if (slot.isVideo) ...[
                    const SizedBox(height: 6),
                    Text(
                      slot.progress <= 0 ? '압축 중' : '${(slot.progress * 100).round()}%',
                      key: Key('post-media-progress-${slot.key}'),
                      style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.2),
                    ),
                  ],
                ]),
              ),
            ),
          if (slot.error != null)
            Container(
              key: Key('post-media-error-${slot.key}'),
              color: const Color(0x99000000),
              padding: const EdgeInsets.all(6),
              child: Center(
                child: Text(_errorLabel(slot.error!),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.3)),
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

  /// 칸에 쓰는 실패 이유. 준비가 거절한 것(60초 · 크기 · 위치 정보)은 다시 눌러도 같으니 이유만
  /// 쓰고, 서버가 문구를 줬으면 그것을, 아니면 "올리지 못했어요" 다.
  static String _errorLabel(Object error) {
    if (error is VideoPrepException) return error.message;
    if (error is PostMediaFailure && error.message != null) return '${error.message}\n눌러서 다시';
    return '올리지 못했어요\n눌러서 다시';
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
