# ondolbom

가족 사용자용 Flutter 앱과 FastAPI 백엔드입니다. 관리자 웹과 관리자 전용 API는 별도 프로젝트에서 관리합니다.

## 협업용 폴더 구조

```text
lib/
  main.dart                앱 시작·앱 설정·화면 경로 등록
  model/                   기능별 데이터·JSON 변환
  view/                    기능별 화면·전용 위젯
  vm/                      기능별 상태 관리·API 호출
python/
  main.py                  FastAPI 생성·라우터 등록
  database.py              MySQL 연결 생성
  features/                담당자가 기능별 router.py 추가
  tests/                   백엔드 테스트
test/                      Flutter 테스트
docs/                      프로세스·API·권한·미정 사항
```

수업의 `model / view / vm` 분류를 유지합니다. VM에서 서버 API를 호출하며
별도 Service 계층은 두지 않습니다. 상태 관리 패키지는 아직 정하지 않았습니다.
로그인·선택 공간 상태의 공유 방식과 서버 주소 관리 방식은 팀에서 합의 후 구현합니다.

기능 담당자가 `lib/model/기능명/`, `lib/view/기능명/`, `lib/vm/기능명/`과
`python/features/기능명/`을 추가합니다. 기능 폴더는 미리 만들지 않습니다.
백엔드 기능 폴더에는 `__init__.py`와 `router.py`를 두고 `python/main.py`에서 등록합니다.
복잡한 기능만 요청 모델·업무 처리·SQL 파일을 추가로 분리합니다.

선택 공간과 그 공간의 역할은 앱에서 일관되게 관리하고, 실제 접근 권한은 서버에서 검사해야 합니다.
인증·권한 검사는 아직 미구현입니다. 백엔드 실행·테스트는 [python/README.md](python/README.md)를 참고합니다.

빈 필수 폴더는 `.gitkeep`으로 Git에 유지합니다. `.env`에는 실제 설정을 작성하고
Git에 올리지 않습니다. 설정 항목은 `python/.env.example`을 참고합니다.

## Flutter 실행

```powershell
flutter pub get
flutter run
```

## Flutter 참고 자료

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
