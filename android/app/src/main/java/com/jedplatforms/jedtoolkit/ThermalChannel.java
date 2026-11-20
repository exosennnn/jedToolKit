package com.jedplatforms.jedtoolkit;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Build;
import android.os.PowerManager;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * Battery temperature plus Android's thermal status, so the benchmark can show
 * how hot it made the phone and stop before it gets dangerous.
 * Register from MainActivity:  ThermalChannel.register(this, flutterEngine);
 */
public final class ThermalChannel {
    private static final String CHANNEL = "jedtoolkit/thermal";

    private ThermalChannel() {}

    public static void register(@NonNull Context context, @NonNull FlutterEngine engine) {
        final Context app = context.getApplicationContext();
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (!"read".equals(call.method)) {
                        result.notImplemented();
                        return;
                    }
                    Map<String, Object> m = new HashMap<>();
                    int status = -1;
                    try {
                        Intent i = app.registerReceiver(null,
                                new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
                        if (i != null) {
                            int t = i.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
                            if (t != Integer.MIN_VALUE) m.put("batteryC", t / 10.0);
                        }
                        PowerManager pm = (PowerManager) app.getSystemService(Context.POWER_SERVICE);
                        if (pm != null && Build.VERSION.SDK_INT >= 29) {
                            status = pm.getCurrentThermalStatus();
                        }
                        if (pm != null && Build.VERSION.SDK_INT >= 30) {
                            float h = pm.getThermalHeadroom(10);
                            if (!Float.isNaN(h)) m.put("headroom", (double) h);
                        }
                    } catch (Throwable ignored) {
                    }
                    m.put("status", status);
                    result.success(m);
                });
    }
}