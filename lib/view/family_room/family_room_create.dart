import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

class FamilyRoomCreate extends ConsumerStatefulWidget {
  const FamilyRoomCreate({super.key});

  @override
  ConsumerState<FamilyRoomCreate> createState() => _FamilyRoomCreateState();
}

class _FamilyRoomCreateState extends ConsumerState<FamilyRoomCreate> {
  late TextEditingController nameController;
  late TextEditingController birthController;
  late TextEditingController addressController;
  late TextEditingController notesController;

  int? selectedGender;

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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 88,
        automaticallyImplyLeading: false,
        leadingWidth: 68,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Center(
            child: SizedBox.square(
              dimension: 42,
              child: OutlinedButton(
                onPressed: state.isLoading
                    ? null
                    : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFEaded7)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Icon(Icons.chevron_left, size: 24),
              ),
            ),
          ),
        ),
        centerTitle: true,
        title: const Column(
          children: [
            Text(
              'NEW FAMILY SPACE',
              style: TextStyle(
                color: Color(0xFFA77762),
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 3),
            Text(
              '돌봄 공간 만들기',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            width: 42,
            height: 42,
            margin: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppColors.sageLight,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.home_outlined,
              color: AppColors.sageDark,
              size: 23,
            ),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 28),
        children: [
          // 안내 카드는 표현만 담당하며 실제 생성·입력 검증은 기존 메서드를 사용한다.
          Container(
            padding: const EdgeInsets.all(22),
            margin: const EdgeInsets.only(bottom: 25),
            decoration: BoxDecoration(
              color: AppColors.peachLight,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '새로운 시작',
                  style: TextStyle(
                    color: Color(0xFF97624B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '소중한 가족을 위한\n공간을 만들어 볼까요?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                    letterSpacing: -1,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '돌봄 대상자의 기본 정보를 입력해 주세요.\n공간을 만든 뒤에도 언제든 수정할 수 있어요.',
                  style: TextStyle(
                    color: Color(0xFF846A5E),
                    fontSize: 12,
                    height: 1.65,
                  ),
                ),
              ],
            ),
          ),

          inputTitle('돌봄 대상자 이름', required: true),
          TextField(
            controller: nameController,
            enabled: !state.isLoading,
            maxLength: 30,
            decoration: inputDecoration(
              context,
            ).copyWith(counterText: '', hintText: '이름을 입력해 주세요'),
          ),
          const SizedBox(height: 24),

          // 남성은 1, 여성은 2로 저장하며 반드시 하나를 선택한다.
          inputTitle('성별', required: true),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(value: 1, label: Text('남성')),
                ButtonSegment<int>(value: 2, label: Text('여성')),
              ],
              selected: selectedGender == null ? <int>{} : {selectedGender!},
              emptySelectionAllowed: selectedGender == null,
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith<Color>(
                  (states) => states.contains(WidgetState.selected)
                      ? const Color(0xFFFFEBD9)
                      : Colors.white,
                ),
                foregroundColor: WidgetStateProperty.resolveWith<Color>(
                  (states) => states.contains(WidgetState.selected)
                      ? const Color(0xFF99522F)
                      : const Color(0xFF78716A),
                ),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: Color(0xFFE8DFD7)),
                ),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              onSelectionChanged: state.isLoading
                  ? null
                  : (selection) {
                      setState(() {
                        selectedGender = selection.first;
                      });
                    },
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
              suffixIcon: const Icon(Icons.calendar_month_outlined),
            ),
          ),
          const SizedBox(height: 24),

          inputTitle('돌봄 장소'),
          TextField(
            controller: addressController,
            enabled: !state.isLoading,
            maxLength: 255,
            decoration: inputDecoration(
              context,
            ).copyWith(counterText: '', hintText: '예: 서울시 마포구'),
          ),
          const SizedBox(height: 24),

          inputTitle('특이사항'),
          TextField(
            controller: notesController,
            enabled: !state.isLoading,
            maxLines: 4,
            decoration: inputDecoration(
              context,
            ).copyWith(hintText: '건강 상태나 돌봄 시 참고할 내용을 적어주세요'),
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
                      foregroundColor: const Color(0xFF6D6561),
                      side: const BorderSide(color: Color(0xFFDED3CC)),
                      backgroundColor: AppColors.surface,
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
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: state.isLoading ? null : () => createAction(),
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
      initialDate: DateTime.tryParse(birthController.text) ?? DateTime(1950),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('돌봄대상자 이름을 입력해 주세요.')));
      return;
    }

    final gender = selectedGender;

    if (gender == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('성별을 선택해 주세요.')));
      return;
    }

    final birth = birthController.text.trim();
    final address = addressController.text.trim();
    final notes = notesController.text.trim();

    final success = await ref
        .read(familyRoomProvider.notifier)
        .createRoom(
          name: name,
          gender: gender,
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
          ref.read(familyRoomProvider).errorMessage ?? '공간을 생성하지 못했습니다.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // 입력칸 위 제목
  Widget inputTitle(String title, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: required ? AppColors.peachSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              required ? '필수' : '선택',
              style: TextStyle(
                color: required
                    ? const Color(0xFFA46F59)
                    : const Color(0xFFAAA09B),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 모든 입력칸에 같은 스타일 적용
  InputDecoration inputDecoration(BuildContext context) {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
      hintStyle: const TextStyle(color: Color(0xFFB4AAA5), fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: const Color(0xFFE5DBD5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
} // class
