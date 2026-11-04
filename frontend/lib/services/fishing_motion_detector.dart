import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// 钓鱼时使用陀螺仪监测手机转动（角速度单位：rad/s）。
///
/// 不能用陀螺仪可靠判断纯平移；本规则只针对明显旋转/晃动。
abstract interface class FishingMotionDetector {
  Future<void> start({
    required double threshold,
    required void Function() onExcessiveMotion,
  });

  Future<void> stop();
}

/// 真正监听手机陀螺仪；设备无传感器或订阅失败时会抛错，不会假装已开启监测。
class GyroscopeFishingMotionDetector implements FishingMotionDetector {
  StreamSubscription<GyroscopeEvent>? _subscription;
  bool _triggered = false;
  int _overThresholdSamples = 0;

  @override
  Future<void> start({
    required double threshold,
    required void Function() onExcessiveMotion,
  }) async {
    await stop();
    if (!threshold.isFinite || threshold <= 0) {
      throw ArgumentError.value(threshold, 'threshold', '必须为正数');
    }

    final firstSample = Completer<void>();
    _triggered = false;
    _overThresholdSamples = 0;
    _subscription = gyroscopeEventStream().listen((event) {
      if (!firstSample.isCompleted) firstSample.complete();
      if (_triggered) return;
      final speed = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (speed >= threshold) {
        _overThresholdSamples++;
        // 连续两帧超限才判定逃跑，降低单帧传感器尖峰误报。
        if (_overThresholdSamples >= 2) {
          _triggered = true;
          onExcessiveMotion();
        }
      } else {
        _overThresholdSamples = 0;
      }
    }, onError: (Object error, StackTrace stack) {
      if (!firstSample.isCompleted) {
        firstSample.completeError(StateError('陀螺仪不可用：$error'), stack);
      } else if (!_triggered) {
        _triggered = true;
        onExcessiveMotion(); // 中途失去传感器时停止计时，不能无检测继续领奖。
      }
    }, cancelOnError: true);

    try {
      await firstSample.future.timeout(const Duration(seconds: 4),
          onTimeout: () => throw StateError('未收到陀螺仪数据，请使用带陀螺仪的真机'));
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final current = _subscription;
    _subscription = null;
    _overThresholdSamples = 0;
    if (current != null) await current.cancel();
  }
}
