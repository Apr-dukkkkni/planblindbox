import 'dart:math';

/// Ephemeral capability session. Never serialize this object or place it in a backup.
class ModRuntimeSession {
  const ModRuntimeSession._({
    required this.sessionId,
    required this.ownerId,
    required this.installationId,
    required this.modId,
    required this.generation,
    required this.verifiedRuntime,
    required this.createdAt,
    required this.expiresAt,
  });

  final String sessionId;
  final int ownerId;
  final String installationId;
  final String modId;
  final int generation;
  /// True only when the session was opened by the host Declarative Runtime
  /// after the installation/package content was validated.
  final bool verifiedRuntime;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// Process-local session registry. Any install mutation invalidates old sessions.
class ModRuntimeSessionManager {
  ModRuntimeSessionManager({
    DateTime Function()? clock,
    Random? random,
    this.sessionLifetime = const Duration(minutes: 15),
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static final ModRuntimeSessionManager instance = ModRuntimeSessionManager();

  final DateTime Function() _clock;
  final Random _random;
  final Duration sessionLifetime;
  final Map<String, ModRuntimeSession> _activeByInstallation = {};
  final Map<String, int> _generationByInstallation = {};

  DateTime get _now => _clock().toUtc();

  ModRuntimeSession open({
    required int ownerId,
    required String installationId,
    required String modId,
    bool verifiedRuntime = false,
  }) {
    final generation = _generationByInstallation[installationId] ?? 0;
    final now = _now;
    final session = ModRuntimeSession._(
      sessionId: _randomToken(),
      ownerId: ownerId,
      installationId: installationId,
      modId: modId,
      generation: generation,
      verifiedRuntime: verifiedRuntime,
      createdAt: now,
      expiresAt: now.add(sessionLifetime),
    );
    _activeByInstallation[installationId] = session;
    return session;
  }

  bool isActive(ModRuntimeSession session) {
    final active = _activeByInstallation[session.installationId];
    return active != null &&
        active.sessionId == session.sessionId &&
        active.ownerId == session.ownerId &&
        active.modId == session.modId &&
        active.generation == session.generation &&
        session.generation ==
            (_generationByInstallation[session.installationId] ?? 0) &&
        session.expiresAt.isAfter(_now);
  }

  void terminateInstallation(String installationId) {
    _activeByInstallation.remove(installationId);
    _generationByInstallation[installationId] =
        (_generationByInstallation[installationId] ?? 0) + 1;
  }

  void terminateOwner(int ownerId) {
    final installationIds = _activeByInstallation.values
        .where((session) => session.ownerId == ownerId)
        .map((session) => session.installationId)
        .toList(growable: false);
    for (final installationId in installationIds) {
      terminateInstallation(installationId);
    }
  }

  void terminateAll() {
    final installationIds = _activeByInstallation.keys.toList(growable: false);
    for (final installationId in installationIds) {
      terminateInstallation(installationId);
    }
  }

  String _randomToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
