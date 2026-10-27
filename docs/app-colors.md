# 공통 색상

공통 팔레트는 `lib/theme/app_colors.dart`, 앱의 기본 테마는 `lib/theme/app_theme.dart`에서 관리한다. `main.dart`는 `AppTheme.light`를 사용한다.

| 상수 | 색상 | 용도 |
|---|---|---|
| `AppColors.primary` | `#F6B08A` | 주요 버튼·숫자 배지 |
| `AppColors.textPrimary` | `#3E3A39` | 주요 글자·버튼 글자 |
| `AppColors.background` | `#FFFAF7` | 화면 배경 |
| `AppColors.surface` | `#FFFFFF` | 카드·입력칸 배경 |
| `AppColors.peachLight` | `#FFD6B5` | 안내 카드·아이콘 배경 |
| `AppColors.peachSoft` | `#FCEEE3` | 연한 복숭아색 영역 |
| `AppColors.textSecondary` | `#9A8F89` | 보조 글자·날짜 |
| `AppColors.border` | `#EADDD5` | 테두리·구분선 |
| `AppColors.sageLight` | `#DCE6CF` | 연두색 배경 |
| `AppColors.sageDark` | `#60704F` | 연두색 영역의 글자·아이콘 |
| `AppColors.sage` | `#B7C8A1` | 기존 인증 화면의 연두색 포인트 |
| `AppColors.notificationDot` | `#E53935` | 메뉴 알림 점 |

```dart
import 'package:ondolbom/theme/app_colors.dart';

const TextStyle(color: AppColors.textPrimary);
```

기본 Material 위젯은 `Theme.of(context).colorScheme`이나 기본 테마를 우선 사용한다. 특정 디자인 요소에 고정 팔레트가 필요한 경우 `AppColors`를 참조한다.

이번 작업은 밝은 모드 공통 팔레트 지정이다. 화면별 전용 색상·소셜 브랜드 색상·오류 상태 색상은 유지한다. 모든 화면의 위젯 구조를 통합하거나 다크 모드·글꼴을 변경한 작업은 아니다. 향후 다크 모드는 색상 역할에 따른 테마 연결을 추가해야 한다.
