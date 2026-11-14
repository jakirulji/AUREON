import 'dart:io';

import 'package:flutter/services.dart';

/// App-scoped network diagnostics. Android may restrict an app's mobile or
/// background data independently of the device-wide network connection.
class AureonNetworkAccess {
  AureonNetworkAccess._();

  static const MethodChannel _channel = MethodChannel('aureon/network_access');
  static const String firebaseAuthHost = 'identitytoolkit.googleapis.com';
  static bool get isAndroid => Platform.isAndroid;

  /// A response of any HTTP status (including 404) proves DNS, TLS and
  /// outbound HTTPS connectivity to Firebase Authentication are working.
  static Future<bool> canReachFirebase({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.https(firebaseAuthHost, '/'))
          .timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      return true;
    } on IOException {
      return false;
    } on Exception {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Opens Android's app-specific settings page. The user remains in control
  /// of Mobile data, Background data and Unrestricted data access switches.
  static Future<void> openAppSettings() async {
    await _channel.invokeMethod<void>('openAppSettings');
  }

  /// Returns Android ConnectivityManager diagnostics when available.
  static Future<Map<Object?, Object?>?> getAndroidStatus() async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>('getNetworkStatus');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
