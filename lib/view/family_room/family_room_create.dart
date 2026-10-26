import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

class FamilyRoomCreate extends ConsumerStatefulWidget {
  const FamilyRoomCreate({super.key});

  @override
  ConsumerState<FamilyRoomCreate> createState() =>
      _FamilyRoomCreateState();
}

class _FamilyRoomCreateState
    extends ConsumerState<FamilyRoomCreate> {
  late TextEditingController nameController;
  late TextEditingController birthController;
  late TextEditingController addressController;
  late TextEditingController notesController;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController();
    birthController = TextEditingController();
    addressController = TextEditingController();
    notesController = TextEditingController();
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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Text('온돌봄'),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: state.isLoading
                  ? null
                  : () => Navigator.pop(context),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('나의 홈'),
                  SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          // 페이지 제목
          Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: state.isLoading
                      ? null
                      : () => Navigator.pop(context),
                  child: const Icon(Icons.chevron_left),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '가족 공간 만들기',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 20),

          inputTitle('돌봄대상자 이름'),
          TextField(
            controller: nameController,
            enabled: !state.isLoading,
            maxLength: 30,
            decoration: inputDecoration(context).copyWith(
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),

          inputTitle('생년월일'),
          TextField(
            controller: birthController,
            enabled: !state.isLoading,
            readOnly: true,
            onTap: () => birthAction(),
            decoration: inputDecoration(context).copyWith(
              hintText: '년-월-일',
              suffixIcon: const Icon(
                Icons.calendar_month_outlined,
              ),
            ),
          ),
          const SizedBox(height: 24),

          inputTitle('돌봄 장소'),
          TextField(
            controller: addressController,
            enabled: !state.isLoading,
            maxLength: 255,
            decoration: inputDecoration(context).copyWith(
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),

          inputTitle('특이사항'),
          TextField(
            controller: notesController,
            enabled: !state.isLoading,
            maxLines: 4,
            decoration: inputDecoration(context),
          ),
        ],
      ),

      // 입력 내용을 스크롤해도 버튼은 아래에 유지한다.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.onSurface,
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: state.isLoading
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text(
                      '취소',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          colors.secondaryContainer,
                      foregroundColor:
                          colors.onSecondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: state.isLoading
                        ? null
                        : () => createAction(),
                    child: Text(
                      state.isLoading ? '생성 중...' : '공간 만들기',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } // build
   // build

  // ----- function -----

  // 달력에서 생년월일을 선택한다.
  Future<void> birthAction() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate:
          DateTime.tryParse(birthController.text) ??
          DateTime(1950),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (!mounted || selectedDate == null) {
      return;
    }

    birthController.text =
        '${selectedDate.year}-'
        '${selectedDate.month.toString().padLeft(2, '0')}-'
        '${selectedDate.day.toString().padLeft(2, '0')}';
  }

  // 입력값을 확인하고 ViewModel에 생성을 요청한다.
  Future<void> createAction() async {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('돌봄대상자 이름을 입력해 주세요.'),
        ),
      );
      return;
    }

    final birth = birthController.text.trim();
    final address = addressController.text.trim();
    final notes = notesController.text.trim();

    final success = await ref
        .read(familyRoomProvider.notifier)
        .createRoom(
          name: name,
          birthDate: birth.isEmpty ? null : birth,
          address: address.isEmpty ? null : address,
          notes: notes.isEmpty ? null : notes,
        );

    if (!mounted) {
      return;
    }

    if (success) {
      Navigator.pop(context, true);
    } else {
      final message =
          ref.read(familyRoomProvider).errorMessage ??
          '공간을 생성하지 못했습니다.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

    // 입력칸 위 제목
  Widget inputTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // 모든 입력칸에 같은 스타일 적용
  InputDecoration inputDecoration(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colors.outline,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colors.primary,
          width: 2,
        ),
      ),
    );
  }
} // class