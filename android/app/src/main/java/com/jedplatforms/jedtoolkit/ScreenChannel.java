package com.jedplatforms.jedtoolkit;

import android.app.Activity;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Keeps the screen on while a benchmark runs. */
public final class ScreenChannel {
    private static final String CHANNEL = "jedtoolkit/screen";

    private ScreenChannel() {}

    public static void register(@NonNull Activity activity, @NonNull FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (!"keepOn".equals(call.method)) {
                        result.notImplemented();
                        return;
                    }
                    final boolean on = Boolean.TRUE.equals(call.argument("enabled"));
                    activity.runOnUiThread(() -> {
                        if (on) {
                            activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                        } else {
                            activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                        }
                        result.success(null);
                    });
                });
    }
}