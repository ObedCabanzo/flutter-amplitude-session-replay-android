import 'dart:math';
import 'package:amplitude_flutter/constants.dart';
import 'package:experiment_sdk_flutter/experiment_client.dart';
import 'package:experiment_sdk_flutter/experiment_sdk_flutter.dart';
import 'package:experiment_sdk_flutter/types/experiment_config.dart';
import 'package:experiment_sdk_flutter/types/experiment_variant.dart';
import 'package:flutter/services.dart';
import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:amplitude_flutter/default_tracking.dart';
import 'package:amplitude_flutter/events/base_event.dart';

/// A singleton service for integrating Amplitude Analytics, Experiment, and Session Replay in Flutter.
///
/// This service handles initialization, event tracking, user/device/session management,
/// and native communication for Amplitude's Session Replay feature.
///
/// Usage:
///   - Call [init] once at app startup with the required API keys.
///   - Use [track] to log events, which will automatically include Session Replay properties if available.
///   - Use [getVariant] to fetch experiment variants for feature flags.
///   - Use [setUserId] and [setDeviceId] to update user and device identifiers.
///
/// Features:
///   - Ensures Amplitude Analytics and Session Replay are initialized only once.
///   - Handles fallback device ID generation if needed.
///   - Bootstraps session IDs for Session Replay if not immediately available.
///   - Synchronizes session and device IDs with the native Session Replay plugin.
///   - Provides safe error handling to avoid blocking the app on native errors.
///
/// Note:
///   - The native plugin for Session Replay must be implemented to handle the required method channels.
///   - Do not call [init] multiple times; use the singleton instance [AmplitudeService.instance].
class AmplitudeService {
  AmplitudeService._();
  static final AmplitudeService instance = AmplitudeService._();

  late final Amplitude _client;
  late final ExperimentClient _clientExp;
  bool _analyticsReady = false;
  bool _srReady = false;

  // Canal nativo para Session Replay (tu plugin nativo debe implementarlo)
  static const _sr = MethodChannel('amplitude_session_replay');

  int? _lastSessionId;

  Future<void> init({
    required String apiKeyAnalytics,
    required String apiKeySessionReplay,
    String apiKeyExperiment = '',
    bool eu = false,
    double sampleRate = 1.0,
    bool enableRemoteConfig = false,
    bool experiment = false,
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
    
    /// Initializes the Experiment client with Amplitude if the [experiment] flag is true and [apiKeyExperiment] is not empty.
    ///
    /// The client is configured with automatic exposure tracking enabled and uses "main" as the instance name. The instanceName could be ignored if not using amplitude analytics. And it could be initialized with the function initialize instead of initializeWithAmplitude if not using amplitude analytics.
    ///
    /// - [experiment]: A boolean flag indicating whether to initialize the Experiment client.
    /// - [apiKeyExperiment]: The API key used for initializing the Experiment client.
    /// - [_clientExp]: The Experiment client instance initialized with the provided API key and configuration.
    if (experiment && apiKeyExperiment.isNotEmpty) {
      _clientExp = Experiment.initializeWithAmplitude(
        apiKey: apiKeyExperiment,
        config: ExperimentConfig(
          automaticExposureTracking: true,
        ),
      );
    }

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

  // Create functions for get a variant given a flag key and an optional userId
  Future<ExperimentVariant?> getVariant(String flagKey) async {
    if (!_analyticsReady) {
      throw StateError(
        'AmplitudeService no inicializado. Llama a init() primero.',
      );
    }
    var deviceId = await _client.getDeviceId();
    await _clientExp.fetch(deviceId: deviceId);
    return _clientExp.variant(flagKey);
  }

  void _ensureAnalyticsReady() {
    if (!_analyticsReady) {
      throw StateError(
        'AmplitudeService no inicializado. Llama a init() primero.',
      );
    }
  }

  // Genera un deviceId válido (>=5 chars) si aún no existe
  String _generateFallbackDeviceId() {
    final r = Random();
    final hex =
        List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
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
        apiKeySessionReplay:
            '', // no re-envíes la key aquí; pásala en init() inicial
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

  Future<String?> getDeviceId() async {
    _ensureAnalyticsReady();
    return _client.getDeviceId();
  }

  Future<int?> getSessionId() async {
    _ensureAnalyticsReady();
    return _client.getSessionId();
  }

  // Get User ID
  Future<String?> getUserId() async {
    _ensureAnalyticsReady();
    return _client.getUserId();
  }
}
