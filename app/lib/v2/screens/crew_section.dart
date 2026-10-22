// 커뮤니티 안의 크루 갈래 — 이슈 #417. 서버는 PR #426.
//
// ## 왜 탭이 아니라 커뮤니티 안인가
//
// 이슈가 안 셋을 놓고 물었고 "소모임은 커뮤니티에 넣을 수 있지 않나" 로 정리됐다.
// 탭을 여섯째로 늘리면 라벨이 접힌다 — #396 에서 다섯 탭이 360dp·글자 1.5배에서 이미
// 한계였다. 커뮤니티와 성격도 가깝다: 둘 다 "동네 사람들" 을 보는 자리다.
//
// ## 화면 하나가 아니라 본문 조각이다
//
// `Scaffold` 도 배경도 안 만든다 — 커뮤니티 화면의 것을 그대로 쓴다. 여기서 또 만들면
// 갈래를 바꿀 때 배경이 한 번 깜빡이고, 그 깜빡임은 "다른 화면으로 갔다" 로 읽힌다.
import 'package:flutter/material.dart';

import '../data/crew_repository.dart';
import '../data/neighborhood_store.dart';
import '../data/region_catalog.dart';
import '../domain/crew.dart';
import '../domain/neighborhood.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/crew_create_sheet.dart';
import 'crew_home_screen.dart';
import 'neighborhood_picker_screen.dart';

class CrewSection extends StatefulWidget {
  /// 테스트가 가짜 서버를 넣는 자리. 앱에서는 `null` 이라 기본 리포지토리가 선다.
  final CrewRepository? repository;

  /// 내 동네를 읽는 자리. **테스트만 넘긴다.**
  final NeighborhoodStore? neighborhoods;

  /// 동네 코드를 이름으로 바꾸는 자산. **테스트만 넘긴다** — 3,516줄짜리라 앱에서는
  /// 캐시된 것을 쓴다.
  final RegionCatalog? catalog;

  const CrewSection({super.key, this.repository, this.neighborhoods, this.catalog});

  @override
  State<CrewSection> createState() => _CrewSectionState();
}

class _CrewSectionState extends State<CrewSection> {
  late final CrewRepository _repo = widget.repository ?? CrewRepository();
  late final NeighborhoodStore _store = widget.neighborhoods ?? NeighborhoodStore();

  CrewScope _scope = CrewScope.mine;

  List<Crew> _crews = const [];
  bool _loading = true;

  /// 못 불러온 이유. **빈 목록으로 그리지 않는다** — 빈 목록은 "크루가 없다" 로 읽히고,
  /// 그러면 서버가 죽은 것을 아무도 모른다.
  CrewFailure? _failure;

  /// 내가 고른 동네. 만들기 시트가 이것을 보고 공개를 열지 말지 정한다.
  Neighborhood? _mine;

  RegionCatalog? _catalog;

