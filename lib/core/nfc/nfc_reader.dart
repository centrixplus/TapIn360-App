import 'dart:convert';
import 'dart:io' show Platform;

import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'card_uid.dart';

/// Thin wrapper over nfc_manager 4.2.1.
/// Android: reader mode stays on until [stop] (and while it is on, Android does
/// not dispatch the card's NDEF to the browser). The OS turns reader mode off
/// when the activity pauses, so callers restart it on resume.
/// iOS: shows the system sheet and ends after one read.
class NfcReader {
  Future<NfcAvailability> availability() => NfcManager.instance.checkAvailability();

  Future<void> start({
    required Future<void> Function(NfcTag tag) onTag,
    required void Function(String message) onError,
    String alertMessageIos = 'Hold your iPhone near the card',
    void Function()? onCancelIos,
  }) {
    return NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      alertMessageIos: alertMessageIos,
      onDiscovered: (tag) async {
        try {
          await onTag(tag);
        } catch (e) {
          onError(e.toString());
        }
      },
      onSessionErrorIos: (error) {
        if (_isCancel(error.code)) {
          onCancelIos?.call();
        } else {
          onError(error.message);
        }
      },
    );
  }

  /// iOS: [alertMessageIos] / [errorMessageIos] are shown as the sheet closes.
  Future<void> stop({String? alertMessageIos, String? errorMessageIos}) =>
      NfcManager.instance.stopSession(alertMessageIos: alertMessageIos, errorMessageIos: errorMessageIos);

  static bool _isCancel(NfcReaderErrorCodeIos code) =>
      code == NfcReaderErrorCodeIos.readerSessionInvalidationErrorUserCanceled ||
      code == NfcReaderErrorCodeIos.readerSessionInvalidationErrorSessionTimeout ||
      code == NfcReaderErrorCodeIos.readerSessionInvalidationErrorFirstNDEFTagRead;
}

/// The tag's UID (`04DB8FE23B1590`), or null if the platform exposes none.
String? uidOf(NfcTag tag) {
  if (Platform.isAndroid) {
    final id = NfcTagAndroid.from(tag)?.id;
    return (id == null || id.isEmpty) ? null : formatCardUid(id);
  }
  if (Platform.isIOS) {
    final id = MiFareIos.from(tag)?.identifier;
    return (id == null || id.isEmpty) ? null : formatCardUid(id);
  }
  return null;
}

/// Android-only debug text: technologies and NDEF record types on the tag.
String describeTag(NfcTag tag) {
  if (!Platform.isAndroid) return '';
  final techs = NfcTagAndroid.from(tag)?.techList.map((t) => t.split('.').last).join('/') ?? '?';
  final records = NdefAndroid.from(tag)?.cachedNdefMessage?.records ?? const <NdefRecord>[];
  final types = records
      .map((r) => '${r.typeNameFormat.name}:${ascii.decode(r.type, allowInvalid: true)}')
      .join(', ');
  return 'tech=$techs ndef=[$types]';
}
