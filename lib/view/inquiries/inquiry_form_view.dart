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
        appBar: AppBar(title: const Text('문의 작성')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('문의할 내용을 작성해 주세요. 비밀번호나 인증번호는 입력하지 마세요.'),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _title,
                    enabled: !operation.isLoading,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: '제목'),
                    validator: (v) => _validate(v, 100),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _content,
                    enabled: !operation.isLoading,
                    maxLength: 10000,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: '문의 내용',
                      alignLabelWithHint: true,
                    ),
                    validator: (v) => _validate(v, 10000),
                  ),
                  if (widget.familyRoomId != null)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('현재 가족 공간과 관련된 문의'),
                      value: _linkRoom,
                      onChanged: operation.isLoading
                          ? null
                          : (v) => setState(() => _linkRoom = v ?? false),
                    ),
                  if (operation.hasError)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(operation.error.toString()),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: operation.isLoading ? null : _submit,
                    child: Text(operation.isLoading ? '등록 중…' : '문의 등록'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
