import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/vm/invites/invite_vm.dart';

class InviteCreate extends ConsumerStatefulWidget {
  const InviteCreate({
    super.key,
    required this.familyRoomId,
    required this.recipientName,
  });

  final String familyRoomId;
  final String recipientName;

  @override
  ConsumerState<InviteCreate> createState() => _InviteCreateState();
}

class _InviteCreateState extends ConsumerState<InviteCreate> {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();

  bool isSaving = false;
  String? errorMessage;

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppStrings.tr(context, '가족 초대')),
          automaticallyImplyLeading: false,
          leadingWidth: 62,
          leading: AppBackLeading(enabled: !isSaving),
        ),
        body: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(AppStrings.tr(context, '함께 돌볼 가족의 로그인 이메일을 입력해 주세요.')),
              const SizedBox(height: 24),

              TextFormField(
                controller: emailController,
                enabled: !isSaving,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: AppStrings.tr(context, '초대할 가족 이메일'),
                  hintText: 'family@example.com',
                  border: OutlineInputBorder(),
                ),
                validator: validateEmail,
              ),
              const SizedBox(height: 16),

              Text(
                AppStrings.tr(context, '초대받은 가족은 같은 이메일로 로그인한 뒤 ') +
                    AppStrings.tr(context, '‘받은 가족 초대’에서 수락할 수 있습니다.'),
                style: TextStyle(
                  color: AppColors.resolve(context, Color(0xFF78716A)),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),

              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    AppStrings.error(context, errorMessage!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),

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
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isSaving
                      ? AppStrings.tr(context, '초대 등록 중…')
                      : AppStrings.tr(context, '초대 등록'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- function -----

  String? validateEmail(String? value) {
    final email = (value ?? '').trim();

    if (email.isEmpty) {
      return '초대할 이메일을 입력해 주세요.';
    }

    if (email.length > 200 ||
        '@'.allMatches(email).length != 1 ||
        RegExp(r'\s').hasMatch(email)) {
      return '올바른 이메일을 입력해 주세요.';
    }

    final parts = email.split('@');
    final local = parts[0];
    final domain = parts[1];

    if (local.isEmpty ||
        !domain.contains('.') ||
        domain.startsWith('.') ||
        domain.endsWith('.')) {
      return '올바른 이메일을 입력해 주세요.';
    }

    return null;
  }

  Future<void> saveAction() async {
    if (isSaving || !formKey.currentState!.validate()) {
      return;
    }

    final email = emailController.text.trim();

    setState(() {
      isSaving = true;
      errorMessage = null;
    });

    try {
      final emailSent = await ref
          .read(inviteVmProvider)
          .createInvite(familyRoomId: widget.familyRoomId, email: email);

      if (!mounted) {
        return;
      }

      setState(() {
        isSaving = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context, emailSent);
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
