import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/app/tokens.dart';
import 'package:nfc_attendance/core/photo/camera_session.dart';
import 'package:nfc_attendance/core/photo/face_finder.dart';
import 'package:nfc_attendance/core/photo/punch_photo.dart';
import 'package:nfc_attendance/features/photo/photo_capture_screen.dart';

import '../../helpers/face_fixtures.dart';
import '../../helpers/localized.dart';
import '../../helpers/photo_fakes.dart';

void main() {
  late FakeCamera camera;
  late FakeFaceFinder faces;
  PunchPhoto? result;
  late bool popped;

  Future<void> open(
    WidgetTester tester, {
    List<FaceScan>? scans,
    Locale locale = const Locale('en'),
    bool canStream = true,
  }) async {
    camera = FakeCamera()..canStream = canStream;
    faces = FakeFaceFinder(scans ?? [goodScan]);
    result = null;
    popped = false;
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<PunchPhoto?>(
                MaterialPageRoute(
                  builder: (_) => PhotoCaptureScreen(camera: camera, faceFinder: faces, encode: fakeEncode),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
      locale: locale,
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route transition
  }

  testWidgets('3 s countdown then automatic capture; one face → returns the photo', (tester) async {
    await open(tester);
    expect(camera.opens, 1);
    expect(find.byKey(const Key('fake.preview')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    expect(camera.captures, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(camera.captures, 1);
    expect(popped, isTrue);
    expect(result!.faces, 1);
    expect(camera.discarded, ['/tmp/shot1.jpg'], reason: 'the raw camera file is deleted');
    expect(camera.closes, greaterThanOrEqualTo(1));
    expect(faces.closed, isTrue);
  });

  testWidgets('the shutter button captures at once', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('photo.shutter')));
    await tester.pumpAndSettle();
    expect(camera.captures, 1);
    expect(result, isNotNull);
  });

  testWidgets('no face → "No face found"; retry with one face succeeds', (tester) async {
    await open(tester, scans: [noFaceScan, goodScan]);
    await tester.tap(find.byKey(const Key('photo.shutter')));
    await tester.pump();
    await tester.pump();
    expect(find.text('No face found'), findsOneWidget);
    expect(popped, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(camera.captures, 1, reason: 'no automatic recapture after a failed check');

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(camera.captures, 2);
    expect(result, isNotNull);
  });

  testWidgets('two faces → "Only one face, please"', (tester) async {
    await open(tester, scans: [twoFacesScan]);
    await tester.tap(find.byKey(const Key('photo.shutter')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Only one face, please'), findsOneWidget);
    expect(popped, isFalse);
  });

  final rejections = {
    'half face at the edge': (halfFaceScan, 'Show your whole face in the frame'),
    'far face': (farFaceScan, 'Move closer'),
    'turned head': (turnedFaceScan, 'Face the camera'),
  };
  for (final MapEntry(key: name, value: (scan, message)) in rejections.entries) {
    testWidgets('$name → "$message", no photo, Try again retakes', (tester) async {
      await open(tester, scans: [scan, goodScan]);
      await tester.pump(const Duration(seconds: 3)); // automatic capture
      await tester.pump();
      await tester.pump();
      expect(camera.captures, 1);
      expect(find.text(message), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(popped, isFalse, reason: 'a rejected photo must not continue the tap');

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(camera.captures, 2);
      expect(result, isNotNull);
    });
  }

  testWidgets('half face → Arabic reason in Arabic', (tester) async {
    await open(tester, scans: [halfFaceScan], locale: const Locale('ar'));
    await tester.tap(find.byKey(const Key('photo.shutter')));
    await tester.pump();
    await tester.pump();
    expect(find.text('أظهر وجهك كاملًا داخل الإطار'), findsOneWidget);
    expect(popped, isFalse);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });

  /// One live preview frame that the finder judges as [scan]; the second
  /// pump draws the setState made when the scan completes.
  Future<void> liveFrame(WidgetTester tester, FaceScan scan) async {
    faces.frameScan = scan;
    camera.sendFrame();
    await tester.pump();
    await tester.pump();
  }

  Color guideColor(WidgetTester tester) {
    final guide = tester.widget<AnimatedContainer>(find.byKey(const Key('photo.face_guide')));
    return ((guide.decoration! as ShapeDecoration).shape as OvalBorder).side.color;
  }

  testWidgets('live guidance: the chip says what to fix, the oval turns green for a good face', (tester) async {
    await open(tester);
    expect(camera.streaming, isTrue, reason: 'preview frames stream during the countdown');
    expect(find.text('One face in view'), findsOneWidget, reason: 'instruction until a frame is checked');
    expect(guideColor(tester), TapInColors.surfaceRaised);

    await liveFrame(tester, halfFaceScan);
    expect(find.text('Show your whole face in the frame'), findsOneWidget);
    expect(find.byKey(const Key('photo.live_hint')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await liveFrame(tester, farFaceScan);
    expect(find.text('Move closer'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await liveFrame(tester, turnedFaceScan);
    expect(find.text('Face the camera'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await liveFrame(tester, goodScan);
    expect(find.text('Hold still'), findsOneWidget);
    expect(find.byKey(const Key('photo.live_ok')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250)); // oval colour animation
    expect(guideColor(tester), TapInColors.success);
    expect(popped, isFalse, reason: 'guidance never takes the photo by itself');

    await tester.pump(const Duration(seconds: 3)); // countdown ends
    await tester.pumpAndSettle();
    expect(camera.streaming, isFalse, reason: 'frames stop before the photo is taken');
    expect(camera.frameStops, 1);
    expect(result, isNotNull);
  });

  testWidgets('live guidance is advisory: a good preview does not pass a bad photo', (tester) async {
    await open(tester, scans: [halfFaceScan]);
    await liveFrame(tester, goodScan);
    expect(find.text('Hold still'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump();
    expect(find.text('Show your whole face in the frame'), findsOneWidget);
    expect(popped, isFalse);
    expect(guideColor(tester), TapInColors.surfaceRaised, reason: 'no green oval after a failed check');
  });

  testWidgets('live frames are throttled: one check at a time, then a 300 ms pause', (tester) async {
    await open(tester);
    faces.frameScan = goodScan;
    camera
      ..sendFrame()
      ..sendFrame();
    await tester.pump();
    camera.sendFrame();
    expect(faces.frameCalls, 1);
    await tester.pump(const Duration(milliseconds: 300));
    camera.sendFrame();
    await tester.pump();
    expect(faces.frameCalls, 2);
  });

  testWidgets('a failing frame check leaves the instruction; frames restart after Try again', (tester) async {
    await open(tester, scans: [noFaceScan, goodScan]);
    camera.sendFrame(); // frameScan not scripted → throws
    await tester.pump();
    expect(find.text('One face in view'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('photo.shutter')));
    await tester.pump();
    await tester.pump();
    expect(camera.streaming, isFalse);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(camera.streaming, isTrue);
    expect(camera.frameStarts, 2);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
  });

  testWidgets('a camera without frame streaming still takes and checks the photo', (tester) async {
    await open(tester, canStream: false);
    expect(find.text('One face in view'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(faces.frameCalls, 0);
  });

  testWidgets('Cancel returns no photo and stops the countdown', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(camera.captures, 0);
  });

  testWidgets('camera permission denied → explanation, Cancel still works', (tester) async {
    camera = FakeCamera(openError: const CameraUnavailable(CameraProblem.permissionDenied, 'denied'));
    faces = FakeFaceFinder([goodScan]);
    popped = false;
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<PunchPhoto?>(
              MaterialPageRoute(
                builder: (_) => PhotoCaptureScreen(camera: camera, faceFinder: faces, encode: fakeEncode),
              ),
            );
            popped = true;
          },
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.text('Camera access is needed for the attendance photo. Allow it in Settings.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result, isNull);
  });

  testWidgets('renders in Arabic, right-to-left', (tester) async {
    await open(tester, locale: const Locale('ar'));
    expect(Directionality.of(tester.element(find.byType(PhotoCaptureScreen))), TextDirection.rtl);
    expect(find.text('إلغاء'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
}
