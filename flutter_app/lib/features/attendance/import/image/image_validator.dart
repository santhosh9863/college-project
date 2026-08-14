import 'dart:io';
import 'dart:typed_data';

/// Result of validating a picked image before OCR.
class ImageValidation {
  const ImageValidation._(this.isValid, {this.reason, this.sizeBytes});

  const ImageValidation.valid(int sizeBytes) : this._(true, sizeBytes: sizeBytes);

  const ImageValidation.invalid(String reason) : this._(false, reason: reason);

  final bool isValid;
  final String? reason;
  final int? sizeBytes;
}

/// Lightweight pre-OCR validation: existence, recognized image format (magic
/// bytes), and a size guard so huge or corrupt files fail fast and the UI
/// stays responsive.
class ImageValidator {
  const ImageValidator();

  /// Maximum accepted file size (50 MB). Screenshots are small; this only
  /// guards against accidental picks.
  static const int maxFileBytes = 50 * 1024 * 1024;

  Future<ImageValidation> validate(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const ImageValidation.invalid('The selected image could not be opened.');
    }

    final size = await file.length();
    if (size == 0) {
      return const ImageValidation.invalid('The selected file is empty.');
    }
    if (size > maxFileBytes) {
      return const ImageValidation.invalid('The selected image is too large to process.');
    }

    try {
      final raf = await file.open();
      final header = await raf.read(12);
      await raf.close();
      if (!_isSupportedFormat(header)) {
        return const ImageValidation.invalid(
          'Unsupported image format. Please choose a JPEG, PNG, WEBP, BMP or GIF screenshot.',
        );
      }
    } on FileSystemException {
      return const ImageValidation.invalid('The selected image could not be read.');
    }

    return ImageValidation.valid(size);
  }

  static bool _isSupportedFormat(Uint8List header) {
    // Each format is checked against the bytes its magic actually needs, so
    // tiny-but-valid headers (e.g. a minimal JPEG) are not rejected.
    if (header.length >= 3 &&
        header[0] == 0xFF &&
        header[1] == 0xD8 &&
        header[2] == 0xFF) {
      return true; // JPEG
    }
    if (header.length >= 4 &&
        header[0] == 0x89 &&
        header[1] == 0x50 &&
        header[2] == 0x4E &&
        header[3] == 0x47) {
      return true; // PNG
    }
    if (header.length >= 2 && header[0] == 0x42 && header[1] == 0x4D) return true; // BMP
    if (header.length >= 3 &&
        header[0] == 0x47 &&
        header[1] == 0x49 &&
        header[2] == 0x46) {
      return true; // GIF
    }
    // RIFF....WEBP
    if (header.length >= 12 &&
        header[0] == 0x52 &&
        header[1] == 0x49 &&
        header[2] == 0x46 &&
        header[3] == 0x46 &&
        header[8] == 0x57 &&
        header[9] == 0x45 &&
        header[10] == 0x42 &&
        header[11] == 0x50) {
      return true;
    }
    return false;
  }
}