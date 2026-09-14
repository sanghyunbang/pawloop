// lib/v2/widgets/notification_route_sync.dart
//
// 눌린 알림이 남긴 곳으로 한 번 보내는 조각 — 아무것도 안 그린다(`walk_reminder_sync.dart` 와 같은 모양).
//
// 화면과 탭을 아는 것은 이 조각이 아니라 부르는 쪽(`MainShell`)이다. 여기는 **언제 보내는가**만 안다:
// 홈이 떴을 때 이미 와 있던 것 하나, 그리고 앱이 떠 있는 동안 새로 눌린 것.
import 'package:flutter/material.dart';

import '../data/notification_route.dart';

class NotificationRouteSync extends StatefulWidget {
  const NotificationRouteSync({super.key, required this.onGo});

  /// 갈 곳이 생겼다. 탭을 바꾸거나 화면을 여는 것은 이 콜백의 일이다.
  final void Function(BuildContext context, NotificationDestination destination) onGo;

  @override
  State<NotificationRouteSync> createState() => _NotificationRouteSyncState();
}

class _NotificationRouteSyncState extends State<NotificationRouteSync> {
  @override
  void initState() {
    super.initState();
    NotificationRouteInbox.pending.addListener(_drain);
    // 꺼져 있던 앱이 알림으로 떴다면 이미 와 있다 — 첫 프레임 뒤에 본다(그 전에는 열 화면이 없다).
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    NotificationRouteInbox.pending.removeListener(_drain);
    super.dispose();
  }

  void _drain() {
    if (!mounted) return;
    final destination = NotificationRouteInbox.take();
    if (destination == null) return;
    widget.onGo(context, destination);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
