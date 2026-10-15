package com.rkprince.control

import android.content.res.Configuration
import android.os.Bundle
import com.rkprince.control.bridge.ControlBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var bridge: ControlBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Before Flutter's first frame, so the launch screen is edge to edge
        // too; from then on Flutter keeps the bars in step with the theme.
        val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        EdgeToEdge.apply(window, darkContent = !night)
    }

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
