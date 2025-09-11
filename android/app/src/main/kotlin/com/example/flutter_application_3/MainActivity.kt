package com.example.flutter_application_3

import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel


class MainActivity: FlutterActivity() {
    private val channelName = "amplitude_session_replay"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "amplitude_session_replay")
  .setMethodCallHandler { call, result ->
    try {
      when (call.method) {
        
        "init" -> {
          val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
          val apiKey = args["apiKey"]?.toString()?.takeIf { it.isNotBlank() }
            ?: return@setMethodCallHandler result.error("SR_ERROR", "apiKey is null/empty", null)

          val deviceId = args["deviceId"]?.toString()?.takeIf { it.isNotBlank() }
            ?: return@setMethodCallHandler result.error("SR_ERROR", "deviceId is null/empty", null)

          val sessionId = when (val s = args["sessionId"]) {
            is Number -> s.toLong()
            is String -> s.toLongOrNull()
            else -> null
          } ?: return@setMethodCallHandler result.error("SR_ERROR", "sessionId is null/invalid", null)

          val sampleRate = when (val r = args["sampleRate"]) {
            is Number -> r.toDouble()
            is String -> r.toDoubleOrNull() ?: 1.0
            else -> 1.0
          }
          val eu = (args["eu"] as? Boolean) ?: false
          val enableRemoteConfig = (args["enableRemoteConfig"] as? Boolean) ?: true

          SessionReplayHolder.init(
            context = applicationContext,
            apiKey = apiKey,
            deviceId = deviceId,
            sessionId = sessionId,
            sampleRate = sampleRate,
            eu = eu,
            enableRemoteConfig = enableRemoteConfig
          )
          result.success(null)
        }
        "updateIds" -> {
          val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
          (args["deviceId"]?.toString())?.let { if (it.isNotBlank()) SessionReplayHolder.setDeviceId(it) }
          (when (val s = args["sessionId"]) {
            is Number -> s.toLong()
            is String -> s.toLongOrNull()
            else -> null
          })?.let { SessionReplayHolder.setSessionId(it) }
          result.success(null)
        }
        "getProperties" -> result.success(SessionReplayHolder.getProperties())
        "flush" -> { SessionReplayHolder.flush(); result.success(null) }
        else -> result.notImplemented()
      }
    } catch (t: Throwable) {
      result.error("SR_ERROR", t.message ?: "Unknown error", null)
    }
  }

    }

    override fun onPause() {
        super.onPause()
        // Por seguridad, haz flush cuando la app se va a background
        SessionReplayHolder.flush()
    }
}
