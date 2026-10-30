import 'dart:convert';
import 'package:flutter/services.dart';

class FamilyRoomOnboardingStep {
  const FamilyRoomOnboardingStep({
    required this.title,
    required this.description,
    required this.image,
    required this.target,
    this.targetRadius = 20,
  });
  final String title, description, image;
  // 스크린샷 기준 비율 좌표. 이미지와 같은 비율로 확대·축소한다.
  final Rect target;
  // 촬영 원본의 실제 버튼·박스 모서리 반경. 사진과 같은 비율로 축소한다.
  // 개발 중 핫 리로드 이전에 만들어진 안내 데이터에는 이 값이 없을 수 있다.
  final double? targetRadius;

  static Future<List<FamilyRoomOnboardingStep>> load() async {
    final targets =
        jsonDecode(
              await rootBundle.loadString(
                'assets/images/onboarding/targets.json',
              ),
            )
            as Map<String, dynamic>;
    const copy = [
      ('create', '우리 가족의 돌봄 공간 만들기', '아래 + 버튼을 눌러 새로운 돌봄 공간을 만들 수 있어요.'),
      (
        'enter',
        '함께할 돌봄 공간에 입장해요',
        '원하는 가족의 공간 카드를 눌러 입장해 주세요. \n화면 속 김온돌 가족은 안내를 위한 예시예요.',
      ),
      ('menu', '공통 기능은 왼쪽 위 메뉴에', '왼쪽 위 메뉴 버튼을 누르면 \n내 계정의 공통 기능을 확인할 수 있어요.'),
      ('drawer', '필요한 소식을 한곳에서', '초대, 알림, 공지사항, 문의, 개인 설정을 \n이 메뉴에서 확인해요.'),
      ('투약일지', '투약일지', '투약 정보를 확인하고, \n가족이 함께 복용 여부를 체크할 수 있어요.'),
      ('실시간 채팅', '실시간 채팅', '같은 돌봄 공간의 가족과 실시간으로 대화하고 \n필요한 소식을 나눠요.'),
      ('메모', '메모', '돌봄 중 기억할 내용과 사진을 가족에게 공유해요.'),
      ('일정', '일정', '돌봄 일정을 등록 및 확인하고 \n내가 담당할 일정을 수락해요.'),
      ('대상자 정보', '대상자 정보', '함께 돌보는 대상자의 기본 정보와 \n주의할 내용을 확인해요.'),
      ('공간 설정', '공간 설정', '함께하는 가족과 공간 관리 기능을 확인해요. \n역할에 따라 사용할 수 있는 기능이 달라요.'),
    ];
    return [
      for (final item in copy)
        _fromTarget(item, targets[item.$1] as Map<String, dynamic>),
    ];
  }

  static FamilyRoomOnboardingStep _fromTarget(
    (String, String, String) copy,
    Map<String, dynamic> data,
  ) {
    final r = (data['rect'] as List).map((v) => (v as num).toDouble()).toList();
    return FamilyRoomOnboardingStep(
      title: copy.$2,
      description: copy.$3,
      image: 'assets/images/onboarding/${data['image']}.png',
      target: copy.$1 == 'menu'
          ? Rect.fromLTWH(
              r[0] + 8 / 390,
              r[1] + 10 / 844,
              r[2] - 16 / 390,
              r[3] - 20 / 844,
            )
          : Rect.fromLTWH(r[0], r[1], r[2], r[3]),
      targetRadius: switch (copy.$1) {
        'create' => 18, // 목록의 새 공간 만들기 버튼
        'menu' => 18, // 화면 가장자리에서 떨어진 둥근 메뉴 강조 영역
        'drawer' => 13, // 공통 메뉴 그룹
        _ => 20, // 공간 카드와 돌봄 메뉴 버튼
      },
    );
  }
}
