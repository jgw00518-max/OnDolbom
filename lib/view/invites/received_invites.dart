import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/widgets/menu_header_icon.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/invites/family_invite.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/invites/invite_vm.dart';

class ReceivedInvites extends ConsumerStatefulWidget {
  const ReceivedInvites({super.key});

  @override
  ConsumerState<ReceivedInvites> createState() => _ReceivedInvitesState();
}

class _ReceivedInvitesState extends ConsumerState<ReceivedInvites> {
  String? acceptingInviteId;
  String? errorMessage;
  bool showSent = false;

  static const _ink = AppColors.textPrimary;
  static const _muted = AppColors.textSecondary;
  static const _line = AppColors.border;

  void _refresh() {
    ref.invalidate(showSent ? sentInvitesProvider : receivedInvitesProvider);
  }

  Widget _tab(bool sent, int pending) {
    final selected = sent == showSent;
    return Expanded(
      child: TextButton(
        onPressed: acceptingInviteId != null
            ? null
            : () => setState(() {
                showSent = sent;
                errorMessage = null;
              }),
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? AppColors.of(context).peachLight
              : Colors.transparent,
          foregroundColor: selected
              ? AppColors.resolve(context, const Color(0xFF754E38))
              : AppColors.resolve(context, _muted),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sent ? Icons.send_outlined : Icons.mail_outline, size: 19),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                sent
                    ? AppStrings.tr(context, '보낸 초대')
                    : AppStrings.tr(context, '받은 초대'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!sent && pending > 0) ...[
              const SizedBox(width: 7),
              Container(
                width: 23,
                height: 23,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.of(context).primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  pending > 99 ? '99+' : '$pending',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final received = ref.watch(receivedInvitesProvider);
    final invites = showSent ? ref.watch(sentInvitesProvider) : received;
    final isAccepting = acceptingInviteId != null;
    final pending =
        received.asData?.value.where((i) => i.inviteStatus == '대기').length ?? 0;
    return PopScope(
      canPop: !isAccepting,
      child: Scaffold(
        backgroundColor: AppColors.of(context).background,
        appBar: AppBar(
          backgroundColor: AppColors.of(context).background,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.resolve(context, _ink),
          toolbarHeight: 88,
          automaticallyImplyLeading: false,
          leadingWidth: 68,
          leading: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Center(
              child: SizedBox.square(
                dimension: 42,
                child: OutlinedButton(
                  onPressed: isAccepting ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: AppColors.of(context).surface,
                    foregroundColor: AppColors.resolve(context, _ink),
                    side: BorderSide(color: AppColors.resolve(context, _line)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Icon(
                    Icons.chevron_left,
                    semanticLabel: AppStrings.tr(context, '뒤로'),
                  ),
                ),
              ),
            ),
          ),
          centerTitle: true,
          title: Column(
            children: [
              Text(
                'FAMILY INVITATION',
                style: TextStyle(
                  color: AppColors.resolve(context, Color(0xFFA77762)),
                  fontSize: 8,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 3),
              Text(
                AppStrings.tr(context, '가족 초대'),
                style: TextStyle(
                  color: AppColors.resolve(context, _ink),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          actions: const [MenuHeaderIcon(icon: Icons.mail_outline)],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 15, 20, 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).surface,
                    border: Border.all(
                      color: AppColors.resolve(context, _line),
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      _tab(false, pending),
                      const SizedBox(width: 4),
                      _tab(true, pending),
                    ],
                  ),
                ),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      AppStrings.error(context, errorMessage!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: invites.when(
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        color: AppColors.of(context).primary,
                      ),
                    ),
                    error: (error, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppStrings.error(
                                context,
                                error.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: isAccepting ? null : _refresh,
                              child: Text(AppStrings.tr(context, '다시 조회')),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (items) => ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    showSent
                                        ? AppStrings.tr(context, '내가 보낸 초대')
                                        : AppStrings.tr(context, '나에게 도착한 초대'),
                                    style: TextStyle(
                                      color: AppColors.resolve(context, _muted),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    AppStrings.format(
                                      context,
                                      "{0}개의 초대가 있어요",
                                      [items.length],
                                    ),
                                    style: TextStyle(
                                      color: AppColors.resolve(context, _ink),
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.of(context).peachSoft,
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: Text(
                                showSent
                                    ? AppStrings.tr(context, '보낸 초대')
                                    : AppStrings.tr(context, '받은 초대'),
                                style: TextStyle(
                                  color: AppColors.resolve(
                                    context,
                                    Color(0xFFA46F59),
                                  ),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Text(
                              showSent
                                  ? AppStrings.tr(
                                      context,
                                      '주보호자로 관리하는 공간에 보낸 초대가 없습니다.',
                                    )
                                  : AppStrings.tr(context, '받은 가족 초대가 없습니다.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.resolve(context, _muted),
                              ),
                            ),
                          ),
                        for (final invite in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: inviteCard(invite),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 19,
          color: AppColors.resolve(context, const Color(0xFFB1765C)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.tr(context, label),
                style: TextStyle(
                  color: AppColors.resolve(context, _muted),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  color: AppColors.resolve(context, Color(0xFF746A64)),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget inviteCard(FamilyInvite invite) {
    final status = invite.inviteStatus;
    final expired = status == '만료';
    final busy = acceptingInviteId != null;
    final processing = acceptingInviteId == invite.inviteId;
    final date = invite.inviteAt;
    final dateText =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final dateLabel = status == '발송대기' || status == '발송실패'
        ? '초대 생성 시각'
        : '보낸 시각';
    final statusColor = switch (status) {
      '수락' => AppColors.resolve(context, const Color(0xFFE5EEDC)),
      '대기' => AppColors.of(context).peachSoft,
      _ => AppColors.resolve(context, const Color(0xFFF0ECE9)),
    };
    final secondaryStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.resolve(context, const Color(0xFF8F6B59)),
      backgroundColor: AppColors.of(context).surface,
      side: BorderSide(color: AppColors.resolve(context, _line)),
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: expired && !showSent
            ? AppColors.of(context).peachSoft
            : AppColors.of(context).surface,
        border: Border.all(color: AppColors.resolve(context, _line)),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.resolve(
              context,
              const Color(0xFF594135),
            ).withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  AppStrings.tr(context, status),
                  style: TextStyle(
                    color: status == '수락'
                        ? AppColors.of(context).sageDark
                        : AppColors.resolve(context, const Color(0xFFA46F59)),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dateText,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppColors.resolve(context, _muted),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            AppStrings.format(context, "{0} 님의 돌봄 공간", [invite.recipientName]),
            style: TextStyle(
              color: AppColors.resolve(context, _ink),
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          _detail(
            Icons.mail_outline,
            AppStrings.tr(context, '초대받는 이메일'),
            invite.inviteEmail,
          ),
          _detail(
            Icons.person_outline,
            AppStrings.tr(context, '초대를 보낸 사람'),
            invite.inviterName ?? AppStrings.tr(context, '가족'),
          ),
          _detail(Icons.schedule, dateLabel, dateText),
          if (invite.expiresAt != null)
            _detail(
              Icons.event_busy_outlined,
              AppStrings.tr(context, '유효기간'),
              AppStrings.format(context, "{0}-{1}-{2} {3}:{4}까지 (7일)", [
                invite.expiresAt!.year,
                invite.expiresAt!.month.toString().padLeft(2, '0'),
                invite.expiresAt!.day.toString().padLeft(2, '0'),
                invite.expiresAt!.hour.toString().padLeft(2, '0'),
                invite.expiresAt!.minute.toString().padLeft(2, '0'),
              ]),
            ),
          // 받은 만료 초대에는 처리 버튼을 두지 않고, 발신자에게만 재요청을 제공한다.
          if (expired && showSent && invite.canResend) ...[
            Divider(color: AppColors.resolve(context, _line), height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : () => resendAction(invite),
                icon: const Icon(Icons.forward_to_inbox_outlined, size: 19),
                label: Text(
                  processing
                      ? AppStrings.tr(context, '발송 중…')
                      : AppStrings.tr(context, '재요청'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.resolve(
                    context,
                    AppColors.primary,
                    onAccent: true,
                  ),
                  foregroundColor: AppColors.resolve(
                    context,
                    _ink,
                    onAccent: true,
                  ),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
          if (expired && !showSent) ...[
            const SizedBox(height: 18),
            Text(
              AppStrings.tr(
                context,
                '초대 유효기간이 지났어요.\n참여하려면 주보호자에게 새 초대를 요청해 주세요.',
              ),
              style: TextStyle(
                color: AppColors.resolve(context, _muted),
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ],
          if (status == '대기' && (!showSent || invite.canCancel)) ...[
            if (!showSent) ...[
              const SizedBox(height: 16),
              Text(
                AppStrings.tr(context, '수락하면 이 공간의 일반 가족으로 참여합니다.'),
                style: TextStyle(
                  color: AppColors.resolve(context, _muted),
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ],
            Divider(
              color: AppColors.resolve(context, Color(0xFFF2E8E2)),
              height: 32,
            ),
            if (showSent)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy ? null : () => cancelAction(invite),
                  style: secondaryStyle.copyWith(
                    backgroundColor: WidgetStatePropertyAll(
                      AppColors.resolve(context, Color(0xFFFFF9F5)),
                    ),
                  ),
                  child: Text(
                    processing
                        ? AppStrings.tr(context, '처리 중…')
                        : AppStrings.tr(context, '초대 취소'),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => rejectAction(invite),
                      style: secondaryStyle,
                      child: Text(AppStrings.tr(context, '거절')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: busy ? null : () => acceptAction(invite),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.resolve(
                          context,
                          AppColors.primary,
                          onAccent: true,
                        ),
                        foregroundColor: AppColors.resolve(
                          context,
                          _ink,
                          onAccent: true,
                        ),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: Text(
                        processing
                            ? AppStrings.tr(context, '처리 중…')
                            : AppStrings.tr(context, '초대 수락'),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  // 발송 중 다른 초대 작업을 막고, 새 초대와 만료 이력을 다시 조회한다.
  Future<void> resendAction(FamilyInvite invite) async {
    if (acceptingInviteId != null) return;
    setState(() {
      acceptingInviteId = invite.inviteId;
      errorMessage = null;
    });
    try {
      final sent = await ref
          .read(inviteVmProvider)
          .resendInvite(invite.inviteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.error(
              context,
              sent
                  ? AppStrings.tr(
                      context,
                      '새 초대장을 이메일로 보냈습니다. 발송 후 7일 동안 유효합니다.',
                    )
                  : AppStrings.tr(
                      context,
                      '새 초대는 생성했지만 이메일 발송에 실패했습니다. 메일 설정을 확인해 주세요.',
                    ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => errorMessage = error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => acceptingInviteId = null);
        ref.invalidate(sentInvitesProvider);
        ref.invalidate(receivedInvitesProvider);
      }
    }
  }

  // 초대를 수락하고 이전 화면에 성공 여부를 전달한다.
  Future<void> acceptAction(FamilyInvite invite) async {
    if (acceptingInviteId != null) {
      return;
    }

    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;

    setState(() {
      acceptingInviteId = invite.inviteId;
      errorMessage = null;
    });

    try {
      await ref.read(inviteVmProvider).acceptInvite(invite.inviteId);

      if (!mounted) {
        return;
      }

      if (ref.read(firebaseAuthProvider).currentUser?.uid != uid) {
        setState(() {
          acceptingInviteId = null;
          errorMessage = '로그인 상태가 변경되었습니다.';
        });
        return;
      }

      ref.invalidate(receivedInvitesProvider);

      // 뒤로 이동 제한을 해제한 다음 목록으로 돌아간다.
      setState(() {
        acceptingInviteId = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context, true);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        acceptingInviteId = null;
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });

      // 이미 처리된 초대라면 최신 목록으로 갱신한다.
      ref.invalidate(receivedInvitesProvider);
    }
  }

  // 초대를 거절하고 받은 초대 목록을 갱신한다.
  Future<void> rejectAction(FamilyInvite invite) async {
    // 수락 또는 거절 처리 중에는 다른 요청을 막는다.
    if (acceptingInviteId != null) {
      return;
    }

    setState(() {
      acceptingInviteId = invite.inviteId;
      errorMessage = null;
    });

    try {
      await ref.read(inviteVmProvider).rejectInvite(invite.inviteId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.tr(context, '초대를 거절했습니다.'))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          acceptingInviteId = null;
        });

        // 거절 성공 또는 상태 변경 여부를 최신 목록에서 확인한다.
        ref.invalidate(receivedInvitesProvider);
      }
    }
  } // build

  // 확인창에서 동의하면 보낸 초대를 취소한다.
  Future<void> cancelAction(FamilyInvite invite) async {
    if (acceptingInviteId != null) {
      return;
    }

    // 확인창이 열린 동안에도 다른 처리를 막는다.
    setState(() {
      acceptingInviteId = invite.inviteId;
      errorMessage = null;
    });

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: AppColors.resolve(
              context,
              const Color(0xFFFFFCF8),
            ),
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: AppColors.resolve(context, Color(0xFFE8DFD7)),
              ),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            scrollable: true,
            title: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.resolve(context, Color(0xFFFFEBD9)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mail_outline_rounded,
                    size: 30,
                    color: AppColors.resolve(context, Color(0xFF99522F)),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  AppStrings.tr(context, '초대를 취소할까요?'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.resolve(context, Color(0xFF403C39)),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.resolve(
                        context,
                        const Color(0xFFFFF3E8),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(
                          AppStrings.tr(context, '초대받은 이메일'),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.resolve(
                              context,
                              Color(0xFF8B796B),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          invite.inviteEmail,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.resolve(
                              context,
                              Color(0xFF553724),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    AppStrings.tr(context, '취소하면 이 초대로는\n돌봄 공간에 참여할 수 없어요.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.7,
                      color: AppColors.resolve(context, Color(0xFF78716A)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.resolve(
                          context,
                          const Color(0xFF756B60),
                        ),
                        side: BorderSide(
                          color: AppColors.resolve(context, Color(0xFFE8DFD7)),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(AppStrings.tr(context, '돌아가기')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.resolve(
                          context,
                          const Color(0xFFF7AC82),
                          onAccent: true,
                        ),
                        foregroundColor: AppColors.resolve(
                          context,
                          const Color(0xFF553724),
                          onAccent: true,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        AppStrings.tr(context, '초대 취소'),
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );

      if (!mounted || confirmed != true) {
        return;
      }

      await ref.read(inviteVmProvider).cancelInvite(invite.inviteId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.tr(context, '초대를 취소했습니다.'))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          acceptingInviteId = null;
        });

        ref.invalidate(sentInvitesProvider);
      }
    }
  }
} // class
