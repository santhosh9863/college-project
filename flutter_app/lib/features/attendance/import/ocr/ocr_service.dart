/// On-device OCR service. Implementations must never upload the image or its
/// text anywhere.
abstract class OcrService {
  /// Recognizes text in the image at [imagePath] and returns the raw text.
  ///
  /// Throws [OcrException] when recognition fails (e.g. model not available,
  /// malformed image, platform error).
  Future<String> recognizeImage(String imagePath);

  /// Releases native resources. Called by the owning controller.
  void dispose();
}

/// Failure of on-device OCR.
class OcrException implements Exception {
  const OcrException(this.message);

  final String message;

  @override
  String toString() => 'OcrException: $message';
}