"""연결된 Android 기기·에뮬레이터의 localhost를 PC 개발 서버로 전달한다."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def find_adb():
    command = shutil.which('adb')
    if command:
        return command
    sdk_paths = [os.environ.get('ANDROID_HOME'), os.environ.get('ANDROID_SDK_ROOT')]
    properties = ROOT / 'android/local.properties'
    if properties.exists():
        for line in properties.read_text(encoding='utf-8-sig').splitlines():
            if line.startswith('sdk.dir='):
                sdk_paths.append(line.split('=', 1)[1].replace('\\\\', '\\').replace('\\:', ':'))
    if os.environ.get('LOCALAPPDATA'):
        sdk_paths.append(str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk'))
    for sdk in sdk_paths:
        if sdk:
            path = Path(sdk) / 'platform-tools' / ('adb.exe' if os.name == 'nt' else 'adb')
            if path.is_file():
                return str(path)
    raise SystemExit('Android SDK의 platform-tools/adb를 찾지 못했습니다.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8000)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('port는 1~65535 범위여야 합니다.')
    config = ROOT / 'config/social-login.local.json'
    if not config.is_file():
        raise SystemExit('config/social-login.example.json을 social-login.local.json으로 복사하고 로컬 설정을 입력해 주세요.')
    values = json.loads(config.read_text(encoding='utf-8-sig'))
    adb = find_adb()
    devices = subprocess.run([adb, 'devices'], check=True, capture_output=True, text=True, timeout=20)
    identifiers = [parts[0] for line in devices.stdout.splitlines()
                   if len(parts := line.split()) >= 2 and parts[1] == 'device']
    if not identifiers:
        raise SystemExit('연결된 Android 기기가 없습니다. USB 연결·USB 디버깅 허용 또는 에뮬레이터 실행 상태를 확인해 주세요.')
    for identifier in identifiers:
        subprocess.run([adb, '-s', identifier, 'reverse', f'tcp:{args.port}', f'tcp:{args.port}'],
                       check=True, capture_output=True, text=True, timeout=15)
        print(f'포트 연결 완료: {identifier} (기기 {args.port} → PC {args.port})')
    # 다른 소셜 로그인 설정값은 보존하고 출력하지 않는다. 로컬 파일만 수정한다.
    values['API_BASE_URL'] = f'http://127.0.0.1:{args.port}'
    config.write_text(json.dumps(values, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'API_BASE_URL: {values["API_BASE_URL"]}')
    print('서버가 실행 중인지 확인하고 앱을 완전히 종료한 뒤 다음 명령으로 실행하세요:')
    print('flutter run --dart-define-from-file=config/social-login.local.json')


if __name__ == '__main__':
    try:
        main()
    except (subprocess.SubprocessError, OSError, ValueError):
        raise SystemExit('연결 설정에 실패했습니다. adb 연결 상태와 로컬 설정 JSON을 확인해 주세요.') from None
