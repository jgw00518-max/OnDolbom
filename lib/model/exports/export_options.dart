import 'dart:typed_data';

String exportDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

enum ExportFormat {
  html('html_zip', 'zip', 'application/zip', [0x50, 0x4b, 0x03, 0x04]),
  pdf('pdf', 'pdf', 'application/pdf', [0x25, 0x50, 0x44, 0x46, 0x2d]);

  const ExportFormat(
    this.apiValue,
    this.extension,
    this.contentType,
    this.signature,
  );
  final String apiValue;
  final String extension;
  final String contentType;
  final List<int> signature;
}

class ExportOptions {
  const ExportOptions({
    required this.startDate,
    required this.endDate,
    required this.memos,
    required this.chats,
    required this.includeImages,
    this.format = ExportFormat.html,
  });

  final DateTime startDate;
  final DateTime endDate;
  final bool memos;
  final bool chats;
  final bool includeImages;
  final ExportFormat format;

  Map<String, Object> toJson(String roomId) => {
    'family_room_id': roomId,
    'start_date': exportDate(startDate),
    'end_date': exportDate(endDate),
    'scopes': [if (memos) 'memos', if (chats) 'chats'],
    'include_images': includeImages,
    'format': format.apiValue,
  };

  String get fileName =>
      'ondolbom_${exportDate(startDate).replaceAll('-', '')}_'
      '${exportDate(endDate).replaceAll('-', '')}.${format.extension}';
}

class ExportFile {
  const ExportFile({
    required this.bytes,
    required this.name,
    this.format = ExportFormat.html,
  });
  final Uint8List bytes;
  final String name;
  final ExportFormat format;
}
