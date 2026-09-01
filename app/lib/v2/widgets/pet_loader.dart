// lib/v2/widgets/pet_loader.dart
//
// 반려동물 목록을 언제 불러오는지 정하는 한 곳 — 이슈 #159.
//
// ## 왜 위젯인가
//
// `AuthState` 가 `PetSync` 를 부르게 하면 인증 계층이 반려동물 도메인을 알게 된다.
// 반대로 화면마다 `initState` 에서 부르면 **한 곳을 빠뜨리는 날**이 오고, 그 화면만
// 영원히 빈 목록을 본다. 그래서 셸을 감싸는 위젯 하나가 그 책임을 진다.
//
// ## 언제 부르는가
//
//  - 앱이 뜰 때 (이미 로그인돼 있으면)
//  - 로그인 상태가 바뀔 때 — 로그인하면 불러오고, 로그아웃하면 **지운다**
//  - 등록·삭제 신호(`petRevision`)가 올 때
//
// 로그아웃에서 지우는 것이 중요하다. 안 지우면 다음 사람이 앞사람의 아이를 본다.
library;

import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/pet_sync.dart';

/// 자식을 그리면서 반려동물 목록을 서버와 맞춘다.
class PetLoader extends StatefulWidget {
  final Widget child;

  const PetLoader({super.key, required this.child});

  @override
  State<PetLoader> createState() => _PetLoaderState();
}

class _PetLoaderState extends State<PetLoader> {
  /// 겹쳐 들어온 응답이 순서를 거슬러 덮어쓰는 것을 막는다.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    AuthState.status.addListener(_onAuthChanged);
    petRevision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    AuthState.status.removeListener(_onAuthChanged);
    petRevision.removeListener(_reload);
    super.dispose();
  }

  void _onAuthChanged() {
    if (AuthState.isAuthenticated) {
      _reload();
      return;
    }
    // 로그인 상태가 아니다. **화면에서 지운다** — 다음 사람이 앞사람의 아이를 보면 안 된다.
    if (AuthState.status.value == AuthStatus.unauthenticated) {
      PetSync.clear();
    }
  }

  Future<void> _reload() async {
    if (!AuthState.isAuthenticated) return;
    final mine = ++_generation;
    await PetSync().load();
    if (mine != _generation) return;
    // load() 가 kMyPets 를 갈아 끼우고, 화면은 그 ValueNotifier 를 구독한다.
    // 여기서 setState 를 부를 필요가 없다.
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
