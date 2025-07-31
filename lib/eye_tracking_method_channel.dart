import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'eye_tracking_platform_interface.dart';

/// An implementation of [EyeTrackingPlatform] that uses method channels.
class MethodChannelEyeTracking extends EyeTrackingPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('eye_tracking');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
