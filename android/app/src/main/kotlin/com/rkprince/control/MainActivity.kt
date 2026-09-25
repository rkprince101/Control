package com.rkprince.control

import com.rkprince.control.bridge.ControlBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var bridge: ControlBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = ControlBridge(applicationContext).also {
            it.attach(flutterEngine.dartExecutor.binaryMessenger, this)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.detach()
        bridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
