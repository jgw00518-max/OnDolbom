import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/schedules/schedule.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/family_room_notifier.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';

// 상세 표시와 버튼 처리 상태는 화면에서, API 요청은 기존 일정 VM에서 관리한다.
class ScheduleDetail extends ConsumerStatefulWidget {
  const ScheduleDetail({super.key, required this.item, required this.query});
  final Schedule item;
  final ScheduleQuery query;

  @override
  ConsumerState<ScheduleDetail> createState() => _ScheduleDetailState();
}

class _ScheduleDetailState extends ConsumerState<ScheduleDetail> {
  bool isAccepting = false;
  bool accepted = false;
  String? errorMessage;
  late final String? loginUid;

  @override
  void initState() {
    super.initState();
    loginUid = ref.read(firebaseAuthProvider).currentUser?.uid;
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(familyRoomProvider);
    final member = rooms.selectedParticipation;
    final user = ref.watch(authUserProvider).asData?.value;
    final canView =
        user != null &&
        user.uid == loginUid &&
        rooms.selectedRoomId == widget.query.familyRoomId &&
        member != null &&
        member.isActive;
    if (!canView) {
      return AlertDialog(
        title: const Text('돌봄 일정'),
        content: const Text('로그인 상태와 가족 공간 참여를 다시 확인해 주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      );
    }

    final schedules = ref.watch(scheduleListProvider(widget.query));
    Schedule? item;
    if (schedules.asData != null) {
      for (final candidate in schedules.asData!.value) {
        if (candidate.seq == widget.item.seq) item = candidate;
      }
    } else {
      item = widget.item;
    }
    final canAccept =
        item != null &&
        !member.isRepresentative &&
        item.acceptedBy == null &&
        item.state == '미완료' &&
        !accepted &&
        !schedules.isLoading &&
        !schedules.hasError;

    final assigned = item?.acceptedBy != null || accepted;
    // 수락 성공 표시와 본인 여부를 구분한다.
    // Firebase UID가 아닌 서버 프로필의 MySQL ID로 실제 수락자를 비교한다.
    final profileState = ref.watch(userProfileProvider);
    final currentUserId = !profileState.isLoading && !profileState.hasError
        ? profileState.asData?.value?.userId
        : null;
    final mine =
        !member.isRepresentative &&
        currentUserId != null &&
        item?.acceptedBy != null &&
        item!.acceptedBy == currentUserId;
    final statusText = mine
        ? '담당 중'
        : assigned
        ? '담당자 등록 완료'
        : '담당자 모집 중';
    final personName = item?.acceptedName ?? (accepted ? '나' : '가족');

    return PopScope(
      canPop: !isAccepting,
      child: Dialog(
        backgroundColor: const Color(0xFFFFFCF8),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(22, 18, 12, 18),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '돌봄 일정',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF403C39),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('schedule-detail-close'),
                      tooltip: '닫기',
                      onPressed: isAccepting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Color(0xFF78716A)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE8DFD7)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item == null)
                        const Text('일정이 삭제되었거나 더 이상 조회할 수 없습니다.')
                      else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBD9),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            statusText,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF756B60),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF403C39),
                          ),
                        ),
                        const SizedBox(height: 28),
                        infoRow(
                          '날짜',
                          '${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}',
                        ),
                        infoRow('시간', '${item.startTime} – ${item.endTime}'),
                        infoRow('담당 인원', assigned ? '1명 · 등록 완료' : '1명 · 모집 중'),
                        infoRow('일정 상태', item.state),
                        infoRow(
                          '메모',
                          item.memo == null || item.memo!.isEmpty
                              ? '등록된 메모가 없습니다.'
                              : item.memo!,
                        ),
                        infoRow('등록자', item.creatorName ?? '가족'),
                        infoRow('알림 대상', '가족 공간 전체'),
                        const SizedBox(height: 18),
                        Text(
                          '담당 가족 ${assigned ? 1 : 0}명',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF403C39),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (!assigned)
                          const Text(
                            '아직 등록된 담당자가 없습니다.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF78716A),
                            ),
                          )
                        else
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 21,
                                backgroundColor: const Color(0xFFB7C8A1),
                                child: Text(
                                  personName.characters.take(2).toString(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF403C39),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  personName,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF403C39),
                                  ),
                                ),
                              ),
                              if (mine)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBD9),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    '나',
                                    style: TextStyle(
                                      color: Color(0xFF99522F),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                      if (errorMessage != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (schedules.hasError) ...[
                        const SizedBox(height: 16),
                        Text(
                          accepted
                              ? '수락은 완료되었습니다. 최신 일정 정보를 다시 조회해 주세요.'
                              : '최신 일정 정보를 불러오지 못했습니다. 다시 조회해 주세요.',
                        ),
                        TextButton(
                          onPressed: isAccepting
                              ? null
                              : () => ref.invalidate(
                                  scheduleListProvider(widget.query),
                                ),
                          child: const Text('다시 조회'),
                        ),
                      ],
                      if (canAccept || isAccepting) ...[
                        const SizedBox(height: 26),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const ValueKey('schedule-accept'),
                            onPressed: isAccepting ? null : acceptAction,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF7AC82),
                              foregroundColor: const Color(0xFF553724),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 18,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              isAccepting ? '수락 중…' : '신청하고 담당자로 참여하기',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 목업처럼 왼쪽 항목명과 오른쪽 값을 일정한 간격으로 배치한다.
  Widget infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: Color(0xFF78716A)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                color: Color(0xFF403C39),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 반복 클릭을 막고 서버 확인 후 목록과 상세를 같은 조회 결과로 갱신한다.
  Future<void> acceptAction() async {
    if (isAccepting || accepted) return;
    setState(() {
      isAccepting = true;
      errorMessage = null;
    });
    try {
      await ref.read(scheduleVmProvider).acceptSchedule(widget.item.seq);
      if (!mounted) return;
      setState(() => accepted = true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => errorMessage = error.toString().replaceFirst('Exception: ', ''),
      );
    }
    if (!mounted) return;
    // 다른 가족이 먼저 수락했거나 응답이 끊긴 경우에도 실제 서버 상태를 확인한다.
    ref.invalidate(scheduleListProvider(widget.query));
    try {
      await ref.read(scheduleListProvider(widget.query).future);
    } catch (_) {
      // 조회 실패는 화면에 별도로 표시하고 이미 성공한 수락과 구분한다.
    } finally {
      if (mounted) setState(() => isAccepting = false);
    }
  }
}
