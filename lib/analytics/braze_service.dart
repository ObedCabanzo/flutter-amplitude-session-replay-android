import 'package:braze_plugin/braze_plugin.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class BrazeService {
  BrazeService._();
  static final BrazeService instance = BrazeService._();

  bool _initialized = false;
  Completer<void>? _initCompleter;
  late final BrazePlugin _client;

  Future<void> init() async {
    if (_initialized) return Future.value();
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      _client = BrazePlugin();
      _client.subscribeToPushNotificationEvents((event) {
        print("Push Notification event of type ${event.payloadType} seen. Title ${event.title}\n and deeplink ${event.url}");
        // Handle push notification events
      });
      // Ask for notification permissions with flutter
      // Request notification permission
      await Permission.notification.request();
      _initialized = true;
      _initCompleter!.complete();
    } catch (e, st) {
      _initCompleter!.completeError(e, st);
      rethrow;
    }
    return _initCompleter!.future;
  }

  void setUserId(String userId) async {
    _ensureInitialized();
    return _client.changeUser(userId);
  }

  void logEvent(String eventName, {Map<String, dynamic>? properties}) {
    _ensureInitialized();
    _client.inAppMessageStreamController.stream.listen((message) {
      
    });
    
    return _client.logCustomEvent(eventName, properties: properties);
  }

  void logPurchase(
    String productId,
    double price,
    String currency, {
    int quantity = 1,
    Map<String, dynamic>? properties,
  }) {
    _ensureInitialized();
    return _client.logPurchase(
      productId,
      currency,
      price,
      quantity,
      properties: properties,
    );
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'BrazeService no está inicializado. Llama init() antes de usarlo.',
      );
    }
  }
}
