import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

/// 메뉴 진입 버튼과 같은 그림을 표시하는 장식이며, 터치 동작은 제공하지 않는다.
class MenuHeaderIcon extends StatelessWidget {
  const MenuHeaderIcon({
    super.key,
    required this.icon,
    this.backgroundColor = AppColors.sageLight,
    this.foregroundColor = AppColors.sageDark,
    this.unreadCount = 0,
  });
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final int unreadCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 20),
    child: Center(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(child: Icon(icon, color: foregroundColor, size: 24)),
            if (unreadCount > 0)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  width: 21,
                  height: 21,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
