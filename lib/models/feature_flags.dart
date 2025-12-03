// feature_flags.dart
import 'package:experiment_sdk_flutter/types/experiment_variant.dart';

/// Resultado tipado que envuelve el ExperimentVariant crudo.
class TypedVariant<V extends Enum, P> {
  final String key;
  final V variant;
  final P payload;
  final ExperimentVariant? raw;

  const TypedVariant({
    required this.key,
    required this.variant,
    required this.payload,
    required this.raw,
  });

  @override
  String toString() => 'TypedVariant<$V, $P>(key: $key, variant: $variant, payload: $payload)';
}

/// Parser/validator para payloads.
typedef PayloadParser<P> = P Function(Map<String, dynamic>? json);
typedef PayloadValidator<V extends Enum, P> = bool Function(V variant, P payload);

/// Definición de un feature flag (clave, variantes, payloads, defaults).
class FlagDefinition<V extends Enum, P> {
  final String key;
  /// Mapa de valor de variante (string de Amplitude, ej. "control", "enabled") -> enum V.
  final Map<String, V> variants;
  final V defaultVariant;

  /// Parser de payload (recibe el `payload` del ExperimentVariant como Map).
  final PayloadParser<P> parsePayload;
  final P defaultPayload;

  /// (Opcional) Validador lógico del payload en función de la variante.
  final PayloadValidator<V, P>? validate;

  /// Si quieres forzar a que variantes desconocidas caigan SIEMPRE al default.
  final bool strictVariants;

  const FlagDefinition({
    required this.key,
    required this.variants,
    required this.defaultVariant,
    required this.parsePayload,
    required this.defaultPayload,
    this.validate,
    this.strictVariants = true,
  });

  V mapToEnum(String? rawValue) {
    if (rawValue == null) return defaultVariant;
    final v = variants[rawValue.trim().toLowerCase()];
    if (v != null) return v;
    return strictVariants ? defaultVariant : (variants.values.first);
  }
}

enum BannerHomeVariant { off, abajo, medio }

class BannerHomePayload {
  final String color;
  final String message;
  const BannerHomePayload({required this.color, required this.message});
  static BannerHomePayload fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BannerHomePayload(color: 'red', message: 'Default banner message');
    return BannerHomePayload(
      color: (json['color'] as String?) ?? 'red',
      message: (json['message'] as String?) ?? 'Default banner message',
    );
  }
}

final FlagDefinition<BannerHomeVariant, BannerHomePayload> bannerHomeFlag =
    FlagDefinition<BannerHomeVariant, BannerHomePayload>(
  key: 'banner-home',
  variants: const {
    'off': BannerHomeVariant.off,
    'abajo': BannerHomeVariant.abajo,
    'medio': BannerHomeVariant.medio,
  },
  defaultVariant: BannerHomeVariant.off,
  parsePayload: BannerHomePayload.fromJson,
  defaultPayload: const BannerHomePayload(color: 'red', message: 'Default banner message'),
);



/// Registro central opcional para descubrir flags por key si lo necesitas.
class FeatureFlagRegistry {
  static final Map<String, FlagDefinition<dynamic, dynamic>> all = {
    bannerHomeFlag.key: bannerHomeFlag,
  };

  static FlagDefinition<V, P>? get<V extends Enum, P>(String key) {
    final def = all[key];
    if (def is FlagDefinition<V, P>) return def;
    return null;
  }
}