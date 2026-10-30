import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

// import 'package:ondolbom/model/family/family_room.dart';
// import 'package:ondolbom/view/family_room/recipient_edit.dart';

class RecipientEdit extends ConsumerStatefulWidget {
  const RecipientEdit({super.key, required this.room});

  final FamilyRoom room;

  @override
  ConsumerState<RecipientEdit> createState() => _RecipientEditState();
}

class _RecipientEditState extends ConsumerState<RecipientEdit> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController nameController;
  late final TextEditingController birthController;
  late final TextEditingController addressController;
  late final TextEditingController notesController;

  int? selectedGender;

  bool isSaving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();

    final room = widget.room;
    final birth = room.birthDate;
    selectedGender = room.gender == 1 || room.gender == 2 ? room.gender : null;

    nameController = TextEditingController(text: room.careRecipientName);
    birthController = TextEditingController(
      text: birth == null ? '' : formatDate(birth),
    );
    addressController = TextEditingController(text: room.careAddress ?? '');
    notesController = TextEditingController(text: room.specialNotes ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    birthController.dispose();
    addressController.dispose();
    notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(familyRoomProvider);

    final canEdit =
        state.selectedRoomId == widget.room.familyRoomId &&
        state.selectedParticipation?.isRepresentative == true;

    return PopScope(
      canPop: !isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppStrings.tr(context, '대상자 정보 편집')),
          leadingWidth: 62,
          leading: AppBackLeading(enabled: !isSaving),
        ),
        body: !canEdit
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    AppStrings.tr(context, '현재 공간의 주보호자만 수정할 수 있습니다.'),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Form(
                key: formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      AppStrings.tr(context, '돌봄에 필요한 정보를\n가족에게 알려주세요.'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.5,
                        color: AppColors.resolve(context, Color(0xFF403C39)),
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: nameController,
                      enabled: !isSaving,
                      maxLength: 30,
                      decoration: InputDecoration(
                        labelText: AppStrings.tr(context, '대상자 이름'),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return AppStrings.tr(context, '대상자 이름을 입력해 주세요.');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      AppStrings.tr(context, '성별'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.resolve(context, Color(0xFF403C39)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment<int>(
                            value: 1,
                            label: Text(AppStrings.tr(context, '남성')),
                          ),
                          ButtonSegment<int>(
                            value: 2,
                            label: Text(AppStrings.tr(context, '여성')),
                          ),
                        ],
                        selected: selectedGender == null
                            ? <int>{}
                            : {selectedGender!},
                        emptySelectionAllowed: selectedGender == null,
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color>(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? AppColors.resolve(
                                        context,
                                        const Color(0xFFFFEBD9),
                                      )
                                    : AppColors.resolve(context, Colors.white),
                              ),
                          foregroundColor:
                              WidgetStateProperty.resolveWith<Color>(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? AppColors.resolve(
                                        context,
                                        const Color(0xFF99522F),
                                      )
                                    : AppColors.resolve(
                                        context,
                                        const Color(0xFF78716A),
                                      ),
                              ),
                          side: WidgetStatePropertyAll(
                            BorderSide(
                              color: AppColors.resolve(
                                context,
                                Color(0xFFE8DFD7),
                              ),
                            ),
                          ),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        onSelectionChanged: isSaving
                            ? null
                            : (selection) {
                                setState(() {
                                  selectedGender = selection.first;
                                });
                              },
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: birthController,
                      enabled: !isSaving,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: AppStrings.tr(context, '생년월일'),
                        hintText: AppStrings.tr(context, '예: 1950-03-15'),
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      validator: validateBirthDate,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: addressController,
                      enabled: !isSaving,
                      maxLength: 255,
                      decoration: InputDecoration(
                        labelText: AppStrings.tr(context, '돌봄 장소'),
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: notesController,
                      enabled: !isSaving,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: AppStrings.tr(context, '특이사항'),
                        alignLabelWithHint: true,
                        hintText: AppStrings.tr(
                          context,
                          '가족들이 알아야 할 내용을 적어주세요.',
                        ),
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        AppStrings.error(context, errorMessage!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),
                    FilledButton(
                      onPressed: isSaving ? null : saveAction,
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
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        isSaving
                            ? AppStrings.tr(context, '저장 중…')
                            : AppStrings.tr(context, '변경 내용 저장'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // 날짜를 서버에 전달할 형식으로 표시한다.
  String formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  // 빈 값은 허용하고, 입력한 경우 실제 존재하는 날짜인지 검사한다.
  String? validateBirthDate(String? value) {
    final text = (value ?? '').trim();

    if (text.isEmpty) {
      return null;
    }

    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      return '생년월일을 YYYY-MM-DD 형식으로 입력해 주세요.';
    }

    final date = DateTime.tryParse(text);

    if (date == null || date.year < 1 || formatDate(date) != text) {
      return '실제로 존재하는 날짜를 입력해 주세요.';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (date.isAfter(today)) {
      return '생년월일은 미래 날짜로 입력할 수 없습니다.';
    }

    return null;
  }

  // 입력값을 확인하고 서버에 저장한다.
  Future<void> saveAction() async {
    if (isSaving || !formKey.currentState!.validate()) {
      return;
    }

    final gender = selectedGender;

    if (gender == null) {
      setState(() {
        errorMessage = '성별을 선택해 주세요.';
      });
      return;
    }

    final state = ref.read(familyRoomProvider);

    if (state.selectedRoomId != widget.room.familyRoomId ||
        state.selectedParticipation?.isRepresentative != true) {
      setState(() {
        errorMessage = '공간 선택과 주보호자 권한을 다시 확인해 주세요.';
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorMessage = null;
    });

    try {
      final birthText = birthController.text.trim();

      await ref
          .read(familyRoomProvider.notifier)
          .updateRecipient(
            familyRoomId: widget.room.familyRoomId,
            name: nameController.text,
            gender: gender,
            birthDate: birthText.isEmpty ? null : birthText,
            address: addressController.text,
            notes: notesController.text,
          );

      if (!mounted) {
        return;
      }

      // 뒤로 이동 제한을 해제한 다음 저장 성공을 전달한다.
      setState(() {
        isSaving = false;
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
        isSaving = false;
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}
