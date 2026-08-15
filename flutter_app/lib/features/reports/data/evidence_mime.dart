/// Maps a file name to the MIME type accepted by the private evidence bucket
/// (images + PDF). Unknown extensions resolve to octet-stream, which the
/// bucket's allowed_mime_types will reject server-side.
String evidenceMimeTypeFromName(String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}
