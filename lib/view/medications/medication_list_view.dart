import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/widgets/discard_changes_dialog.dart';
import 'package:ondolbom/view/widgets/app_date_picker.dart';
import 'package:ondolbom/view/widgets/menu_header_icon.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/medications/medication_style.dart';
import 'package:ondolbom/view/widgets/app_add_button.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/view/medications/medication_form_view.dart';
import 'package:ondolbom/view/medications/medication_edit_view.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

class MedicationListView extends ConsumerStatefulWidget {
  const MedicationListView({super.key, this.initialDate});
  final DateTime? initialDate;
  @override
  ConsumerState<MedicationListView> createState() => _MedicationListViewState();
}

class _MedicationListViewState extends ConsumerState<MedicationListView> {
  final _unconfirmDialogs = <int>{};
  final _deleting = <int>{};
  late DateTime _date = DateUtils.dateOnly(
    widget.initialDate ?? DateTime.now(),
  );

  Future<void> _pickDate() async {
    final selected = await showAppDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (mounted && selected != null) setState(() => _date = selected);
  }

  Future<void> _add(MedicationQuery query) async {
    if (ref.read(familyContextProvider) != query.context ||
        !ref.read(medicationCreateAllowedProvider(query.context))) {
      return;
    }
    // 약 추가는 별도 화면에서 작성하고 저장 완료 후 목록에 결과를 돌려준다.
    final saved = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(builder: (_) => MedicationFormView(query: query)),
    );
    if (mounted && saved != null) {
      // 시작일을 바꿔 등록했다면 목록도 저장한 날짜로 이동해 결과를 바로 확인한다.
      setState(() => _date = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.tr(context, '투약일지를 등록했어요.'))),
      );
    }
  }

  Future<void> _deletePeriod(MedicationQuery query, Medication item) async {
    if (!_deleting.add(item.seq)) return;
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppStrings.tr(context, '남은 복용 기간을 삭제할까요?')),
          content: Text(
            AppStrings.format(
              context,
              "{0}의 같은 등록 묶음에서 오늘과 이후 날짜의 항목을 삭제해요.\n오늘 체크한 항목도 삭제되며, 어제까지의 기록은 유지돼요.",
              [item.info ?? AppStrings.tr(context, '이 약')],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppStrings.tr(context, '취소')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppStrings.tr(context, '삭제')),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final count = await ref
          .read(medicationVmProvider(query).notifier)
          .deletePeriod(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.error(
                context,
                count == 0
                    ? AppStrings.tr(context, '오늘 이후에 삭제할 항목이 없어요.')
                    : AppStrings.format(context, "오늘 이후의 투약 항목 {0}개를 삭제했어요.", [
                        count,
                      ]),
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.error(
                context,
                error is MedicationFailure
                    ? error.message
                    : AppStrings.tr(context, '약을 삭제하지 못했어요. 다시 시도해 주세요.'),
              ),
            ),
          ),
        );
      }
    } finally {
      _deleting.remove(item.seq);
    }
  }

  Future<void> _confirm(MedicationQuery query, Medication item) async {
    try {
      await ref
          .read(medicationVmProvider(query).notifier)
          .confirmMedication(item);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.error(
              context,
              error is MedicationFailure
                  ? error.message
                  : AppStrings.tr(context, '체크하지 못했어요. 다시 시도해 주세요.'),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _unconfirm(MedicationQuery query, Medication item) async {
    if (!_unconfirmDialogs.add(item.seq)) return;
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => DiscardChangesDialog(
          title: AppStrings.tr(context, '복약 완료 체크 해제'),
          message: AppStrings.tr(
            context,
            '체크를 해제하면 미완료로 표시됩니다.\n체크를 해제하시겠습니까?',
          ),
          continueLabel: '취소',
          discardLabel: '해제',
        ),
      );
      if (!mounted || approved != true) return;
      await ref
          .read(medicationVmProvider(query).notifier)
          .unconfirmMedication(item);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.error(
              context,
              error is MedicationFailure
                  ? error.message
                  : AppStrings.tr(context, '체크를 해제하지 못했어요. 다시 시도해 주세요.'),
            ),
          ),
        ),
      );
    } finally {
      _unconfirmDialogs.remove(item.seq);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(familyContextProvider);
    final query = (context: selected, date: medicationDateKey(_date));
    final provider = medicationVmProvider(query);
    final feed = ref.watch(provider);
    final colors = Theme.of(context).colorScheme;
    final canCreate = ref.watch(medicationCreateAllowedProvider(selected));
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 62,
        leading: const AppBackLeading(),
        title: Text(
          AppStrings.tr(context, '투약일지'),
          style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
            fontFamily: Theme.of(context).textTheme.titleLarge?.fontFamily,
          ),
        ),
        actions: const [MenuHeaderIcon(icon: Icons.medication_outlined)],
      ),
      floatingActionButton: canCreate
          ? AppAddButton(
              tooltip: AppStrings.tr(context, '약 추가'),
              onPressed:
                  selected.familyRoomId.isEmpty || selected.userId.isEmpty
                  ? null
                  : () => _add(query),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: AppStrings.tr(context, '이전 날짜'),
                      onPressed: _date.isAfter(DateTime(1900))
                          ? () => setState(
                              () => _date = DateTime(
                                _date.year,
                                _date.month,
                                _date.day - 1,
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                        ),
                        label: Text(medicationDateKey(_date)),
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.tr(context, '다음 날짜'),
                      onPressed: _date.isBefore(DateTime(2100, 12, 31))
                          ? () => setState(
                              () => _date = DateTime(
                                _date.year,
                                _date.month,
                                _date.day + 1,
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    TextButton(
                      onPressed: () => setState(
                        () => _date = DateUtils.dateOnly(DateTime.now()),
                      ),
                      child: Text(AppStrings.tr(context, '오늘')),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: selected.familyRoomId.isEmpty
                    ? const _MedicationMessage('돌봄 공간을 먼저 선택해 주세요.')
                    : feed.when(
                        skipLoadingOnRefresh: false,
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => _MedicationMessage(
                          error is MedicationFailure
                              ? error.message
                              : '투약일지를 불러오지 못했어요.',
                          action: OutlinedButton(
                            onPressed: () => ref.invalidate(provider),
                            child: Text(AppStrings.tr(context, '다시 시도')),
                          ),
                        ),
                        data: (data) {
                          final groups = <String, List<Medication>>{};
                          for (final item in data.items) {
                            (groups[item.time ?? '시간 미지정'] ??= []).add(item);
                          }
                          int mealOrder(String time) {
                            final value = time.trim();
                            if (value.startsWith('아침')) return 0;
                            if (value.startsWith('점심')) return 1;
                            if (value.startsWith('저녁')) return 2;
                            return 3;
                          }

                          int timingOrder(String time) {
                            if (time.contains('식전')) return 0;
                            if (time.contains('식후')) return 1;
                            return 2;
                          }

                          final orderedGroups = [
                            for (var order = 0; order < 4; order++)
                              for (var timing = 0; timing < 3; timing++)
                                ...groups.entries.where(
                                  (group) =>
                                      mealOrder(group.key) == order &&
                                      timingOrder(group.key) == timing,
                                ),
                          ];
                          return RefreshIndicator(
                            onRefresh: () async {
                              ref.invalidate(provider);
                              try {
                                await ref.read(provider.future);
                              } catch (_) {
                                /* 오류 화면에서 재시도 */
                              }
                            },
                            child: ListView(
                              // 마지막 항목을 추가 버튼 위까지 스크롤할 수 있도록 여백을 둔다.
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                20,
                                20,
                                104,
                              ),
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                if (data.items.isEmpty)
                                  const SizedBox(
                                    height: 280,
                                    child: _MedicationMessage(
                                      '이 날짜에 등록된 약이 없어요.\n약 추가로 투약일지를 작성해 보세요.',
                                    ),
                                  ),
                                for (final group in orderedGroups)
                                  Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    AppStrings.tr(
                                                      context,
                                                      group.key,
                                                    ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: colors
                                                        .secondaryContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    AppStrings.format(
                                                      context,
                                                      "{0}/{1} 완료",
                                                      [
                                                        group.value
                                                            .where(
                                                              (item) => item
                                                                  .isConfirmed,
                                                            )
                                                            .length,
                                                        group.value.length,
                                                      ],
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: colors
                                                          .onSecondaryContainer,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          for (final item in group.value)
                                            ListTile(
                                              leading: IconButton(
                                                tooltip: item.isConfirmed
                                                    ? (canCreate ||
                                                              item.confirmedByUserId ==
                                                                  selected
                                                                      .userId
                                                          ? AppStrings.tr(
                                                              context,
                                                              '복약 완료 체크 해제',
                                                            )
                                                          : AppStrings.tr(
                                                              context,
                                                              '복약 완료',
                                                            ))
                                                    : AppStrings.tr(
                                                        context,
                                                        '복약 완료 체크',
                                                      ),
                                                onPressed:
                                                    (item.isConfirmed &&
                                                            !canCreate &&
                                                            item.confirmedByUserId !=
                                                                selected
                                                                    .userId) ||
                                                        data.confirming
                                                            .contains(
                                                              item.seq,
                                                            ) ||
                                                        selected.userId.isEmpty
                                                    ? null
                                                    : () => item.isConfirmed
                                                          ? _unconfirm(
                                                              query,
                                                              item,
                                                            )
                                                          : _confirm(
                                                              query,
                                                              item,
                                                            ),
                                                icon:
                                                    data.confirming.contains(
                                                      item.seq,
                                                    )
                                                    ? const SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      )
                                                    : Icon(
                                                        item.isConfirmed
                                                            ? Icons
                                                                  .check_circle_outline
                                                            : Icons
                                                                  .radio_button_unchecked,
                                                        color: item.isConfirmed
                                                            ? colors.primary
                                                            : colors
                                                                  .onSurfaceVariant,
                                                      ),
                                              ),
                                              title: Text(
                                                '${item.info ?? AppStrings.tr(context, '약 정보 없음')} ${item.doseLabel}',
                                              ),
                                              subtitle: item.isConfirmed
                                                  ? Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          AppStrings.tr(
                                                            context,
                                                            '복약 완료',
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 10,
                                                                vertical: 5,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                AppColors.resolve(
                                                                  context,
                                                                  AppColors
                                                                      .sageLight,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  20,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            AppStrings.format(
                                                              context,
                                                              "체크: {0}",
                                                              [
                                                                item.confirmedByLabel,
                                                              ],
                                                            ),
                                                            style: TextStyle(
                                                              color:
                                                                  AppColors.resolve(
                                                                    context,
                                                                    AppColors
                                                                        .sageDark,
                                                                  ),
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          medicationConfirmationLabel(
                                                            item,
                                                          ).split('\n').last,
                                                        ),
                                                      ],
                                                    )
                                                  : Text(
                                                      AppStrings.tr(
                                                        context,
                                                        '복약 전',
                                                      ),
                                                    ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (canCreate)
                                                    IconButton(
                                                      tooltip: AppStrings.tr(
                                                        context,
                                                        '약 삭제',
                                                      ),
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                      ),
                                                      onPressed: () =>
                                                          _deletePeriod(
                                                            query,
                                                            item,
                                                          ),
                                                    ),
                                                  const Icon(
                                                    Icons.chevron_right,
                                                  ),
                                                ],
                                              ),
                                              onTap: () => _showDetail(item),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (data.hasMore)
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      AppStrings.tr(
                                        context,
                                        '완료 개수는 현재 불러온 기록 기준입니다.',
                                      ),
                                    ),
                                  ),
                                if (data.hasMore)
                                  OutlinedButton(
                                    onPressed: data.loadingMore
                                        ? null
                                        : () async {
                                            try {
                                              await ref
                                                  .read(provider.notifier)
                                                  .loadMore();
                                            } catch (error) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      AppStrings.error(
                                                        context,
                                                        error
                                                                is MedicationFailure
                                                            ? error.message
                                                            : AppStrings.tr(
                                                                context,
                                                                '추가 조회에 실패했어요.',
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                    child: Text(
                                      data.loadingMore
                                          ? AppStrings.tr(context, '불러오는 중…')
                                          : AppStrings.tr(context, '더 보기'),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(Medication item) async {
    final room = ref.read(familyContextProvider);
    final query = (context: room, date: medicationDateKey(_date));
    final edit = await showDialog<bool>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(familyContextProvider);
          final canEdit =
              current == room && ref.watch(medicationEditAllowedProvider(room));
          final feed = ref.watch(medicationVmProvider(query)).asData?.value;
          final record =
              feed?.items
                  .where((record) => record.seq == item.seq)
                  .firstOrNull ??
              item;
          final confirming = feed?.confirming.contains(item.seq) ?? false;
          final canConfirm =
              current == room &&
              room.userId.isNotEmpty &&
              feed != null &&
              !record.isConfirmed &&
              !confirming;
          final canUnconfirm =
              current == room &&
              room.userId.isNotEmpty &&
              feed != null &&
              record.isConfirmed &&
              (canEdit || record.confirmedByUserId == room.userId);
          return AlertDialog(
            backgroundColor: AppColors.of(context).background,
            surfaceTintColor: Colors.transparent,
            shape: MedicationStyle.shape(context),
            clipBehavior: Clip.antiAlias,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            titlePadding: EdgeInsets.zero,
            contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: MedicationHeading(
              title: AppStrings.tr(context, '투약 정보'),
              onClose: () => Navigator.pop(context),
            ),
            content: SingleChildScrollView(
              child: current != room
                  ? Text(AppStrings.tr(context, '선택한 공간이 변경됐어요. 다시 조회해 주세요.'))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.of(context).surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.of(context).border,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.info ??
                                    AppStrings.tr(context, '약 정보 없음'),
                                style: TextStyle(
                                  fontSize: 19,
                                  height: 1.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.of(context).textPrimary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: record.isConfirmed
                                      ? AppColors.of(context).sageLight
                                      : AppColors.of(context).peachSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  AppStrings.format(context, "상태: {0}", [
                                    record.isConfirmed ? '복약 완료' : '복약 전',
                                  ]),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.of(context).textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        MedicationInfoRow(
                          icon: Icons.calendar_today_outlined,
                          text: '투약 날짜: ${medicationDateKey(record.date)}',
                        ),
                        MedicationInfoRow(
                          icon: Icons.schedule_outlined,
                          text: '복약 시간: ${record.time ?? '미지정'}',
                        ),
                        MedicationInfoRow(
                          icon: Icons.medication_outlined,
                          text: '용량: ${record.doseLabel}',
                        ),
                        const Divider(height: 20),
                        MedicationInfoRow(
                          icon: Icons.person_outline,
                          text: '작성자: ${record.authorLabel}',
                        ),
                        if (record.isConfirmed)
                          MedicationInfoRow(
                            icon: Icons.check_circle_outline,
                            text: medicationConfirmationLabel(record),
                          ),
                      ],
                    ),
            ),
            actions: [
              if (canUnconfirm)
                TextButton(
                  onPressed: confirming
                      ? null
                      : () => _unconfirm(query, record),
                  child: Text(
                    confirming
                        ? AppStrings.tr(context, '해제 중…')
                        : AppStrings.tr(context, '체크 해제'),
                  ),
                ),
              if (!record.isConfirmed)
                TextButton(
                  onPressed: canConfirm ? () => _confirm(query, record) : null,
                  child: Text(
                    confirming
                        ? AppStrings.tr(context, '체크 중…')
                        : AppStrings.tr(context, '복약 완료 체크'),
                  ),
                ),
              if (canEdit)
                TextButton(
                  onPressed: confirming
                      ? null
                      : () => Navigator.pop(context, true),
                  child: Text(AppStrings.tr(context, '수정')),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.tr(context, '닫기')),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || edit != true || ref.read(familyContextProvider) != room) {
      return;
    }
    final savedDate = await showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MedicationEditDialog(query: query, item: item),
    );
    if (!mounted ||
        savedDate == null ||
        ref.read(familyContextProvider) != room) {
      return;
    }
    setState(() => _date = DateUtils.dateOnly(savedDate));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.tr(context, '투약 정보를 수정했어요.'))),
    );
  }
}

class _MedicationMessage extends StatelessWidget {
  const _MedicationMessage(this.message, {this.action});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.medication_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 40,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: action),
        ],
      ),
    ),
  );
}
