package com.example.flutter_application_3

import android.app.Application
import android.content.Context
import com.amplitude.android.sessionreplay.SessionReplay

object SessionReplayHolder {
    @Volatile private var sr: SessionReplay? = null

    fun init(
        context: Context,
        apiKey: String,
        deviceId: String,
        sessionId: Long,
        sampleRate: Double = 1.0,
        eu: Boolean = false,
        enableRemoteConfig: Boolean = false
    ) {
        if (sr != null) return
        sr = SessionReplay(
            apiKey = apiKey,
            context = context.applicationContext,
            deviceId = deviceId,
            sessionId = sessionId,       // en milisegundos epoch
            sampleRate = sampleRate,     // durante QA puedes usar 1.0 (100%)
            enableRemoteConfig = enableRemoteConfig
        )
    }

    fun setSessionId(sessionId: Long) { sr?.setSessionId(sessionId) }
    fun setDeviceId(deviceId: String) { sr?.setDeviceId(deviceId) }

    /** Devuelve el mapa con "[Amplitude] Session Replay ID" listo para adjuntar al evento */
    fun getProperties(): Map<String, Any> = sr?.getSessionReplayProperties() ?: emptyMap()

    fun flush() { sr?.flush() }
}
