import 'package:flutter/material.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import 'family_chat_screen.dart';
import 'family_screen.dart';

/// 채팅 탭 — 채팅방 목록. '우리 가족'이 기본방, 이후 친구·동호회 방으로 확장.
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 100),
            children: [
              Row(children: const [
                Text('채팅', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: T.textPrimary)),
                Spacer(),
                ProfileAvatar(),
              ]),
              const SizedBox(height: 4),
              const Text('가족·이웃 반려인들과의 대화', style: TextStyle(fontSize: 13, color: Color(0xB3463C64))),
              const SizedBox(height: 16),
              for (final r in kChatRooms) ...[
                _roomCard(context, r),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              _newChatButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roomCard(BuildContext context, ChatRoom r) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FamilyChatScreen(title: r.name, subtitle: '${r.memberCount}명'),
      )),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          // 방 아이콘
          Container(
            width: 48, height: 48, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: r.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(r.icon, size: 24, color: r.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                ),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: r.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                  child: Text(r.tag, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: r.color)),
                ),
                const SizedBox(width: 6),
                Text('${r.memberCount}명', style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
              ]),
              const SizedBox(height: 5),
              Text(r.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xA8463C64))),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(r.lastTime, style: const TextStyle(fontSize: 11, color: T.textMuted)),
            const SizedBox(height: 6),
            if (r.unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${r.unread}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
              )
            else if (r.isDefault)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamilyScreen())),
                child: const Icon(Icons.pets, size: 16, color: Color(0xFFCABFDC)),
              ),
          ]),
        ]),
      ),
    );
  }

  // 기본방(우리 가족)에서 케어 현황으로 가는 안내 + 새 채팅.
  Widget _newChatButton(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamilyScreen())),
        behavior: HitTestBehavior.opaque,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: const [
            Icon(Icons.diversity_1_rounded, size: 19, color: Color(0xFFFF8F63)),
            SizedBox(width: 10),
            Expanded(
              child: Text('우리 가족 관리 — 멤버·초대·오늘의 케어',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
            ),
            Icon(Icons.chevron_right, size: 18, color: Color(0xFFCABFDC)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('친구 추가 기능 준비 중이에요 · 커뮤니티에서 이웃 반려인을 만나보세요 🐾'), duration: Duration(milliseconds: 2000)),
        ),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xCCFFFFFF),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x80FFFFFF)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.add_comment_outlined, size: 18, color: T.textSecondary),
            SizedBox(width: 8),
            Text('새 채팅', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary)),
          ]),
        ),
      ),
    ]);
  }
}
