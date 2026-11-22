import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef StubHandler = FutureOr<ResponseBody> Function(RequestOptions request);

/// Dio adapter that answers from [handler] and records every request.
class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.handler);

  StubHandler handler;
  final requests = <RequestOptions>[];

  /// Decoded JSON body of request [i] (requests send a JSON string).
  Map<String, Object?> bodyOf(int i) => jsonDecode(requests[i].data as String) as Map<String, Object?>;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(int status, Object body, {Map<String, List<String>>? headers}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...?headers,
    },
  );
}

ResponseBody textResponse(int status, String body, {Map<String, List<String>>? headers}) {
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['text/html'],
      ...?headers,
    },
  );
}

Map<String, Object?> errorBody(String code, String message, [Map<String, Object?> extra = const {}]) {
  return {
    'error': {'code': code, 'message': message, ...extra},
  };
}
