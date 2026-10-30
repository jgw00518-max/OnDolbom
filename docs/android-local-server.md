# Android 실기기·에뮬레이터에서 같은 PC 서버 사용

Android 에뮬레이터의 `10.0.2.2`는 PC를 뜻하는 특수 주소다. 실제 휴대폰에서는 같은 의미로 사용할 수 없다.

## USB 연결 방식

휴대폰의 개발자 옵션에서 USB 디버깅을 켜고 PC에 연결한 뒤 디버깅 허용을 승인한다. 에뮬레이터도 함께 실행할 수 있다.

프로젝트 루트에서 실행한다.

```powershell
python scripts/connect_android_server.py
```

이 명령은 현재 연결된 각 Android 기기에 `adb reverse tcp:8000 tcp:8000`을 설정하고, 무시되는 로컬 파일 `config/social-login.local.json`의 `API_BASE_URL`만 `http://127.0.0.1:8000`으로 변경한다. 키 등 다른 설정값은 유지한다. 팀원은 각자 자신의 PC에서 실행한다.

서버가 실행 중이 아니라면 별도 터미널에서 실행한다.

```powershell
python -m uvicorn python.main:app --host 0.0.0.0 --port 8000 --reload --no-access-log
```

앱을 완전히 종료한 뒤 기존 소셜 설정 파일을 포함해 실행한다.

```powershell
flutter devices
flutter run -d <기기ID> --dart-define-from-file=config/social-login.local.json
```

기기가 여러 개면 `-d`로 실제 휴대폰 또는 에뮬레이터를 선택한다. `API_BASE_URL`은 빌드 시 전달되는 값이므로 변경 후 기존 실행 앱을 새 명령으로 다시 실행해야 한다. VS Code에서는 기기를 선택하고 **온돌봄 Android (로컬 서버)** 실행 구성을 사용한다. `.vscode/launch.json`에 같은 로컬 설정 파일을 전달하도록 구성했다.

기기의 Chrome에서 `http://127.0.0.1:8000/health`를 열어 `{"status":"ok"}`가 보이는지 확인한다. 이는 API 연결 확인이며 MySQL 연결 확인과는 별개다.

USB 연결을 끊거나 기기·adb를 재시작하면 포트 연결을 다시 설정해야 할 수 있다. 기기를 다시 연결한 뒤 위 스크립트를 재실행한다. PC 서버도 실행 상태를 유지해야 한다. Android 디버그 빌드에는 개발용 HTTP 허용 설정이 이미 있다.

## 같은 Wi-Fi로 연결하는 경우

PC와 휴대폰이 같은 네트워크에 있어야 한다. 로컬 JSON의 `API_BASE_URL`에 PC의 Wi-Fi IPv4 주소를 사용한다. 예: `http://192.168.x.x:8000`. 에뮬레이터도 이 주소를 사용할 수 있다. 서버는 `0.0.0.0`으로 실행하고, Windows 방화벽에서 해당 네트워크의 Python/8000번 포트 접근이 허용되어 있어야 한다. 네트워크의 기기 간 통신 차단 여부도 영향을 준다. IP가 바뀌면 설정을 다시 갱신한다.

네이버 브라우저 로그인은 API 주소와 별개로 서버 `.env`의 `NAVER_REDIRECT_URI` 및 네이버 콘솔 Callback URL도 실행 기기에서 접근 가능한 동일 주소로 등록돼 있어야 한다. 에뮬레이터 전용 `10.0.2.2` 콜백은 실제 휴대폰에서 사용할 수 없다. USB 방식에서는 `127.0.0.1` 콜백을 사용할 수 있으나 콘솔 등록과 서버 설정을 함께 맞춰야 한다.
