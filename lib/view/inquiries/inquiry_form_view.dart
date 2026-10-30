import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/inquiries/inquiry_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/inquiries/inquiry_vm.dart';

class InquiryFormView extends ConsumerStatefulWidget {
  const InquiryFormView({super.key, this.familyRoomId});
  final String? familyRoomId;
  @override
  ConsumerState<InquiryFormView> createState() => _InquiryFormViewState();
}

class _InquiryFormViewState extends ConsumerState<InquiryFormView> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(), _content = TextEditingController();
  bool _linkRoom = false;
  @override
  void initState() {
    super.initState();
    _linkRoom = widget.familyRoomId != null;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  String? _validate(String? input, int max) {
    final text = input?.trim() ?? '';
    if (text.isEmpty || text.runes.length > max) return '1~$max자로 입력해 주세요.';
    if (text.runes.any((c) => c > 0xFFFF)) {
      return '현재 문의는 일부 이모지를 지원하지 않습니다. 이모지를 제외해 주세요.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await ref
        .read(inquiryCreateProvider.notifier)
        .create(
          _title.text,
          _content.text,
          familyRoomId: _linkRoom ? widget.familyRoomId : null,
        );
    if (!mounted) return;
    final id = ref.read(inquiryCreateProvider).asData?.value;
    if (id != null) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final operation = ref.watch(inquiryCreateProvider);
    return PopScope(
      canPop: !operation.isLoading,
      child: Scaffold(
        backgroundColor: AppColors.resolve(context, InquiryStyle.paper),
        appBar: InquiryStyle.header(
          context,
          AppStrings.tr(context, '문의 작성'),
          busy: operation.isLoading,
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).peachLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.resolve(
                                  context,
                                  InquiryStyle.peach,
                                ),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                Icons.edit_outlined,
                                color: AppColors.resolve(
                                  context,
                                  Color(0xFF875C49),
                                ),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppStrings.tr(context, '어떤 도움이 필요하신가요?'),
                                    style: TextStyle(
                                      color: AppColors.resolve(
                                        context,
                                        InquiryStyle.ink,
                                      ),
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      height: 1.4,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    AppStrings.tr(
                                      context,
                                      '비밀번호나 인증번호 등 민감한 정보는 입력하지 마세요.',
                                    ),
                                    style: TextStyle(
                                      color: AppColors.resolve(
                                        context,
                                        Color(0xFFA46F59),
                                      ),
                                      fontSize: 11,
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 25),
                      Text(
                        AppStrings.tr(context, '문의 제목'),
                        style: TextStyle(
                          color: AppColors.resolve(context, InquiryStyle.ink),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _title,
                        enabled: !operation.isLoading,
                        maxLength: 100,
                        decoration: InquiryStyle.input(
                          context,
                          AppStrings.tr(context, '문의 제목을 입력해 주세요'),
                        ),
                        validator: (v) => _validate(v, 100),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppStrings.tr(context, '문의 내용'),
                        style: TextStyle(
                          color: AppColors.resolve(context, InquiryStyle.ink),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _content,
                        enabled: !operation.isLoading,
                        maxLength: 10000,
                        minLines: 6,
                        maxLines: 12,
                        decoration: InquiryStyle.input(
                          context,
                          AppStrings.tr(context, '궁금한 내용을 자세히 적어주세요'),
                        ),
                        validator: (v) => _validate(v, 10000),
                      ),
                      if (widget.familyRoomId != null)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            AppStrings.tr(context, '현재 돌봄 공간과 관련된 문의'),
                          ),
                          value: _linkRoom,
                          onChanged: operation.isLoading
                              ? null
                              : (v) => setState(() => _linkRoom = v ?? false),
                        ),
                      if (operation.hasError)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            AppStrings.error(
                              context,
                              operation.error.toString(),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.resolve(
                            context,
                            InquiryStyle.peach,
                            onAccent: true,
                          ),
                          foregroundColor: AppColors.resolve(
                            context,
                            InquiryStyle.ink,
                            onAccent: true,
                          ),
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: operation.isLoading ? null : _submit,
                        child: Text(
                          operation.isLoading
                              ? AppStrings.tr(context, '등록 중…')
                              : AppStrings.tr(context, '문의 등록'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
