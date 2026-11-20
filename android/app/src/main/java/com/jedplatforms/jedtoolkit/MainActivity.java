package com.jedplatforms.jedtoolkit;

import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterFragmentActivity; // CHANGED: was FlutterActivity (local_auth needs a FragmentActivity)
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends FlutterFragmentActivity { // CHANGED
    private static final String CHANNEL = "com.jedplatforms.jedtoolkit/phoneinfo";
    private static final String DISK_CHANNEL = "com.jedplatforms.jedtoolkit/disk";

    private MethodChannel methodChannel;
    private MethodChannel diskChannel;
    private RamMetricsCollector ramCollector;
    private DiskBenchmark diskBenchmark;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    // One worker thread: RAM sampling never blocks the UI and never overlaps itself.
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        DeviceSpecsChannel.register(flutterEngine);
        GlesComputeChannel.register(flutterEngine);
        ThermalChannel.register(this, flutterEngine);
        ScreenChannel.register(this, flutterEngine);
        HWCheckerChannel.register(this, flutterEngine);
        HwMediaBiometricChannel.register(this, flutterEngine);
        PanicAnalyzerChannel.register(this, flutterEngine);   // <-- add this

        // ---------------- Phone info + RAM ----------------
        ramCollector = new RamMetricsCollector(this);
        methodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        methodChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "getDeviceInfo":
                    try {
                        result.success(new DeviceInfoCollector(this).collect());
                    } catch (RuntimeException e) {
                        result.error("COLLECT_FAILED", e.getMessage(), null);
                    }
                    break;
                case "getRamMetrics": {
                    final boolean includeCaps = Boolean.TRUE.equals(call.argument("includeCapabilities"));
                    worker.execute(() -> {
                        try {
                            final Map<String, Object> data = ramCollector.collect(includeCaps);
                            runOnUiThread(() -> result.success(data));
                        } catch (Throwable t) {
                            runOnUiThread(() -> result.error("RAM_COLLECT_FAILED", String.valueOf(t.getMessage()), null));
                        }
                    });
                    break;
                }
                default:
                    result.notImplemented();
                    break;
            }
        });

        // ---------------- Disk checker ----------------
        // Events are posted one by one to the main looper, so Flutter receives them in order.
        diskBenchmark = new DiskBenchmark(this, event -> mainHandler.post(() -> {
            if (diskChannel != null) diskChannel.invokeMethod("onDiskEvent", event);
        }));
        diskChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), DISK_CHANNEL);
        diskChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "getDiskSpace":
                    worker.execute(() -> {
                        try {
                            final Map<String, Object> data = diskBenchmark.getDiskSpace();
                            runOnUiThread(() -> result.success(data));
                        } catch (Throwable t) {
                            runOnUiThread(() -> result.error("DISK_SPACE_FAILED", String.valueOf(t.getMessage()), null));
                        }
                    });
                    break;
                case "startDiskTest":
                    result.success(diskBenchmark.start());
                    break;
                case "cancelDiskTest":
                    diskBenchmark.cancel();
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        });
    }

    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        if (methodChannel != null) {
            methodChannel.invokeMethod("onMemoryPressure", RamMetricsCollector.mapTrimLevelToPressure(level));
        }
    }

    @Override
    public void onLowMemory() {
        super.onLowMemory();
        if (methodChannel != null) {
            methodChannel.invokeMethod("onMemoryPressure", "Critical");
        }
    }

    @Override
    protected void onDestroy() {
        if (diskBenchmark != null) diskBenchmark.shutdown();
        worker.shutdownNow();
        super.onDestroy();
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (HWCheckerChannel.handleKeyEvent(event)) {
            return true;
        }
        return super.dispatchKeyEvent(event);
    }
}