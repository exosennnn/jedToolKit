package com.jedplatforms.jedtoolkit;

import android.app.ActivityManager;
import android.content.ComponentCallbacks2;
import android.content.Context;
import android.os.Build;
import android.os.Debug;
import android.system.Os;
import android.system.OsConstants;

import java.io.BufferedReader;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Android counterpart of iOS MemoryMonitorService.
 *
 * iOS:      budget = footprint + os_proc_available_memory()
 * Android:  budget = footprint + (availMem - lowMemoryThreshold)
 *
 * Android has no hard per-app native limit, so the real "room to grow" is how
 * much RAM the system can hand out before it starts killing processes.
 *
 * Call collect() from a background thread (see MainActivity).
 */
public class RamMetricsCollector {
    private final ActivityManager activityManager;
    private final boolean is64Bit =
            Build.SUPPORTED_64_BIT_ABIS != null && Build.SUPPORTED_64_BIT_ABIS.length != 0;
    private final long pageSize;

    public RamMetricsCollector(Context context) {
        Context app = context.getApplicationContext();
        this.activityManager = (ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE);

        long ps = 4096L;
        try {
            long v = Os.sysconf(OsConstants._SC_PAGESIZE);
            if (v > 0) ps = v;
        } catch (Throwable ignored) {
        }
        this.pageSize = ps;
    }

    public Map<String, Object> collect(boolean includeCapabilities) {
        ActivityManager.MemoryInfo memInfo = new ActivityManager.MemoryInfo();
        if (activityManager != null) activityManager.getMemoryInfo(memInfo);

        Map<String, Object> payload = new HashMap<>();
        payload.put("app", collectAppMetrics(memInfo));
        payload.put("system", collectSystemMetrics(memInfo));
        if (includeCapabilities) payload.put("capabilities", collectCapabilities());
        return payload;
    }

    private Map<String, Object> collectAppMetrics(ActivityManager.MemoryInfo memInfo) {
        Runtime runtime = Runtime.getRuntime();
        long heapUsed = runtime.totalMemory() - runtime.freeMemory();

        long rss = 0L;
        long virt = 0L;
        long[] status = readProcSelfStatus(); // [VmRSS, VmSize]
        rss = status[0];
        virt = status[1];

        // Debug.getPss() = this process' proportional set size in KB. Never throws on a parse.
        long pss = 0L;
        try {
            pss = Debug.getPss() * 1024L;
        } catch (Throwable ignored) {
        }

        long footprint = pss > 0 ? pss : (rss > 0 ? rss : heapUsed);

        // iOS-style budget: what the app could still grow by before the system gets into trouble.
        long headroom = Math.max(0L, memInfo.availMem - memInfo.threshold);
        long total = footprint + headroom;

        Map<String, Object> app = new HashMap<>();
        app.put("physicalFootprintBytes", footprint);
        app.put("residentMemoryBytes", rss > 0 ? rss : footprint);
        app.put("virtualMemoryBytes", virt);
        app.put("availableBudgetBytes", headroom);
        app.put("totalBudgetEstimateBytes", total);
        return app;
    }

    private Map<String, Object> collectSystemMetrics(ActivityManager.MemoryInfo memInfo) {
        long totalRam = memInfo.totalMem;
        long availableRam = memInfo.availMem;
        long usedRam = Math.max(0L, totalRam - availableRam);

        Map<String, Object> sys = new HashMap<>();
        sys.put("totalPhysicalBytes", totalRam);
        sys.put("usedBytes", usedRam);
        sys.put("availableBytes", availableRam);
        sys.put("freeBytes", readMemFreeBytes());
        sys.put("pageSizeBytes", pageSize);
        sys.put("addressWidthBits", is64Bit ? 64 : 32);
        sys.put("virtualAddressSpaceBytes", is64Bit ? (1L << 39) : 0xFFFFFFFFL);
        sys.put("lowMemory", memInfo.lowMemory);
        return sys;
    }

    private List<Object> collectCapabilities() {
        List<Object> caps = new ArrayList<>();

        int large = activityManager != null ? activityManager.getLargeMemoryClass() : 0;
        int normal = activityManager != null ? activityManager.getMemoryClass() : 0;
        caps.add(makeCap(
                "Large Heap Allocation",
                large != normal ? "Available" : "Unavailable",
                "Allows manifest largeHeap builds to request extended ART heap caps (" + large + " MB)."));

        caps.add(makeCap(
                "Extended Virtual Addressing",
                is64Bit ? "Available" : "Unsupported",
                "Provides access to expanded 64-bit user-space virtual memory addressing."));

        caps.add(makeCap(
                "Memory Pressure Monitoring",
                "Available",
                "Subscribes to Android trim notifications prior to low-memory-killer intervention."));

        caps.add(makeCap(
                "Procfs & PSS Statistics",
                "Available",
                "Queries Linux /proc/meminfo page statistics and process PSS/RSS footprint."));

        caps.add(makeCap(
                "64-bit Address Space",
                is64Bit ? "Available" : "Unsupported",
                "App process executes natively within a 64-bit ARM64/x86_64 architecture."));

        return caps;
    }

    private Map<String, Object> makeCap(String title, String status, String summary) {
        Map<String, Object> cap = new HashMap<>();
        cap.put("title", title);
        cap.put("status", status);
        cap.put("summary", summary);
        return cap;
    }

    /** Returns {VmRSS, VmSize} in bytes (0 if unavailable). */
    private long[] readProcSelfStatus() {
        long rss = 0L, size = 0L;
        try (BufferedReader reader = new BufferedReader(new FileReader("/proc/self/status"))) {
            String line;
            int found = 0;
            while (found < 2 && (line = reader.readLine()) != null) {
                if (line.startsWith("VmRSS:")) {
                    rss = parseKb(line);
                    found++;
                } else if (line.startsWith("VmSize:")) {
                    size = parseKb(line);
                    found++;
                }
            }
        } catch (Exception ignored) {
        }
        return new long[]{rss, size};
    }

    private Long readMemFreeBytes() {
        try (BufferedReader reader = new BufferedReader(new FileReader("/proc/meminfo"))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith("MemFree:")) return parseKb(line);
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    private static long parseKb(String line) {
        String[] parts = line.trim().split("\\s+");
        if (parts.length < 2) return 0L;
        try {
            return Long.parseLong(parts[1]) * 1024L;
        } catch (NumberFormatException e) {
            return 0L;
        }
    }

    public static String mapTrimLevelToPressure(int level) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_COMPLETE
                || level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL) {
            return "Critical";
        } else if (level >= ComponentCallbacks2.TRIM_MEMORY_MODERATE
                || level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW
                || level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE) {
            return "Warning";
        }
        return "Normal";
    }
}