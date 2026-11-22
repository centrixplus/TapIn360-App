import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Long side of the uploaded photo (spec §15.1).
const maxPhotoSide = 640;
const photoQuality = 70;

/// The server rejects photos over 1 MB decoded; stay under the decimal MB.
const maxPhotoBytes = 1000000;

const _fallbackQualities = [55, 40, 25];

class PhotoTooLarge implements Exception {
  const PhotoTooLarge(this.bytes);

  final int bytes;

  @override
  String toString() => 'PhotoTooLarge($bytes bytes)';
}

/// Camera JPEG → upload JPEG: EXIF rotation applied, long side at most
/// [maxSide] (never upscaled), quality [quality], lowered step by step until
/// the result is at most [maxBytes]. Throws [FormatException] for bytes that
/// are not an image and [PhotoTooLarge] if even the lowest quality is too big.
Uint8List compressPhoto(
  Uint8List input, {
  int maxSide = maxPhotoSide,
  int quality = photoQuality,
  int maxBytes = maxPhotoBytes,
}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) throw const FormatException('Not a decodable image');
  var image = img.bakeOrientation(decoded);
  if (max(image.width, image.height) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  var smallest = 0;
  for (final q in [quality, ..._fallbackQualities.where((f) => f < quality)]) {
    final out = img.encodeJpg(image, quality: q);
    if (out.length <= maxBytes) return out;
    smallest = out.length;
  }
  throw PhotoTooLarge(smallest);
}

/// Pixel size of [jpeg] as shown upright (EXIF rotation applied, as ML Kit
/// does), read from the headers only. Throws [FormatException] for bytes that
/// are not a JPEG.
({int width, int height}) jpegUprightSize(Uint8List jpeg) {
  final info = img.JpegDecoder().startDecode(jpeg);
  if (info == null || info.width <= 0 || info.height <= 0) throw const FormatException('Not a JPEG');
  final orientation = img.decodeJpgExif(jpeg)?.imageIfd.orientation ?? 1;
  return orientation >= 5 && orientation <= 8
      ? (width: info.height, height: info.width)
      : (width: info.width, height: info.height);
}

/// [compressPhoto] off the UI thread.
Future<Uint8List> compressPhotoInBackground(Uint8List input) => Isolate.run(() => compressPhoto(input));
