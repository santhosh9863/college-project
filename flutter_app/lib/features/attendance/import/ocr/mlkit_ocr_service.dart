import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_service.dart';

/// Google ML Kit Text Recognition v2 (Latin script), fully on-device.
///
/// Privacy: the image is processed locally; no pixels or text leave the
/// device. ML Kit downloads its Latin model once on first use, after which
/// recognition runs offline.
class MlKitOcrService implements OcrService {
  MlKitOcrService({TextRecognizer? recognizer})
      : _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  @override
  Future<String> recognizeImage(String imagePath) async {
    try {
      final input = InputImage.fromFilePath(imagePath);
      final result = await _recognizer.processImage(input);
      return result.text;
    } catch (error) {
      throw OcrException('Text recognition failed: $error');
    }
  }

  @override
  void dispose() {
    _recognizer.close();
  }
}