  /// 요청 세대. 갈래를 빠르게 오갈 때 늦게 온 응답이 화면을 되돌리는 것을 막는다.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog;
    _loadNeighborhood();
    _load();
  }

  Future<void> _loadNeighborhood() async {
    final mine = await _store.read();
    if (!mounted) return;
    setState(() => _mine = mine);
  }

  /// 동네 이름표는 **있으면 좋은 것**이라 실패해도 목록을 막지 않는다.
  Future<void> _loadCatalog() async {
    if (_catalog != null) return;
    try {
      final catalog = await RegionCatalog.load();
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (_) {
      // 자산을 못 읽으면 동네 이름 없이 그린다. 열 자리 코드를 대신 보여 주지 않는다 —
      // 사용자에게 아무 뜻도 없는 숫자다.
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final crews = await _repo.list(scope: _scope);
      if (!mounted || generation != _generation) return;
      setState(() {
        _crews = crews;
        _loading = false;
      });
      await _loadCatalog();
    } on CrewFailure catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = e;
        _crews = const [];
        _loading = false;
      });
    }
  }

  void _selectScope(CrewScope scope) {
    if (_scope == scope) return;
    setState(() => _scope = scope);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _scopeRow(),
      const SizedBox(height: 8),
      Expanded(child: _body()),
    ]);
  }

  Widget _scopeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        _scopeChip(CrewScope.mine, '내 크루'),
        const SizedBox(width: 8),
        _scopeChip(CrewScope.neighborhood, '우리 동네'),
        const Spacer(),
        _iconAction(
          key: const Key('crew-join-by-code'),
          icon: Icons.vpn_key_outlined,
          tooltip: '초대 코드로 참여',
          onTap: _openJoinByCode,
        ),
        const SizedBox(width: 6),
        _iconAction(
          key: const Key('crew-create'),
          icon: Icons.add_rounded,
          tooltip: '크루 만들기',
          onTap: _openCreate,
        ),
      ]),
    );
  }

  Widget _scopeChip(CrewScope scope, String label) {
    final on = _scope == scope;
    return GestureDetector(
      key: Key('crew-scope-${scope.wire}'),
      onTap: () => _selectScope(scope),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: on ? T.sigEnd.withValues(alpha: 0.2) : T.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: on ? T.sigEnd : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: on ? T.textPrimary : T.textMuted)),
      ),
    );
  }

  Widget _iconAction({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      key: key,
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 19, color: T.textSecondary),
      style: IconButton.styleFrom(
        backgroundColor: T.surface,
        shape: const CircleBorder(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failure case final failure?) {
      return _failureView(failure);
    }
    if (_crews.isEmpty) {
      return _emptyView();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            12, 4, 12, MediaQuery.of(context).padding.bottom + 100),
        children: [
          for (final crew in _crews) ...[
            _card(crew),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  /// 크루가 하나도 없을 때. **갈래마다 다른 말을 한다** — 사용자가 할 일이 다르다.
  /// 내 크루가 비면 만들거나 찾으면 되고, 우리 동네가 비면 만드는 것뿐이다.
  Widget _emptyView() {
    final mine = _scope == CrewScope.mine;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            mine ? '아직 든 크루가 없어요' : '우리 동네에 아직 크루가 없어요',
            key: const Key('crew-empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(mine ? '우리 동네에서 찾아보거나 하나 만들어 볼까요' : '하나 만들어 볼까요',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: T.textMuted)),
          const SizedBox(height: 14),
          _primaryButton('크루 만들기', _openCreate),
        ]),
      ),
    );
  }

  /// 못 불러왔을 때. **빈 목록이 아니라 이유와 다음 동작이다.**
  ///
  /// 동네를 안 골라서 400 을 받은 것은 "고장" 이 아니라 **아직 안 한 일**이라, 다시
  /// 시도가 아니라 동네 고르기로 보낸다. 다시 눌러도 같은 400 이다.
  Widget _failureView(CrewFailure failure) {
    final needsNeighborhood =
        failure.kind == CrewFailureKind.invalid && _scope == CrewScope.neighborhood;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            needsNeighborhood
                ? '동네를 먼저 골라 주세요'
                : failure.message ?? '크루를 불러오지 못했어요',
            key: const Key('crew-failure'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            needsNeighborhood
                ? '우리 동네 크루는 내가 고른 동네로 찾아요'
                : '잠시 뒤 다시 시도해 주세요',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: T.textMuted),
          ),
          const SizedBox(height: 14),
          needsNeighborhood
              ? _primaryButton('동네 고르기', _openNeighborhoodPicker)
              : _primaryButton('다시 시도', _load),
        ]),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
            gradient: T.sig, borderRadius: BorderRadius.circular(14)),
        child: Text(label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    );
  }

  Widget _card(Crew crew) {
    final district = _districtOf(crew);
    return GestureDetector(
      key: Key('crew-card-${crew.id}'),
      onTap: () => _openHome(crew),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF57C98A).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.directions_walk_rounded,
                size: 22, color: Color(0xFF3FA873)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(crew.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: T.textPrimary)),
                    ),
                    const SizedBox(width: 6),
                    _visibilityBadge(crew.visibility),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (district != null) district,
                      '${crew.headcount}명',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: T.textMuted),
                  ),
                  if (crew.intro case final intro?) ...[
                    const SizedBox(height: 4),
                    Text(intro,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: T.textSecondary)),
                  ],
                ]),
          ),
          const SizedBox(width: 8),
          _cardAction(crew),
        ]),
      ),
    );
  }

  /// 카드 오른쪽. **든 크루와 안 든 크루가 다른 말을 한다** — 하나는 들어가는 것이고
  /// 하나는 참여하는 것이다. 자리가 없으면 그것을 먼저 말한다.
  Widget _cardAction(Crew crew) {
    if (crew.mine) {
      return const Icon(Icons.chevron_right_rounded, size: 22, color: T.textFaint);
    }
    if (crew.isFull) {
      return const Text('정원 참',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: T.textFaint));
    }
    return const Text('참여',
        style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF3FA873)));
  }

  Widget _visibilityBadge(CrewVisibility visibility) {
    final open = visibility.isPublic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: (open ? const Color(0xFF57C98A) : T.textMuted).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(visibility.label,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: open ? const Color(0xFF3FA873) : T.textMuted)),
    );
  }

  /// "성동구 왕십리2동". 자산을 못 읽었거나 동네 없는 크루면 `null` 이다 — 열 자리 코드를
  /// 대신 보여 주지 않는다.
  String? _districtOf(Crew crew) =>
      _catalog?.byCode(crew.neighborhoodCode)?.label;

  Future<void> _openHome(Crew crew) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CrewHomeScreen(crewId: crew.id, repository: _repo),
    ));
    if (!mounted) return;
    // 들어갔거나 나왔으면 인원과 "내 크루" 여부가 달라진다. 서버가 다시 답하게 한다 —
    // 앱이 지레짐작하면 참여가 실패했을 때 목록이 거짓말을 한다.
    if (changed == true) await _load();
  }

  Future<void> _openCreate() async {
    final created = await showCrewCreateSheet(
      context,
      repository: _repo,
      myNeighborhood: _mine,
    );
    if (!mounted || created == null) return;
    // 만든 크루는 **내 크루**다. 우리 동네를 보고 있었다면 그리로 안 가고 내 크루로
    // 옮긴다 — 초대 크루로 만들었으면 우리 동네 목록에는 아예 안 뜬다.
    setState(() => _scope = CrewScope.mine);
    await _load();
    if (!mounted) return;
    await _openHome(created);
  }

  Future<void> _openJoinByCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinByCodeDialog(),
    );
    if (!mounted || code == null || code.isEmpty) return;
    try {
      final crew = await _repo.joinByCode(code);
      if (!mounted) return;
      setState(() => _scope = CrewScope.mine);
      await _load();
      if (!mounted) return;
      await _openHome(crew);
    } on CrewFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_joinReason(e))));
    }
  }

  /// 참여 실패를 **네 갈래**로 말한다. 하나로 뭉치면 사용자는 자기가 할 일을 모른다 —
  /// 정원이 찬 것은 새 코드를 받아도 소용없고, 죽은 코드는 기다려도 안 열린다.
  static String _joinReason(CrewFailure failure) => switch (failure.kind) {
        CrewFailureKind.full => '정원이 찼어요. 자리가 나면 들어갈 수 있어요.',
        CrewFailureKind.inviteDead => '코드가 만료됐어요. 새 코드를 받아 주세요.',
        CrewFailureKind.forbidden =>
          failure.message ?? '이 코드로는 크루에 들어갈 수 없어요.',
        CrewFailureKind.notFound => '그런 코드가 없어요.',
        CrewFailureKind.network => '연결이 끊겼어요. 잠시 뒤 다시 시도해 주세요.',
        CrewFailureKind.invalid => failure.message ?? '코드를 다시 확인해 주세요.',
        // 참여 경로에서는 안 온다 — 품앗이 맡기·크루 지우기의 409 다(#417).
        CrewFailureKind.taken || CrewFailureKind.notAlone =>
          failure.message ?? '요청을 처리하지 못했어요.',
      };

  Future<void> _openNeighborhoodPicker() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NeighborhoodPickerScreen()));
    if (!mounted) return;
    await _loadNeighborhood();
    await _load();
  }
}

/// 코드를 받는 자리. 채팅의 `InviteJoinScreen` 과 달리 **화면을 안 만든다** — 크루 참여는
/// 목록에서 한 번 누르고 끝나는 일이라, 화면을 밀어 올리면 돌아올 곳을 한 번 더 눌러야 한다.
class _JoinByCodeDialog extends StatefulWidget {
  const _JoinByCodeDialog();

  @override
  State<_JoinByCodeDialog> createState() => _JoinByCodeDialogState();
}

class _JoinByCodeDialogState extends State<_JoinByCodeDialog> {
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: T.bgTop,
      title: const Text('초대 코드로 참여',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: TextField(
        key: const Key('crew-code-field'),
        controller: _code,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(hintText: '방장에게 받은 코드'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기')),
        FilledButton(
          key: const Key('crew-code-submit'),
          onPressed: () => Navigator.of(context).pop(_code.text.trim()),
          child: const Text('참여'),
        ),
      ],
    );
  }
}
