import 'dart:io';

String? exportFileSystemCode(Object error) {
  if (error is! FileSystemException) return null;
  final code = error.osError?.errorCode;
  // Windows와 POSIX는 같은 번호도 의미가 달라 OS별로 해석한다.
  if (Platform.isWindows) {
    return switch (code) {
      5 => 'eacces',
      39 || 112 => 'enospc',
      2 || 3 || 15 || 21 => 'enoent',
      _ => code == null ? null : 'errno_$code',
    };
  }
  return switch (code) {
    1 || 13 || 30 => 'eacces',
    28 => 'enospc',
    2 || 19 || 20 => 'enoent',
    _ => code == null ? null : 'errno_$code',
  };
}
