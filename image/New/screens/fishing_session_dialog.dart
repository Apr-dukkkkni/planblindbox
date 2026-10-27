import 'dart:async';

import 'package:flutter/material.dart';

import '../data/stats_api.dart';
import '../services/fishing_motion_detector.dart';
import '../theme/app_theme.dart';

/// 前台钓鱼会话。应用进入后台时立即停止计时，不保活、不启动后台服务。
class FishingSessionDialog extends StatefulWidget {
  const FishingSessionDialog({super.key, required this.api});

  final StatsApi api;

  @override
  State<FishingSessionDialog> createState() => _FishingSessionDialogState();
}

class _FishingSessionDialogState extends State<FishingSessionDialog>
    with WidgetsBindingObserver {
  // 正常默认每 30 分钟钓到一条鱼；可通过 dart-define 缩短开发测试时间。
  static const int _configuredCatchMinutes =
      int.fromEnvironment('FISHING_CATCH_MINUTES', defaultValue: 30);
  static const Duration _catchInterval = Duration(
    minutes: _configuredCatchMinutes > 0 ? _configuredCatchMinutes : 30,
  );

  // 仅为未来的传感器实现预留的参数；当前占位检测器不会使用它。
  static const double _motionThreshold = 2.0;

  final FishingMotionDetector _motionDetector = NoopFishingMotionDetector();
  Timer? _ticker;
  DateTime? _attemptStart;
  DateTime? _segmentStart;
  Duration _attemptElapsed = Duration.zero;
  Duration _segmentElapsed = Duration.zero;
  int _fishCaught = 0;
  bool _active = false;
  bool _escaped = false;
  bool _ending = false;
  bool _closing = false;
  bool _processingCatch = false;
  String _statusMessage = '正在准备鱼竿……';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startFishing());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _active) {
      unawaited(_endFishing(
        reason: '应用进入后台，鱼被吓跑了。返回后可以重新钓鱼。',
        savePartial: true,
      ));
    }
  }

  Future<void> _startFishing() async {
    if (_active || _ending || !mounted) return;
    final now = DateTime.now();
    setState(() {
      _active = true;
      _escaped = false;
      _attemptStart = now;
      _segmentStart = now;
      _attemptElapsed = Duration.zero;
      _segmentElapsed = Duration.zero;
      _statusMessage = '鱼竿已抛出，请保持手机稳定。每持续钓鱼 ${_catchInterval.inMinutes} 分钟可获得一条鱼。';
    });

    try {
      await _motionDetector.start(
        threshold: _motionThreshold,
        onExcessiveMotion: () {
          unawaited(_endFishing(
            reason: '手机晃动超过阈值，鱼被吓跑了。请重新开始钓鱼。',
            savePartial: true,
          ));
        },
      );
    } catch (error) {
      if (mounted && _active) {
        setState(() => _statusMessage = '运动检测接口启动失败：$error');
      }
    }

    if (!mounted || !_active) return;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!_active || _attemptStart == null || _segmentStart == null) return;
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _attemptElapsed = now.difference(_attemptStart!);
        _segmentElapsed = now.difference(_segmentStart!);
      });
    }
    if (!_processingCatch && _segmentElapsed >= _catchInterval) {
      unawaited(_processDueCatches(now));
    }
  }

  Future<void> _processDueCatches(DateTime now) async {
    if (_processingCatch || !_active || _segmentStart == null) return;
    _processingCatch = true;
    try {
      while (_active && _segmentStart != null) {
        final start = _segmentStart!;
        final catchTime = start.add(_catchInterval);
        if (catchTime.isAfter(now)) break;

        final fishNumber = _fishCaught + 1;
        setState(() {
          _fishCaught = fishNumber;
          _segmentStart = catchTime;
          _segmentElapsed = now.difference(catchTime);
          _statusMessage = '🎉 钓到第 $fishNumber 条鱼！继续保持安静，等待下一条鱼。';
        });

        final saved = await _saveTimeRange(
          start,
          catchTime,
          title: '钓鱼（鱼获第${fishNumber}条）',
          note: '连续钓鱼满 ${_catchInterval.inMinutes} 分钟，获得第 $fishNumber 条鱼。',
        );
        if (!saved && mounted) {
          setState(() => _statusMessage =
              '钓到第 $fishNumber 条鱼了，但时间记录保存失败，请检查后端连接。');
        }
      }
    } finally {
      _processingCatch = false;
    }
  }

  Future<void> _endFishing({
    required String reason,
    required bool savePartial,
  }) async {
    if (!_active || _ending) return;
    _ending = true;
    final start = _segmentStart;
    final end = DateTime.now();
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _active = false;
      _escaped = true;
      _statusMessage = reason;
    });

    await _motionDetector.stop();
    var saved = true;
    if (savePartial && start != null && end.difference(start).inMinutes >= 1) {
      saved = await _saveTimeRange(
        start,
        end,
        title: '钓鱼（鱼跑了）',
        note: '$reason 本段未获得鱼，已保存实际钓鱼时长。',
      );
    }
    if (mounted) {
      setState(() {
        if (!saved) _statusMessage = '$reason（时间记录保存失败，请检查后端连接。）';
        _ending = false;
      });
    } else {
      _ending = false;
    }
  }

  Future<bool> _saveTimeRange(
    DateTime start,
    DateTime end, {
    required String title,
    required String note,
  }) async {
    if (!end.isAfter(start)) return true;
    var cursor = start;
    try {
      while (cursor.isBefore(end)) {
        final boundary = _nextBusinessBoundary(cursor);
        final pieceEnd = end.isBefore(boundary) ? end : boundary;
        // 后端要求每条记录至少一分钟，并且不能跨凌晨 05:00 的业务日边界。
        if (pieceEnd.difference(cursor).inMinutes >= 1) {
          final isLastPiece = !pieceEnd.isBefore(end);
          await widget.api.createTimeRecord(
            title: isLastPiece ? title : '钓鱼（跨业务日分段）',
            category: '休闲',
            startTime: cursor,
            endTime: pieceEnd,
            note: isLastPiece ? note : '钓鱼计时分段，按凌晨 05:00 业务日边界拆分。',
          );
        }
        cursor = pieceEnd;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  DateTime _nextBusinessBoundary(DateTime value) {
    final todayAtFive = DateTime(value.year, value.month, value.day, 5);
    if (value.isBefore(todayAtFive)) return todayAtFive;
    return DateTime(value.year, value.month, value.day + 1, 5);
  }

  Future<void> _leaveFishing() async {
    if (_closing) return;
    _closing = true;
    if (_active) {
      await _endFishing(
        reason: '你收竿离开了，鱼被吓跑了。',
        savePartial: true,
      );
    }
    if (mounted) Navigator.of(context).pop(_fishCaught);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    unawaited(_motionDetector.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _catchInterval - _segmentElapsed;
    final clampedRemaining = remaining.isNegative ? Duration.zero : remaining;
    final progress = (_segmentElapsed.inSeconds / _catchInterval.inSeconds)
        .clamp(0.0, 1.0)
        .toDouble();

    return PopScope<Object?>(
      canPop: (!_active && !_ending) || _closing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _active) unawaited(_leaveFishing());
      },
      child: AlertDialog(
        title: const Row(children: [
          Icon(Icons.set_meal_rounded, color: AppColors.forest),
          SizedBox(width: 9),
          Text('钓鱼'),
        ]),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5EF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [
                  Icon(
                    _active ? Icons.waves_rounded : Icons.set_meal_rounded,
                    size: 46,
                    color: AppColors.forest,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _active ? '静静等待鱼儿上钩' : (_escaped ? '鱼跑掉了' : '准备钓鱼'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _active ? _formatDuration(_attemptElapsed) : '本次钓鱼已暂停',
                    style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _active ? progress : 0),
                  const SizedBox(height: 7),
                  Text(
                    _active ? '距离下一条鱼：${_formatDuration(clampedRemaining)}' : '已钓获 $_fishCaught 条鱼',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.vibration, size: 17, color: AppColors.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '陀螺仪检测接口已预留，当前未开启传感器监听。',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _escaped ? const Color(0xFFFFF2E8) : const Color(0xFFF7F8F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_statusMessage, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        actions: [
          if (!_active && _escaped)
            FilledButton.icon(
              onPressed: _ending ? null : _startFishing,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('重新钓鱼'),
            ),
          TextButton(
            onPressed: _closing || _ending ? null : _leaveFishing,
            child: Text(_active ? '收竿离开' : '关闭'),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
