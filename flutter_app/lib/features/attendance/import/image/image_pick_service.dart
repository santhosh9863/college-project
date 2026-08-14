import 'package:image_picker/image_picker.dart';

/// Picks an image for OCR. Returns the temporary file path, or `null` when
/// the user cancelled the picker.
abstract class ImagePickService {
  Future<String?> pickGalleryImage();
}

/// Gallery picking via [ImagePicker]. The picker copies the selection into an
/// app cache directory; callers are responsible for deleting the temporary
/// file after processing (see [ImagePickServiceCleanup]).
class GalleryImagePickService implements ImagePickService {
  GalleryImagePickService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pickGalleryImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    return file?.path;
  }
}