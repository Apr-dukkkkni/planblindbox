/// 钓鱼过程的运动检测抽象。
///
/// 当前版本故意不订阅陀螺仪/加速度计事件，避免尚未在真机验证前持续监听传感器。
/// 真机调试时可新增实现类，在超过阈值时调用 onExcessiveMotion。
abstract interface class FishingMotionDetector {
  Future<void> start({
    required double threshold,
    required void Function() onExcessiveMotion,
  });

  Future<void> stop();
}

/// 暂时不做传感器监听的占位实现。
class NoopFishingMotionDetector implements FishingMotionDetector {
  @override
  Future<void> start({
    required double threshold,
    required void Function() onExcessiveMotion,
  }) async {
    // 预留接口：手机陀螺仪实测后，再在这里替换为真正的运动检测实现。
  }

  @override
  Future<void> stop() async {
    // 当前没有启动传感器订阅，无需清理。
  }
}
