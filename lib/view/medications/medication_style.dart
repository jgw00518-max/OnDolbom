import 'package:ondolbom/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

abstract final class MedicationStyle {
  static RoundedRectangleBorder shape(BuildContext context) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.of(context).border),
      );

  static InputDecoration field(
    BuildContext context,
    String label, {
    String? hint,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppColors.of(context).border),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.of(context).surface,
      labelStyle: TextStyle(color: AppColors.of(context).textPrimary),
      floatingLabelStyle: TextStyle(
        color: AppColors.of(context).sageDark,
        fontWeight: FontWeight.w700,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: AppColors.of(context).sageDark,
          width: 1.5,
        ),
      ),
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.all(16),
      alignLabelWithHint: true,
    );
  }
}

class MedicationHeading extends StatelessWidget {
  const MedicationHeading({super.key, required this.title, this.onClose});
  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.of(context).peachSoft,
    padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
    child: Row(
      children: [
        Icon(
          Icons.medication_outlined,
          color: AppColors.of(context).sageDark,
          size: 24,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.of(context).textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: AppStrings.tr(context, '닫기'),
          onPressed: onClose,
          icon: Icon(Icons.close, color: AppColors.of(context).textPrimary),
        ),
      ],
    ),
  );
}

class MedicationDateLabel extends StatelessWidget {
  const MedicationDateLabel({super.key, required this.date});
  final String date;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 6,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 20,
            color: AppColors.of(context).sageDark,
          ),
          Text(
            date,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.of(context).textPrimary,
            ),
          ),
        ],
      ),
    ),
  );
}

class MedicationInfoRow extends StatelessWidget {
  const MedicationInfoRow({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AppColors.of(context).sageDark),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.of(context).textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}
