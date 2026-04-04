package com.openreef.app.openreef

import com.openreef.app.openreef.litert.LiteRtLmBridge
import com.openreef.app.openreef.litert.UnavailableLiteRtLmEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var liteRtBridge: LiteRtLmBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (liteRtBridge == null) {
            liteRtBridge =
                LiteRtLmBridge(
                    messenger = flutterEngine.dartExecutor.binaryMessenger,
                    engine = UnavailableLiteRtLmEngine(),
                )
        }
    }

    override fun onDestroy() {
        liteRtBridge?.dispose()
        liteRtBridge = null
        super.onDestroy()
    }
}
