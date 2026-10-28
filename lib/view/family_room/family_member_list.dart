import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/family/family_member.dart';
import 'package:ondolbom/vm/family_room/family_member_vm.dart';

class FamilyMemberList extends ConsumerWidget {
  const FamilyMemberList({super.key, required this.familyRoomId});

  final String familyRoomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(familyMembersProvider(familyRoomId));

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 62,
        leading: const AppBackLeading(),
        title: const Text('함께하는 가족'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: () {
              ref.invalidate(familyMembersProvider(familyRoomId));
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error.toString().replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    ref.invalidate(familyMembersProvider(familyRoomId));
                  },
                  child: const Text('다시 조회'),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('참여 중인 가족이 없습니다.'));
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '우리 공간의 가족 ${items.length}명',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF403C39),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '소중한 일상을 함께 돌보는 가족들이에요.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF78716A),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              for (final member in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: memberCard(member),
                ),
            ],
          );
        },
      ),
    );
  }

  // 가족 이름·이메일과 현재 공간의 역할을 표시한다.
  Widget memberCard(FamilyMember member) {
    final name = member.name?.trim();
    final displayName = name == null || name.isEmpty ? '가족' : name;

    final email = member.email?.trim();
    final displayEmail = email == null || email.isEmpty
        ? '등록된 이메일이 없습니다.'
        : email;

    final badgeColor = member.isRepresentative
        ? const Color(0xFFFFEBD9)
        : const Color(0xFFF0F4E9);

    final roleColor = member.isRepresentative
        ? const Color(0xFF99522F)
        : const Color(0xFF526345);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8DFD7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: badgeColor,
            child: Icon(
              member.isRepresentative
                  ? Icons.home_outlined
                  : Icons.person_outline_rounded,
              color: roleColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF403C39),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  displayEmail,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Color(0xFF78716A),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    member.roleName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: roleColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
