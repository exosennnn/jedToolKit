package com.jedplatforms.jedtoolkit;

import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * Data Android allows an app to read about itself, for the jedPanicAnalyzer module:
 *  - exit history (ApplicationExitInfo, Android 11+), including stored ANR and
 *    native crash traces for this app
 *  - this app's own logcat lines (no READ_LOGS permission needed)
 *
 * Nothing here reads other apps, system folders, or needs root.
 * Register from MainActivity.configureFlutterEngine:
 *   PanicAnalyzerChannel.register(this, flutterEngine);
 */
public final class PanicAnalyzerChannel {
    private static final String CHANNEL = "com.jedplatforms.jedtoolkit/panic";
    private static final int MAX_EXITS = 20;
    private static final int MAX_TRACE_BYTES = 256 * 1024;
    private static final int MAX_LOGCAT_LINES = 4000;

    private final Context app;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newSingleThreadExecutor();

    private interface Work {
        Object run() throws Exception;
    }

    private PanicAnalyzerChannel(Context app) {
        this.app = app;
    }

    public static void register(@NonNull Context context, @NonNull FlutterEngine engine) {
        final PanicAnalyzerChannel h = new PanicAnalyzerChannel(context.getApplicationContext());
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "getCapabilities":
                            result.success(h.capabilities());
                            break;
                        case "getExitHistory": {
                            final boolean traces = Boolean.TRUE.equals(call.argument("includeTraces"));
                            h.async(() -> h.exitHistory(traces), result, "EXIT_HISTORY_FAILED");
                            break;
                        }
                        case "getLogcat":
                            h.async(h::logcat, result, "LOGCAT_FAILED");
                            break;
                        default:
                            result.notImplemented();
                            break;
                    }
                });
    }

    /** Runs slow work off the main thread and replies on the main thread. */
    private void async(Work work, MethodChannel.Result result, String errorCode) {
        io.execute(() -> {
            try {
                final Object data = work.run();
                main.post(() -> result.success(data));
            } catch (Throwable t) {
                final String msg = t.getMessage() != null ? t.getMessage() : t.getClass().getSimpleName();
                main.post(() -> result.error(errorCode, msg, null));
            }
        });
    }

    private Map<String, Object> capabilities() {
        final boolean exits = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R;
        final Map<String, Object> m = new HashMap<>();
        m.put("sdkInt", Build.VERSION.SDK_INT);
        m.put("exitHistory", exits);
        m.put("exitTraces", exits);
        m.put("logcat", true);
        return m;
    }

    private Map<String, Object> exitHistory(boolean includeTraces) throws IOException {
        final Map<String, Object> out = new HashMap<>();
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            out.put("supported", false);
            out.put("records", new ArrayList<Object>());
        } else {
            out.put("supported", true);
            out.put("records", exitRecords(includeTraces));
        }
        return out;
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private List<Object> exitRecords(boolean includeTraces) throws IOException {
        final List<Object> out = new ArrayList<>();
        final ActivityManager am = (ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE);
        if (am == null) return out;

        final List<ApplicationExitInfo> infos =
                am.getHistoricalProcessExitReasons(app.getPackageName(), 0, MAX_EXITS);
        for (ApplicationExitInfo info : infos) {
            final int reason = info.getReason();
            final Map<String, Object> r = new HashMap<>();
            r.put("timestampMs", info.getTimestamp());
            r.put("pid", info.getPid());
            r.put("process", info.getProcessName());
            r.put("reason", reason);
            r.put("reasonName", reasonName(reason));
            r.put("status", info.getStatus());
            r.put("importance", info.getImportance());
            r.put("rssKb", info.getRss());
            r.put("description", info.getDescription());

            // Android keeps a trace only for ANRs and native crashes.
            if (includeTraces && (reason == ApplicationExitInfo.REASON_ANR
                    || reason == ApplicationExitInfo.REASON_CRASH_NATIVE)) {
                try (InputStream in = info.getTraceInputStream()) {
                    r.put("trace", in == null ? null : readCapped(in));
                }
            }
            out.add(r);
        }
        return out;
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private static String reasonName(int reason) {
        switch (reason) {
            case ApplicationExitInfo.REASON_CRASH: return "Java crash";
            case ApplicationExitInfo.REASON_CRASH_NATIVE: return "Native crash";
            case ApplicationExitInfo.REASON_ANR: return "ANR";
            case ApplicationExitInfo.REASON_LOW_MEMORY: return "Low memory";
            case ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE: return "Excessive resource use";
            case ApplicationExitInfo.REASON_USER_REQUESTED: return "User requested";
            case ApplicationExitInfo.REASON_USER_STOPPED: return "User stopped";
            case ApplicationExitInfo.REASON_SIGNALED: return "Signaled";
            case ApplicationExitInfo.REASON_EXIT_SELF: return "Exited by app";
            case ApplicationExitInfo.REASON_INITIALIZATION_FAILURE: return "Initialization failed";
            case ApplicationExitInfo.REASON_PERMISSION_CHANGE: return "Permission changed";
            case ApplicationExitInfo.REASON_DEPENDENCY_DIED: return "Dependency died";
            case ApplicationExitInfo.REASON_OTHER: return "Other";
            default: return "Unknown";
        }
    }

    private static String readCapped(InputStream in) throws IOException {
        final ByteArrayOutputStream buf = new ByteArrayOutputStream();
        final byte[] chunk = new byte[8192];
        int n;
        while (buf.size() < MAX_TRACE_BYTES && (n = in.read(chunk)) > 0) {
            buf.write(chunk, 0, Math.min(n, MAX_TRACE_BYTES - buf.size()));
        }
        return new String(buf.toByteArray(), StandardCharsets.UTF_8);
    }

    /** This app's own log lines, in "brief" format (E/Tag(pid): message). */
    private String logcat() throws IOException {
        final Process p = new ProcessBuilder(
                "logcat", "-d", "-v", "brief", "-t", String.valueOf(MAX_LOGCAT_LINES))
                .redirectErrorStream(true)
                .start();
        final StringBuilder sb = new StringBuilder();
        try (BufferedReader r = new BufferedReader(
                new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) {
                sb.append(line).append('\n');
            }
        }
        try {
            p.waitFor();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return sb.toString();
    }
}