// ios/Runner/SessionReplayHolder.swift
import Foundation
import AmplitudeSessionReplay

final class SessionReplayHolder {
  static let shared = SessionReplayHolder()
  private init() {}

  private var sr: SessionReplay?
  private var lastSessionId: Int64?

  func initIfNeeded(
    apiKey: String,
    deviceId: String,
    sessionId: Int64,
    sampleRate: Float = 1.0, // <- Debe ser Float
    eu: Bool = false,
    enableRemoteConfig: Bool = true
  ) {
    guard sr == nil else { return }

    // Uso correcto del enum
    let zone: ServerZone = eu ? .EU : .US

    sr = SessionReplay(
      apiKey: apiKey,
      deviceId: deviceId,
      sessionId: sessionId,      // epoch ms
      sampleRate: sampleRate,    // Float
      serverZone: zone,          // Enum, no String
      enableRemoteConfig: enableRemoteConfig
    )
    sr?.start()
    lastSessionId = sessionId
  }

  func setSessionId(_ sessionId: Int64) {
    guard let sr else { return }
    if lastSessionId != sessionId {
      sr.sessionId = sessionId
      lastSessionId = sessionId
    }
  }

  func setDeviceId(_ deviceId: String) {
    sr?.deviceId = deviceId
  }

  func getProperties() -> [String: Any] {
    sr?.additionalEventProperties ?? [:]
  }

  func flush() {
    sr?.flush()
  }
}