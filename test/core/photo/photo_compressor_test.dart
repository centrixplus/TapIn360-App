import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nfc_attendance/core/photo/photo_compressor.dart';

Uint8List jpeg(int width, int height, {bool noise = false, int? orientation}) {
  final image = img.Image(width: width, height: height);
  final random = Random(7);
  for (final p in image) {
    if (noise) {
      p
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    } else {
      p
        ..r = (p.x * 255 ~/ width)
        ..g = (p.y * 255 ~/ height)
        ..b = 128;
    }
  }
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(image, quality: 95);
}

img.Image decode(Uint8List bytes) => img.decodeJpg(bytes)!;

void main() {
  test('landscape camera frame → 640 px long side, JPEG', () {
    final out = compressPhoto(jpeg(1280, 720));
    expect(out.sublist(0, 2), [0xFF, 0xD8], reason: 'JPEG magic');
    final image = decode(out);
    expect(image.width, 640);
    expect(image.height, 360);
  });

  test('portrait frame → 640 px on the long (vertical) side', () {
    final image = decode(compressPhoto(jpeg(720, 1280)));
    expect(image.width, 360);
    expect(image.height, 640);
  });

  test('small images are not upscaled', () {
    final image = decode(compressPhoto(jpeg(320, 240)));
    expect(image.width, 320);
    expect(image.height, 240);
  });

  test('EXIF rotation is applied before resizing', () {
    final image = decode(compressPhoto(jpeg(800, 400, orientation: 6)));
    expect(image.width, 320);
    expect(image.height, 640);
  });

  test('a typical frame is far below the 1 MB server limit', () {
    final out = compressPhoto(jpeg(1280, 720));
    expect(out.length, lessThan(maxPhotoBytes));
  });

  test('lowers quality until the photo fits the byte limit', () {
    final noisy = jpeg(640, 640, noise: true);
    final atDefault = compressPhoto(noisy);
    final limit = atDefault.length * 2 ~/ 3;
    final out = compressPhoto(noisy, maxBytes: limit);
    expect(out.length, lessThanOrEqualTo(limit));
  });

  test('throws when even the lowest quality is too big', () {
    expect(() => compressPhoto(jpeg(640, 640, noise: true), maxBytes: 1000), throwsA(isA<PhotoTooLarge>()));
  });

  test('throws on bytes that are not an image', () {
    expect(() => compressPhoto(Uint8List.fromList([1, 2, 3, 4])), throwsFormatException);
  });

  group('jpegUprightSize', () {
    test('reads the size from the JPEG headers', () {
      expect(jpegUprightSize(jpeg(480, 640)), (width: 480, height: 640));
      expect(jpegUprightSize(jpeg(640, 360)), (width: 640, height: 360));
    });

    test('EXIF rotation 5–8 swaps the sides, as ML Kit turns the image upright', () {
      expect(jpegUprightSize(jpeg(640, 480, orientation: 6)), (width: 480, height: 640));
      expect(jpegUprightSize(jpeg(640, 480, orientation: 8)), (width: 480, height: 640));
      expect(jpegUprightSize(jpeg(640, 480, orientation: 3)), (width: 640, height: 480));
    });

    test('the compressed upload photo is already upright', () {
      final out = compressPhoto(jpeg(1280, 720, orientation: 6));
      expect(jpegUprightSize(out), (width: 360, height: 640));
    });

    test('bytes that are not a JPEG → FormatException', () {
      expect(() => jpegUprightSize(Uint8List.fromList([1, 2, 3, 4])), throwsFormatException);
    });
  });
}
