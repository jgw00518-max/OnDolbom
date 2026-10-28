import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

abstract final class MedicationStyle {
  static final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
    side: const BorderSide(color: AppColors.border),
  );

  static InputDecoration field(String label, {String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.surface,
      labelStyle: const TextStyle(color: AppColors.textPrimary),
      floatingLabelStyle: const TextStyle(
        color: AppColors.sageDark,
        fontWeight: FontWeight.w700,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.sageDark, width: 1.5),
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
    color: AppColors.peachSoft,
    padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
    child: Row(
      children: [
        const Icon(
          Icons.medication_outlined,
          color: AppColors.sageDark,
          size: 24,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: '닫기',
          onPressed: onClose,
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
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
          const Icon(
            Icons.calendar_today_outlined,
            size: 20,
            color: AppColors.sageDark,
          ),
          Text(
            date,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
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
        Icon(icon, size: 19, color: AppColors.sageDark),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}
