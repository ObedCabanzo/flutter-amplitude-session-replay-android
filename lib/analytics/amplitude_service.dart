// lib/analytics/amplitude_service.dart
import 'dart:math';
import 'package:amplitude_flutter/constants.dart';
import 'package:flutter/services.dart';
import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:amplitude_flutter/default_tracking.dart';
import 'package:amplitude_flutter/events/base_event.dart';

class AmplitudeService {
  AmplitudeService._();
  static final AmplitudeService instance = AmplitudeService._();

  late final Amplitude _client;
  bool _analyticsReady = false;
  bool _srReady = false;

  // Canal nativo para Session Replay (tu plugin nativo debe implementarlo)
  static const _sr = MethodChannel('amplitude_session_replay');

  int? _lastSessionId;

  Future<void> init({
    required String apiKeyAnalytics,
    required String apiKeySessionReplay,
    bool eu = false,
    double sampleRate = 1.0,
    bool enableRemoteConfig = false,
  }) async {
    if (_analyticsReady) return;

    _client = Amplitude(
      Configuration(
        apiKey: apiKeyAnalytics,
        instanceName: 'main',
        // v4: defaultTracking controla sesiones y lifecycles
        defaultTracking: const DefaultTrackingOptions(
          sessions: true,
          appLifecycles: true,
        ),
        logLevel: LogLevel.debug,
        // Si tu proyecto es EU, usa serverZone.eu
        // serverZone: eu ? ServerZone.eu : ServerZone.us,
      ),
    );

    await _client.isBuilt;
    _analyticsReady = true;

    // No inicialices SR aquí a ciegas. Déjalo para cuando existan IDs.
    await _maybeInitSessionReplay(
      apiKeySessionReplay: apiKeySessionReplay,
      eu: eu,
      sampleRate: sampleRate,
      enableRemoteConfig: enableRemoteConfig,

    );
  }

  void _ensureAnalyticsReady() {
    if (!_analyticsReady) {
      throw StateError('AmplitudeService no inicializado. Llama a init() primero.');
    }
  }

  // Genera un deviceId válido (>=5 chars) si aún no existe
  String _generateFallbackDeviceId() {
    final r = Random();
    final hex = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
    return 'flutter-$hex';
  }

  // Intenta inicializar Session Replay cuando ya hay IDs válidos
  Future<void> _maybeInitSessionReplay({
    required String apiKeySessionReplay,
    required bool eu,
    required double sampleRate,
    required bool enableRemoteConfig,
  }) async {
    if (_srReady) return;

    // 1) Device ID
    var deviceId = await _client.getDeviceId();
    if (deviceId == null || deviceId.length < 5) {
      // fija uno de fallback y persiste
      deviceId = _generateFallbackDeviceId();
      await _client.setDeviceId(deviceId);
    }

    // 2) Session ID (puede tardar en estar disponible en el primer arranque)
    int? sessionId = await _client.getSessionId();

    // Haz un pequeño bootstrap si viene nulo
    if (sessionId == null || sessionId <= 0) {
      _client.track(BaseEvent('_sr_bootstrap')); // forzará creación de sesión
      // Espera breve y vuelve a consultar
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        sessionId = await _client.getSessionId();
        if (sessionId != null && sessionId > 0) break;
      }
    }

    // Si aún no hay sessionId, no bloquees la app; SR se intentará más tarde en track()
    if (sessionId == null || sessionId <= 0) {
      return;
    }

    try {
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
    } catch (e) {
      // No dejes caer la app por errores nativos; SR se reintenta en el próximo track()
      // print('SR init failed: $e');
    }
  }

  // Mantiene SR sincronizado si cambia el sessionId
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

  /// Track con propiedades de Session Replay si están disponibles.
  Future<void> track(String eventType, {Map<String, dynamic>? props}) async {
    _ensureAnalyticsReady();

    // Si SR aún no está listo, intenta inicializarlo ahora (no bloqueante si faltan IDs).
    if (!_srReady) {
      await _maybeInitSessionReplay(
        apiKeySessionReplay: '', // no re-envíes la key aquí; pásala en init() inicial
        eu: false,
        sampleRate: 1.0,
        enableRemoteConfig: true,
      );
    }

    // Sincroniza sessionId si SR ya está listo
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
    _ensureAnalyticsReady();
    _client.flush();
    if (_srReady) {
      _sr.invokeMethod('flush');
    }
  }

  Future<void> setUserId(String? userId) async {
    _ensureAnalyticsReady();
    await _client.setUserId(userId);
  }

  Future<void> setDeviceId(String deviceId) async {
    _ensureAnalyticsReady();
    await _client.setDeviceId(deviceId);
    if (_srReady) {
      try {
        await _sr.invokeMethod('updateIds', {'deviceId': deviceId});
      } catch (_) {}
    }
  }
}
