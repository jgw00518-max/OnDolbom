import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

/// 현재 돌봄 공간을 표시하는 공통 안내 문구.
class FamilyRoomLabel extends StatelessWidget {
  const FamilyRoomLabel({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(top: 2),
        child: Icon(
          Icons.home_outlined,
          size: 18,
          color: AppColors.of(context).sageDark,
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.of(context).sageDark,
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}
