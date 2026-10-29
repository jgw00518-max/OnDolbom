import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/schedules/schedule.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';
import 'package:ondolbom/view/schedules/schedule_create.dart';

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
  bool isEditing = false;
  bool isResponding = false;
  bool isDeleting = false;
  bool isWithdrawing = false;
  bool accepted = false;
  String? errorMessage;
  late final String? loginUid;
  SharedPreferences? reviewPreferences;
  String? seenContentVersion;
  final Set<String> displayedChanges = {};

  String reviewKey() =>
      'schedule_content_seen:$loginUid:'
      '${widget.query.familyRoomId}:${widget.item.seq}';

  Future<void> loadReviewState() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    if (!mounted) return;
    setState(() {
      reviewPreferences = preferences;
      seenContentVersion = preferences.getString(reviewKey());
    });
  }

  // 화면에 표시한 버전만 저장한다. 열린 창의 비교 표시는 유지한다.
  void markContentDisplayed(String version) {
    if (displayedChanges.contains(version)) return;
    displayedChanges.add(version);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          ref.read(firebaseAuthProvider).currentUser?.uid != loginUid ||
          ref.read(familyRoomProvider).selectedRoomId !=
              widget.query.familyRoomId) {
        return;
      }
      await reviewPreferences?.setString(reviewKey(), version);
    });
  }

  // 처리 중에는 다른 버튼과 뒤로 가기를 막는다.
  bool get isBusy =>
      isAccepting || isEditing || isResponding || isDeleting || isWithdrawing;

  @override
  void initState() {
    super.initState();
    loginUid = ref.read(firebaseAuthProvider).currentUser?.uid;
    loadReviewState();
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
        content: const Text('로그인 상태와 돌봄 공간 참여를 다시 확인해 주세요.'),
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
    final canRespond =
        item != null &&
        mine &&
        item.reconfirmRequired &&
        item.reconfirmUserId == currentUserId &&
        item.historySeq != null &&
        item.state == '미완료' &&
        !schedules.isLoading &&
        !schedules.hasError;
    final statusText = item?.reconfirmRequired == true
        ? '재수락 요청 중'
        : mine
        ? '담당 중'
        : assigned
        ? '담당자 등록 완료'
        : '담당자 모집 중';
    final personName = item?.acceptedName ?? (accepted ? '나' : '가족');
    // 재수락 대기 중에만 변경 전 내용을 비교한다.
    final previous = item?.reconfirmRequired == true
        ? item?.previousSchedule
        : null;
    final contentVersion = item?.contentChangeVersion;
    final showContentChange =
        reviewPreferences != null &&
        contentVersion != null &&
        (displayedChanges.contains(contentVersion) ||
            seenContentVersion != contentVersion);
    final contentBefore = showContentChange
        ? item?.contentBeforeFor(seenContentVersion)
        : null;
    if (showContentChange && contentBefore != null) {
      markContentDisplayed(contentVersion);
    }
    final responseDueAt = item?.reconfirmResponseDueAt;
    return PopScope(
      canPop: !isBusy,
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
                      onPressed: isBusy ? null : () => Navigator.pop(context),
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
                        changeText(
                          item.title,
                          previousValue:
                              contentBefore?.title ??
                              (contentVersion == null ? previous?.title : null),
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF403C39),
                          ),
                        ),
                        const SizedBox(height: 28),
                        infoRow(
                          '날짜',
                          dateText(item.date),
                          previousValue: previous == null
                              ? null
                              : dateText(previous.date),
                        ),
                        infoRow(
                          '시작시간',
                          item.startTime,
                          previousValue: previous?.startTime,
                        ),
                        infoRow(
                          '종료시간',
                          item.endTime,
                          previousValue: previous?.endTime,
                        ),
                        infoRow('담당자', assigned ? personName : '모집 중'),
                        infoRow('일정 상태', item.state),
                        if (item.reconfirmRequired) ...[
                          if (responseDueAt != null || !item.reconfirmIsUrgent)
                            infoRow(
                              '응답 기한',
                              responseDueAt == null
                                  ? '기한을 확인하지 못했습니다.'
                                  : '${dateText(responseDueAt)} '
                                        '${responseDueAt.hour.toString().padLeft(2, '0')}:'
                                        '${responseDueAt.minute.toString().padLeft(2, '0')}',
                              valueStyle: TextStyle(
                                color: item.reconfirmIsUrgent
                                    ? const Color(0xFFC62828)
                                    : Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                        infoRow(
                          '메모',
                          memoText(item.memo),
                          previousValue: contentBefore != null
                              ? memoText(contentBefore.memo)
                              : contentVersion == null && previous != null
                              ? memoText(previous.memo)
                              : null,
                          newLine: true,
                        ),
                        infoRow('등록자', item.creatorName ?? '가족'),
                        const SizedBox(height: 18),
                        Text(
                          '담당 가족',
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
                                backgroundColor: AppColors.sage,
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
                      if (item != null &&
                          member.isRepresentative &&
                          !schedules.isLoading &&
                          !schedules.hasError) ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: isBusy
                                    ? null
                                    : () => deleteAction(item!),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFB87568),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(isDeleting ? '삭제 중…' : '일정 삭제'),
                              ),
                            ),
                            if (item.state == '미완료') ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: isBusy
                                      ? null
                                      : () => editAction(item!),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 48),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: Text(isEditing ? '편집 중…' : '일정 변경'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (item != null &&
                          mine &&
                          !item.reconfirmRequired &&
                          item.state == '미완료' &&
                          item.acceptedAt != null &&
                          !schedules.isLoading &&
                          !schedules.hasError) ...[
                        const SizedBox(height: 24),
                        Center(
                          child: SizedBox(
                            width: 156,
                            child: FilledButton(
                              onPressed: isBusy
                                  ? null
                                  : () => withdrawAction(item!),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFB87568),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 48),
                              ),
                              child: Text(isWithdrawing ? '처리 중…' : '일정 참여 취소'),
                            ),
                          ),
                        ),
                      ],
                      if (canRespond) ...[
                        const SizedBox(height: 24),
                        Text(
                          responseDueAt != null
                              ? '변경된 일정 내용을 확인하고 재수락하거나 거절해 주세요.\n'
                                    '응답 기한 내에 응답하지 않으면 담당 배정이 자동 해제됩니다.'
                              : '변경된 일정 내용을 확인하고 재수락하거나 거절해 주세요.',
                          style: const TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: isBusy
                                    ? null
                                    : () => respondAction(item!, false),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFB87568),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 48),
                                ),
                                child: const Text('거절'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: isBusy
                                    ? null
                                    : () => respondAction(item!, true),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                                child: Text(isResponding ? '처리 중…' : '재수락'),
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
                          onPressed: isBusy
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
                            onPressed: isBusy ? null : acceptAction,
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

  Widget infoRow(
    String label,
    String value, {
    String? previousValue,
    bool newLine = false,
    TextStyle? valueStyle,
  }) {
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
            child: changeText(
              value,
              previousValue: previousValue,
              newLine: newLine,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                color: Color(0xFF403C39),
              ).merge(valueStyle),
            ),
          ),
        ],
      ),
    );
  }

  // 변경된 항목만 기존 값 → 빨간색 새 값으로 표시한다.
  Widget changeText(
    String value, {
    String? previousValue,
    bool newLine = false,
    TextStyle? style,
  }) {
    if (previousValue == null || previousValue == value) {
      return Text(value, style: style);
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: previousValue,
            style: const TextStyle(
              color: Color(0xFF78716A),
              fontWeight: FontWeight.normal,
            ),
          ),
          TextSpan(
            text: newLine ? '\n→ ' : ' → ',
            style: const TextStyle(
              color: Color(0xFFC62828),
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Color(0xFFC62828),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      style: style,
    );
  }

  String dateText(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String memoText(String? memo) {
    return memo == null || memo.isEmpty ? '등록된 메모가 없습니다.' : memo;
  }

  Future<void> withdrawAction(Schedule item) async {
    if (isBusy) return;
    // 취소 확인창을 여는 시점의 최신 표시 일정으로 남은 시간을 확인한다.
    final timeParts = item.startTime.split(':');
    final startsAt = DateTime(
      item.date.year,
      item.date.month,
      item.date.day,
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
    final remaining = startsAt.difference(DateTime.now());
    final needsContact =
        remaining > Duration.zero && remaining < const Duration(hours: 24);
    setState(() => isWithdrawing = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '일정 참여 취소',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '이 일정의 담당 참여를 취소할까요?\n'
                '담당 배정이 해제되고,\n'
                '가족에게 재모집 안내가 전달됩니다.',
              ),
              if (needsContact) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.peachSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '일정 시작까지 24시간이 채 남지 않았습니다.\n'
                    '주보호자에게 알려 새로운 담당 가족을 찾도록\n'
                    '알려주세요',
                    style: TextStyle(
                      color: Color(0xFF9B5C50),
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB87568),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('참여 취소'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => isWithdrawing = false);
      return;
    }
    try {
      if (ref.read(firebaseAuthProvider).currentUser?.uid != loginUid ||
          ref.read(familyRoomProvider).selectedRoomId !=
              widget.query.familyRoomId) {
        throw Exception('로그인 상태와 가족 공간을 다시 확인해 주세요.');
      }
      final published = await ref
          .read(scheduleVmProvider)
          .withdrawSchedule(item);
      if (mounted) {
        setState(() {
          accepted = false;
          errorMessage = published ? null : '참여 취소는 완료됐지만 알림 발행 확인이 필요합니다.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => errorMessage = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
    if (!mounted) return;
    ref.invalidate(scheduleListProvider(widget.query));
    try {
      await ref.read(scheduleListProvider(widget.query).future);
    } catch (_) {
      /* 기존 조회 오류 안내를 사용한다. */
    } finally {
      if (mounted) setState(() => isWithdrawing = false);
    }
  }

  // 기존 담당자가 재수락·거절하고 최신 일정으로 화면을 갱신한다.
  Future<void> respondAction(Schedule item, bool acceptChange) async {
    if (isBusy) return;

    if (item.historySeq == null ||
        ref.read(firebaseAuthProvider).currentUser?.uid != loginUid ||
        ref.read(familyRoomProvider).selectedRoomId !=
            widget.query.familyRoomId) {
      setState(() {
        errorMessage = '로그인 상태와 선택한 일정을 다시 확인해 주세요.';
      });
      return;
    }

    setState(() {
      isResponding = true;
      errorMessage = null;
    });

    try {
      await ref
          .read(scheduleVmProvider)
          .respondScheduleChange(
            scheduleSeq: item.seq,
            historySeq: item.historySeq!,
            accepted: acceptChange,
          );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }

    if (!mounted) return;

    // 응답이 끊겨도 서버에서 처리됐을 수 있으므로 다시 조회한다.
    ref.invalidate(scheduleListProvider(widget.query));

    try {
      await ref.read(scheduleListProvider(widget.query).future);
    } catch (_) {
      // 조회 실패 안내는 기존 화면의 다시 조회 영역에서 표시한다.
    } finally {
      if (mounted) {
        setState(() {
          isResponding = false;
        });
      }
    }
  }

  // 반복 클릭을 막고 서버 확인 후 목록과 상세를 같은 조회 결과로 갱신한다.
  Future<void> acceptAction() async {
    if (isBusy || accepted) return;
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

  // 현재 일정의 최신 내용을 편집 화면에 전달한다.
  Future<void> editAction(Schedule? item) async {
    if (item == null || isBusy) {
      return;
    }

    final rooms = ref.read(familyRoomProvider);
    final room = rooms.selectedRoom;

    if (room == null ||
        room.familyRoomId != widget.query.familyRoomId ||
        rooms.selectedParticipation?.isRepresentative != true) {
      setState(() {
        errorMessage = '공간 선택과 주보호자 권한을 다시 확인해 주세요.';
      });
      return;
    }

    setState(() {
      isEditing = true;
      errorMessage = null;
    });

    try {
      final result = await Navigator.push<ScheduleEditResult>(
        context,
        MaterialPageRoute(
          builder: (_) => ScheduleCreate(
            familyRoomId: room.familyRoomId,
            recipientName: room.careRecipientName,
            initialSchedule: item,
          ),
        ),
      );

      if (!mounted || result == null) {
        return;
      }

      if (ref.read(firebaseAuthProvider).currentUser?.uid != loginUid ||
          ref.read(familyRoomProvider).selectedRoomId != room.familyRoomId) {
        setState(() {
          errorMessage = '로그인 상태와 선택한 공간을 다시 확인해 주세요.';
        });
        return;
      }

      // 이동 제한을 해제하고 목록 화면에 저장 결과를 전달한다.
      setState(() {
        isEditing = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop<ScheduleEditResult>(context, result);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && isEditing) {
        setState(() {
          isEditing = false;
        });
      }
    }
  }

  // 삭제 확인 후 요청하고 목록을 갱신한다.
  Future<void> deleteAction(Schedule? item) async {
    if (item == null || isBusy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFFFFFCF8),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE8DFD7)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBD9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFA65F48),
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '일정을 삭제할까요?',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF403C39),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '삭제할 일정을 확인해 주세요.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF78716A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1E5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF0DDCC)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.event_outlined,
                        size: 22,
                        color: Color(0xFF99522F),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF554B43),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              dateText(item.date),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF756B60),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${item.startTime} – ${item.endTime}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF756B60),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  item.acceptedBy == null
                      ? '현재 가족 모두에게 삭제 알림이 전달됩니다.'
                      : '담당 배정이 해제되고, 현재 가족 모두에게 '
                            '삭제 알림이 전달됩니다.',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: Color(0xFF756B60),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF756B60),
                          side: const BorderSide(color: Color(0xFFE8DFD7)),
                          minimumSize: const Size.fromHeight(52),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFA65F48),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('삭제하기'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || confirmed != true || isBusy) return;

    final rooms = ref.read(familyRoomProvider);
    if (ref.read(firebaseAuthProvider).currentUser?.uid != loginUid ||
        rooms.selectedRoomId != widget.query.familyRoomId ||
        rooms.selectedParticipation?.isRepresentative != true) {
      setState(() {
        errorMessage = '로그인 상태와 주보호자 권한을 다시 확인해 주세요.';
      });
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      isDeleting = true;
      errorMessage = null;
    });

    try {
      final published = await ref
          .read(scheduleVmProvider)
          .deleteSchedule(
            scheduleSeq: item.seq,
            familyRoomId: widget.query.familyRoomId,
          );

      if (!mounted) return;

      ref.invalidate(scheduleListProvider(widget.query));

      if (ref.read(firebaseAuthProvider).currentUser?.uid != loginUid ||
          ref.read(familyRoomProvider).selectedRoomId !=
              widget.query.familyRoomId) {
        return;
      }

      // 뒤로 가기 제한을 해제한 다음 상세창을 닫는다.
      setState(() => isDeleting = false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        Navigator.pop(context);

        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                published ? '일정을 삭제했습니다.' : '일정을 삭제했습니다. 가족 알림은 전송 대기 중입니다.',
              ),
            ),
          );
        }
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });

      // 응답이 끊겨도 서버에서는 삭제됐을 수 있어 다시 조회한다.
      ref.invalidate(scheduleListProvider(widget.query));
    } finally {
      if (mounted && isDeleting) {
        setState(() => isDeleting = false);
      }
    }
  }
}
