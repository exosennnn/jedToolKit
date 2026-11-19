package com.jedplatforms.jedtoolkit;

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.jedplatforms.jedtoolkit/phoneinfo";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (call.method.equals("getDeviceInfo")) {
                        try {
                            result.success(new DeviceInfoCollector(this).collect());
                        } catch (RuntimeException e) {
                            result.error("COLLECT_FAILED", e.getMessage(), null);
                        }
                    } else {
                        result.notImplemented();
                    }
                });
    }
}