import UIKit
import Flutter

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {
  private let channelName = "amplitude_session_replay"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      do {
        switch call.method {

        case "init":
          guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "SR_ERROR", message: "Missing args", details: nil)); return
          }
          guard let apiKey = (args["apiKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !apiKey.isEmpty else {
            result(FlutterError(code: "SR_ERROR", message: "apiKey is null/empty", details: nil)); return
          }
          guard let deviceIdRaw = args["deviceId"] as? String, !deviceIdRaw.isEmpty else {
            result(FlutterError(code: "SR_ERROR", message: "deviceId is null/empty", details: nil)); return
          }

          let sessionId: Int64? = {
            if let n = args["sessionId"] as? NSNumber { return n.int64Value }
            if let s = args["sessionId"] as? String { return Int64(s) }
            return nil
          }()
          guard let sid = sessionId, sid > 0 else {
            result(FlutterError(code: "SR_ERROR", message: "sessionId is null/invalid", details: nil)); return
          }

          // <- Convertimos a Float de forma segura
          let sampleRate: Float = {
            if let n = args["sampleRate"] as? NSNumber { return n.floatValue }
            if let s = args["sampleRate"] as? String, let d = Float(s) { return d }
            return 1.0
          }()

          let eu = (args["eu"] as? Bool) ?? false
          let enableRemoteConfig = (args["enableRemoteConfig"] as? Bool) ?? true

          SessionReplayHolder.shared.initIfNeeded(
            apiKey: apiKey,
            deviceId: deviceIdRaw,
            sessionId: sid,
            sampleRate: sampleRate,     // <- Float
            eu: eu,
            enableRemoteConfig: enableRemoteConfig
          )
          result(nil)

        case "updateIds":
          if let deviceId = (call.arguments as? [String: Any])?["deviceId"] as? String, !deviceId.isEmpty {
            SessionReplayHolder.shared.setDeviceId(deviceId)
          }
          if let s = (call.arguments as? [String: Any])?["sessionId"] {
            let sid: Int64? = (s as? NSNumber)?.int64Value ?? (s as? String).flatMap { Int64($0) }
            if let sid { SessionReplayHolder.shared.setSessionId(sid) }
          }
          result(nil)

        case "getProperties":
          result(SessionReplayHolder.shared.getProperties())

        case "flush":
          SessionReplayHolder.shared.flush()
          result(nil)

        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "SR_ERROR", message: "\(error)", details: nil))
      }
    }

    // Flush cuando la app pasa a background
    NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
    ) { _ in
      SessionReplayHolder.shared.flush()
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}