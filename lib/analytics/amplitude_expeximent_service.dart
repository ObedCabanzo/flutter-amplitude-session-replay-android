// amplitude_experiment_service.dart
import 'package:experiment_sdk_flutter/experiment_client.dart';
import 'package:experiment_sdk_flutter/experiment_sdk_flutter.dart';
import 'package:experiment_sdk_flutter/types/experiment_config.dart';
import 'package:experiment_sdk_flutter/types/experiment_variant.dart';
import 'package:flutter_application_3/models/feature_flags.dart';

import 'amplitude_analytics_service.dart';

/// Singleton SOLO para Amplitude Experiment (feature flags / variantes).
class AmplitudeExperimentService {
  AmplitudeExperimentService._();
  static final AmplitudeExperimentService instance = AmplitudeExperimentService._();

  ExperimentClient? _client;
  bool _ready = false;
  bool _usesAmplitudeIntegration = true;
  bool _automaticExposureTracking = true;

  bool get isReady => _ready;

  Future<void> init({
    required String apiKeyExperiment,
    bool automaticExposureTracking = true,
    bool useAmplitudeIntegration = true,
    String? userId,
    String? deviceId,
  }) async {
    if (_ready) return;

    _usesAmplitudeIntegration = useAmplitudeIntegration;
    _automaticExposureTracking = automaticExposureTracking;

    if (useAmplitudeIntegration) {
      // Requiere que Analytics ya esté inicializado.
      if (!AmplitudeAnalyticsService.instance.isReady) {
        throw StateError(
          'Debe inicializar primero AmplitudeAnalyticsService antes de usar Experiment con integración.',
        );
      }
      _client = Experiment.initializeWithAmplitude(
        apiKey: apiKeyExperiment,
        config: ExperimentConfig(
          automaticExposureTracking: automaticExposureTracking,
          debug: true,
        ),
      );
    } else {
      _client = Experiment.initialize(
        apiKey: apiKeyExperiment,
        config: ExperimentConfig(
          automaticExposureTracking: automaticExposureTracking,
          debug: true,
        ),
      );
    }

    _ready = true;
  }

  void _ensureReady() {
    if (!_ready || _client == null) {
      throw StateError('AmplitudeExperimentService no inicializado. Llama init() primero.');
    }
  }

  Future<TypedVariant<V, P>> getVariant<V extends Enum, P>(
    FlagDefinition<V, P> def, {
    bool fetch = true,
    String? overrideDeviceId,
    String? overrideUserId,
    bool trackExposure = true,
  }) async {
    _ensureReady();

    String? deviceId = overrideDeviceId;
    String? userId = overrideUserId;

    if (deviceId == null && _usesAmplitudeIntegration) {
      deviceId = await AmplitudeAnalyticsService.instance.getDeviceId();
    }

    if (userId == null && _usesAmplitudeIntegration) {
      userId = await AmplitudeAnalyticsService.instance.getUserId();
      print("User ID from AmplitudeAnalyticsService: $userId");
    }


    if (fetch) {
      await _client!.fetch(deviceId: deviceId, userId: userId);
    }
    
    final ExperimentVariant? raw = _client!.variant(def.key); 
    print("Raw variant for '${def.key}': $raw");
    final V variantEnum = def.mapToEnum(raw?.value);
    P payloadParsed;

    try {
      payloadParsed = def.parsePayload(raw?.payload);
      // Si hay validador y falla, usa fallback.
      if (def.validate != null && !def.validate!(variantEnum, payloadParsed)) {
        payloadParsed = def.defaultPayload;
      }
    } catch (_) {
      payloadParsed = def.defaultPayload;
    }

    // Exposición: solo si no está auto-tracking y el caller lo pide.
    if (trackExposure && !_automaticExposureTracking) {
      try {
        await _client!.exposure(def.key);
      } catch (_) {
        // ignora errores de tracking de exposición
      }
    }

    return TypedVariant<V, P>(
      key: def.key,
      variant: variantEnum,
      payload: payloadParsed,
      raw: raw,
    );
  }

  /// ===== API original (RAW) opcional si necesitas compatibilidad =====
  /// Obtiene una variante cruda (sin tipado) haciendo fetch previo.
  Future<ExperimentVariant?> getVariantRaw(String flagKey) async {
    _ensureReady();

    String? deviceId;
    if (_usesAmplitudeIntegration) {
      deviceId = await AmplitudeAnalyticsService.instance.getDeviceId();
    }
    await _client!.fetch(deviceId: deviceId);
    return _client!.variant(flagKey);
  }

  /// Retorna todas las variantes actuales (sin forzar fetch).
  Map<String, ExperimentVariant> getAllCached() {
    _ensureReady();
    return _client!.all();
  }

  /// Fuerza un fetch manual (por ejemplo previo a un batch de lecturas).
  Future<void> refresh({String? overrideDeviceId}) async {
    _ensureReady();
    String? deviceId = overrideDeviceId;
    if (deviceId == null && _usesAmplitudeIntegration) {
      deviceId = await AmplitudeAnalyticsService.instance.getDeviceId();
    }
    await _client!.fetch(deviceId: deviceId);
  }
}