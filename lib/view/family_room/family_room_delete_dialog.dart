import 'package:ondolbom/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

class FamilyRoomDeleteDialog extends ConsumerStatefulWidget {
  const FamilyRoomDeleteDialog({super.key, required this.room});
  final FamilyRoom room;

  @override
  ConsumerState<FamilyRoomDeleteDialog> createState() =>
      _FamilyRoomDeleteDialogState();
}

class _FamilyRoomDeleteDialogState
    extends ConsumerState<FamilyRoomDeleteDialog> {
  final _name = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_deleting || _name.text.trim() != widget.room.careRecipientName) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref
          .read(familyRoomProvider.notifier)
          .deleteRoom(
            familyRoomId: widget.room.familyRoomId,
            recipientName: widget.room.careRecipientName,
            confirmationName: _name.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on FamilyRoomDeleteFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(familyRoomProvider);
    final allowed =
        state.selectedRoomId == widget.room.familyRoomId &&
        state.selectedRoom?.careRecipientName ==
            widget.room.careRecipientName &&
        state.selectedParticipation?.isRepresentative == true &&
        state.selectedParticipation?.isActive == true;
    final errorColor = Theme.of(context).colorScheme.error;
    return PopScope(
      canPop: !_deleting,
      child: Dialog(
        backgroundColor: AppColors.of(context).background,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppColors.of(context).border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          // 키보드가 열리거나 글씨가 커져도 입력과 확인 버튼까지 접근할 수 있게 한다.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColoredBox(
                  color: AppColors.of(context).surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.of(context).peachSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.delete_outline, color: errorColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            AppStrings.tr(context, '돌봄 공간을 삭제할까요?'),
                            style: TextStyle(
                              fontSize: 21,
                              height: 1.4,
                              fontWeight: FontWeight.w800,
                              color: AppColors.of(context).textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: AppColors.of(context).border),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).peachSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          AppStrings.tr(context, '모든 가족이 이 공간을 이용할 수 없게 됩니다.'),
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: AppColors.of(context).textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppStrings.tr(context, '삭제하려면 돌봄 대상자 이름을 입력해 주세요.'),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: AppColors.of(context).textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('family-room-delete-name'),
                        controller: _name,
                        enabled: allowed && !_deleting,
                        autocorrect: false,
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.of(context).textPrimary,
                        ),
                        decoration: InputDecoration(
                          labelText: AppStrings.tr(context, '돌봄 대상자 이름'),
                          labelStyle: TextStyle(
                            color: AppColors.of(context).textSecondary,
                          ),
                          floatingLabelStyle: TextStyle(
                            color: AppColors.of(context).sageDark,
                          ),
                          filled: true,
                          fillColor: AppColors.of(context).surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppColors.of(context).border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppColors.of(context).border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppColors.of(context).sageDark,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                      if (!allowed || _error != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            !allowed
                                ? AppStrings.tr(
                                    context,
                                    '공간 또는 권한이 변경됐어요. 화면을 다시 열어 주세요.',
                                  )
                                : AppStrings.error(context, _error!),
                            style: TextStyle(
                              color: errorColor,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _deleting
                                  ? null
                                  : () => Navigator.of(context).pop(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.of(
                                  context,
                                ).textPrimary,
                                side: BorderSide(
                                  color: AppColors.of(context).border,
                                ),
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                AppStrings.tr(context, '취소'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              key: const Key('family-room-delete-confirm'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.textPrimary,
                                disabledBackgroundColor: AppColors.of(
                                  context,
                                ).peachSoft,
                                disabledForegroundColor: AppColors.of(
                                  context,
                                ).textSecondary,
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed:
                                  allowed &&
                                      !_deleting &&
                                      !state.isLoading &&
                                      _name.text.trim() ==
                                          widget.room.careRecipientName
                                  ? _delete
                                  : null,
                              child: Text(
                                AppStrings.tr(
                                  context,
                                  _deleting ? '삭제 중…' : '공간 삭제',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
