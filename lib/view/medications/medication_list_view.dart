import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/view/medications/medication_form_view.dart';
import 'package:ondolbom/vm/family_context.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

class MedicationListView extends ConsumerStatefulWidget {
  const MedicationListView({super.key, this.initialDate});
  final DateTime? initialDate;
  @override
  ConsumerState<MedicationListView> createState() => _MedicationListViewState();
}

class _MedicationListViewState extends ConsumerState<MedicationListView> {
  late DateTime _date = DateUtils.dateOnly(
    widget.initialDate ?? DateTime.now(),
  );

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (mounted && selected != null) setState(() => _date = selected);
  }

  Future<void> _add(MedicationQuery query) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MedicationFormDialog(query: query),
    );
    if (mounted && saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('투약일지를 등록했어요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(familyContextProvider);
    final query = (context: selected, date: medicationDateKey(_date));
    final provider = medicationVmProvider(query);
    final feed = ref.watch(provider);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '투약일지',
          style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
            fontFamily: Theme.of(context).textTheme.titleLarge?.fontFamily,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonal(
              onPressed:
                  selected.familyRoomId.isEmpty || selected.userId.isEmpty
                  ? null
                  : () => _add(query),
              child: const Text('약 추가'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.home_outlined, size: 18),
                    label: Text(
                      selected.roomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    backgroundColor: colors.secondaryContainer,
                    labelStyle: TextStyle(color: colors.onSecondaryContainer),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '이전 날짜',
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
                      tooltip: '다음 날짜',
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
                      child: const Text('오늘'),
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
                            child: const Text('다시 시도'),
                          ),
                        ),
                        data: (data) {
                          final groups = <String, List<Medication>>{};
                          for (final item in data.items) {
                            (groups[item.time ?? '시간 미지정'] ??= []).add(item);
                          }
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
                              padding: const EdgeInsets.all(20),
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                if (data.items.isEmpty)
                                  const SizedBox(
                                    height: 280,
                                    child: _MedicationMessage(
                                      '이 날짜에 등록된 약이 없어요.\n약 추가로 투약일지를 작성해 보세요.',
                                    ),
                                  ),
                                for (final group in groups.entries)
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
                                                    group.key,
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
                                                    '${group.value.where((item) => item.isConfirmed).length}/${group.value.length} 완료',
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
                                              leading: Icon(
                                                item.isConfirmed
                                                    ? Icons.check_circle_outline
                                                    : Icons
                                                          .radio_button_unchecked,
                                                color: item.isConfirmed
                                                    ? colors.primary
                                                    : colors.onSurfaceVariant,
                                              ),
                                              title: Text(
                                                '${item.info ?? '약 정보 없음'} ${item.doseLabel}',
                                              ),
                                              subtitle: Text(
                                                item.isConfirmed
                                                    ? '복약 완료'
                                                    : '복약 전',
                                              ),
                                              trailing: const Icon(
                                                Icons.chevron_right,
                                              ),
                                              onTap: () => _showDetail(item),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (data.hasMore)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: Text('완료 개수는 현재 불러온 기록 기준입니다.'),
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
                                                      error is MedicationFailure
                                                          ? error.message
                                                          : '추가 조회에 실패했어요.',
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                    child: Text(
                                      data.loadingMore ? '불러오는 중…' : '더 보기',
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

  void _showDetail(Medication item) {
    final room = ref.read(familyContextProvider);
    showDialog<void>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(familyContextProvider);
          return AlertDialog(
            title: const Text('투약 정보'),
            content: SingleChildScrollView(
              child: Text(
                current != room
                    ? '선택한 공간이 변경됐어요. 다시 조회해 주세요.'
                    : '${item.info ?? '약 정보 없음'}\n\n투약 날짜: ${medicationDateKey(item.date)}\n복약 시간: ${item.time ?? '미지정'}\n용량: ${item.doseLabel}\n상태: ${item.isConfirmed ? '복약 완료' : '복약 전'}\n작성자: ${item.userId == room.userId ? '나' : item.userId}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      ),
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
