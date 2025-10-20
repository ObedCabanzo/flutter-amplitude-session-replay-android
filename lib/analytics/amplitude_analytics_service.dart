import 'dart:math';
import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:amplitude_flutter/constants.dart';
import 'package:amplitude_flutter/default_tracking.dart';
import 'package:amplitude_flutter/events/base_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_3/analytics/amplitude_expeximent_service.dart';

/// Singleton encargado SOLO de Amplitude Analytics + Session Replay.
class AmplitudeAnalyticsService {
  AmplitudeAnalyticsService._();
  static final AmplitudeAnalyticsService instance = AmplitudeAnalyticsService._();

  late final Amplitude _client;
  bool _analyticsReady = false;

  // Session Replay
  bool _srReady = false;
  static const _sr = MethodChannel('amplitude_session_replay');
  int? _lastSessionId;

  bool get isReady => _analyticsReady;

  Future<void> init({
    required String apiKeyAnalytics,
    String apiKeySessionReplay = '',
    bool eu = false,
    double sampleRate = 1.0,
    bool enableRemoteConfig = false,
    LogLevel logLevel = LogLevel.debug,
  }) async {
    if (_analyticsReady) return;

    _client = Amplitude(
      Configuration(
        apiKey: apiKeyAnalytics,
        defaultTracking: const DefaultTrackingOptions(
          sessions: true,
          appLifecycles: true,
        ),
        logLevel: logLevel,
        // serverZone: eu ? ServerZone.eu : ServerZone.us,
      ),
    );

    await _client.isBuilt;
    _analyticsReady = true;
    if (apiKeySessionReplay.isNotEmpty) {
      await _maybeInitSessionReplay(
        apiKeySessionReplay: apiKeySessionReplay,
        eu: eu,
        sampleRate: sampleRate,
        enableRemoteConfig: enableRemoteConfig,
      );
    }
  }

  void _ensureReady() {
    if (!_analyticsReady) {
      throw StateError('AmplitudeAnalyticsService no inicializado. Llama init() primero.');
    }
  }

  // Public helpers
  Future<String?> getDeviceId() async {
    _ensureReady();
    return _client.getDeviceId();
  }

  Future<int?> getSessionId() async {
    _ensureReady();
    return _client.getSessionId();
  }

  Future<void> setUserId(String? userId) async {
    _ensureReady();
    await _client.setUserId(userId);

    // Tras cambiar userId, refrescar flags de Experiment (si está listo)
    try {
      final exp = AmplitudeExperimentService.instance;
      if (exp.isReady) {
        await exp.refresh(); // hace fetch de variantes con la nueva identidad
      }
    } catch (_) {
      // silencioso
    }
  }

  Future<void> track(String eventType, {Map<String, dynamic>? props}) async {
    _ensureReady();

    if (!_srReady) {
      // Re-intento silencioso (sin apiKey aquí)
      await _maybeInitSessionReplay(
        apiKeySessionReplay: '',
        eu: false,
        sampleRate: 1.0,
        enableRemoteConfig: true,
      );
    }

    await _syncReplaySessionIdIfChanged();

    Map<String, dynamic> srProps = const {};
    if (_srReady) {
      try {
        final m = await _sr.invokeMethod<Map>('getProperties');
        srProps = m == null ? const {} : Map<String, dynamic>.from(m);
      } catch (_) {
        srProps = const {};
      }
    }

    _client.track(
      BaseEvent(
        eventType,
        eventProperties: {if (props != null) ...props, ...srProps},
      ),
    );
  }

  void flush() {
    _ensureReady();
    _client.flush();
    if (_srReady) {
      _sr.invokeMethod('flush');
    }
  }

  // ----- Session Replay internals -----
  String _generateFallbackDeviceId() {
    final r = Random();
    final hex = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
    return 'flutter-$hex';
  }

  Future<void> _maybeInitSessionReplay({
    required String apiKeySessionReplay,
    required bool eu,
    required double sampleRate,
    required bool enableRemoteConfig,
  }) async {
    if (_srReady) return;

    var deviceId = await _client.getDeviceId();
    if (deviceId == null || deviceId.length < 5) {
      deviceId = _generateFallbackDeviceId();
      await _client.setDeviceId(deviceId);
    }

    int? sessionId = await _client.getSessionId();
    if (sessionId == null || sessionId <= 0) {
      _client.track(BaseEvent('_sr_bootstrap'));
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        sessionId = await _client.getSessionId();
        if (sessionId != null && sessionId > 0) break;
      }
    }
    if (sessionId == null || sessionId <= 0) return;

    try {
      // Si apiKeySessionReplay está vacío (reintento), evita llamar init sin apiKey.
      if (apiKeySessionReplay.isEmpty) return;

      await _sr.invokeMethod('init', {
        'apiKey': apiKeySessionReplay,
        'deviceId': deviceId,
        'sessionId': sessionId,
        'sampleRate': sampleRate,
        'eu': eu,
        'enableRemoteConfig': enableRemoteConfig,
      });
      _lastSessionId = sessionId;
      _srReady = true;
    } catch (_) {
      // Silencioso
    }
  }

  Future<void> _syncReplaySessionIdIfChanged() async {
    if (!_srReady) return;
    final current = await _client.getSessionId();
    if (current != null && current > 0 && _lastSessionId != current) {
      _lastSessionId = current;
      try {
        await _sr.invokeMethod('updateIds', {'sessionId': current});
      } catch (_) {}
    }
  }

  // Get user id 
  Future<String?> getUserId() async {
    _ensureReady();
    return await _client.getUserId();
  }
}