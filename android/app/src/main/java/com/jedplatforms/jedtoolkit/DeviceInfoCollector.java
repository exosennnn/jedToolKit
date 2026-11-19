package com.jedplatforms.jedtoolkit;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.FeatureInfo;
import android.content.pm.PackageManager;
import android.hardware.Sensor;
import android.hardware.SensorManager;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.hardware.display.DisplayManager;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Environment;
import android.os.StatFs;
import android.util.DisplayMetrics;
import android.util.Size;
import android.view.Display;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

/**
 * Collects device information from public Android APIs and readable system files.
 * Every value carries an explicit status so the UI never shows a guess.
 */
public final class DeviceInfoCollector {

    static final String AVAILABLE = "AVAILABLE";
    static final String RESTRICTED = "RESTRICTED";
    static final String UNSUPPORTED = "UNSUPPORTED";
    static final String ERROR = "ERROR";

    private static final String NOT_READABLE_NOTE =
            "Android restricts this system file for apps on this device.";

    private interface FieldSupplier {
        List<Map<String, Object>> get() throws Exception;
    }

    private final Context context;

    public DeviceInfoCollector(Context context) {
        this.context = context.getApplicationContext();
    }

    public List<Map<String, Object>> collect() {
        List<Map<String, Object>> sections = new ArrayList<>();
        sections.add(buildSection("Device", this::deviceFields));
        sections.add(buildSection("Android", this::androidFields));
        sections.add(buildSection("System on Chip", this::socFields));
        sections.add(buildSection("CPU", this::cpuFields));
        sections.add(buildSection("Memory", this::memoryFields));
        sections.add(buildSection("Storage", this::storageFields));
        sections.add(buildSection("Display", this::displayFields));
        sections.add(buildSection("Battery", this::batteryFields));
        sections.add(buildSection("Graphics", this::graphicsFields));
        sections.add(buildSection("Cameras", this::cameraFields));
        sections.add(buildSection("Sensors", this::sensorFields));
        sections.add(buildSection("Features", this::featureFields));
        return sections;
    }

    // ---------- sections ----------

    private List<Map<String, Object>> deviceFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        f.add(value("Manufacturer", Build.MANUFACTURER, null));
        f.add(value("Brand", Build.BRAND, null));
        f.add(value("Model", Build.MODEL, null));
        f.add(value("Device codename", Build.DEVICE,
                "Internal device name, often different from the marketing name."));
        f.add(value("Product", Build.PRODUCT, null));
        f.add(value("Board", Build.BOARD, null));
        return f;
    }

    private List<Map<String, Object>> androidFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        f.add(value("Android version", Build.VERSION.RELEASE, null));
        f.add(value("API level", String.valueOf(Build.VERSION.SDK_INT), null));
        f.add(value("Security patch", Build.VERSION.SECURITY_PATCH,
                "Reported by the device. Manufacturers may update it late."));
        f.add(value("Build ID", Build.DISPLAY, null));
        f.add(value("Kernel version", System.getProperty("os.version"), null));
        return f;
    }

    private List<Map<String, Object>> socFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= 31) {
            f.add(value("SoC manufacturer", Build.SOC_MANUFACTURER, null));
            f.add(value("SoC model", Build.SOC_MODEL, null));
        } else {
            f.add(field("SoC model", null, UNSUPPORTED,
                    "Requires Android 12 (API 31) or newer."));
        }
        f.add(value("Hardware", Build.HARDWARE, "Platform name reported by the kernel."));
        return f;
    }

    private List<Map<String, Object>> cpuFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        int cores = Runtime.getRuntime().availableProcessors();

        f.add(value("Architecture", System.getProperty("os.arch"), null));
        f.add(field("Online cores", String.valueOf(cores), AVAILABLE,
                "Cores currently online, as reported by the Java runtime."));
        f.add(value("Supported ABIs", join(Build.SUPPORTED_ABIS), null));

        String present = readLine("/sys/devices/system/cpu/present");
        f.add(present == null
                ? field("Present cores", null, RESTRICTED, NOT_READABLE_NOTE)
                : field("Present cores", present, AVAILABLE, null));

        // Group cores into clusters by their maximum frequency, like CPU-Z does.
        TreeMap<Long, List<Integer>> clusters = new TreeMap<>();
        for (int i = 0; i < cores; i++) {
            Long max = parseLong(readLine(cpuPath(i, "cpuinfo_max_freq")));
            if (max != null) {
                clusters.computeIfAbsent(max, k -> new ArrayList<>()).add(i);
            }
        }

        if (clusters.isEmpty()) {
            f.add(field("Clusters", null, RESTRICTED, NOT_READABLE_NOTE));
        } else {
            int n = 1;
            for (Map.Entry<Long, List<Integer>> e : clusters.entrySet()) {
                f.add(field("Cluster " + n++,
                        e.getValue().size() + " core(s) · max " + formatKhz(e.getKey())
                                + " · cores " + joinInts(e.getValue()),
                        AVAILABLE,
                        n == 2 ? "Ordered by maximum frequency, lowest first." : null));
            }
        }

        String governor = readLine(cpuPath(0, "scaling_governor"));
        f.add(governor == null
                ? field("Governor (core 0)", null, RESTRICTED, NOT_READABLE_NOTE)
                : field("Governor (core 0)", governor, AVAILABLE, null));

        for (int i = 0; i < cores; i++) {
            Long cur = parseLong(readLine(cpuPath(i, "scaling_cur_freq")));
            Long max = parseLong(readLine(cpuPath(i, "cpuinfo_max_freq")));
            String label = "Core " + i;
            if (cur == null) {
                f.add(field(label, null, RESTRICTED, i == 0 ? NOT_READABLE_NOTE : null));
            } else {
                String v = formatKhz(cur) + (max != null ? " of " + formatKhz(max) : "");
                f.add(field(label, v, AVAILABLE,
                        i == 0 ? "Current clock. It changes with load and temperature." : null));
            }
        }
        return f;
    }

    private List<Map<String, Object>> memoryFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        ActivityManager am = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
        am.getMemoryInfo(mi);

        f.add(field("Total memory", formatBytes(mi.totalMem), AVAILABLE,
                "Total device memory reported by Android."));
        f.add(field("Available memory", formatBytes(mi.availMem), AVAILABLE,
                "Memory Android can give to apps right now. It changes constantly."));
        f.add(field("Low-memory state", mi.lowMemory ? "Yes" : "No", AVAILABLE, null));
        f.add(field("App heap limit", am.getMemoryClass() + " MB", AVAILABLE,
                "Standard heap limit for this app. Large-heap apps get more."));
        return f;
    }

    private List<Map<String, Object>> storageFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        StatFs s = new StatFs(Environment.getDataDirectory().getPath());
        f.add(field("Internal total", formatBytes(s.getTotalBytes()), AVAILABLE,
                "Size of the data partition, as seen by this app."));
        f.add(field("Internal free", formatBytes(s.getAvailableBytes()), AVAILABLE, null));
        return f;
    }

    private List<Map<String, Object>> displayFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        DisplayManager dm = context.getSystemService(DisplayManager.class);
        Display d = dm.getDisplay(Display.DEFAULT_DISPLAY);
        DisplayMetrics m = new DisplayMetrics();
        d.getRealMetrics(m);

        f.add(field("Resolution", m.widthPixels + " × " + m.heightPixels + " px", AVAILABLE, null));
        f.add(field("Density", m.densityDpi + " dpi", AVAILABLE, null));
        f.add(field("Refresh rate", String.format(Locale.US, "%.0f Hz", d.getRefreshRate()),
                AVAILABLE, null));

        if (m.xdpi > 0 && m.ydpi > 0) {
            double w = m.widthPixels / m.xdpi;
            double h = m.heightPixels / m.ydpi;
            f.add(field("Estimated diagonal",
                    String.format(Locale.US, "%.1f in", Math.sqrt(w * w + h * h)), AVAILABLE,
                    "Estimated from manufacturer-reported DPI. Can be off by a few tenths of an inch."));
        } else {
            f.add(field("Estimated diagonal", null, UNSUPPORTED, "Physical size is not reported."));
        }
        return f;
    }

    private List<Map<String, Object>> batteryFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        Intent bi = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));

        if (bi != null) {
            int level = bi.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
            int scale = bi.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
            int status = bi.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
            int health = bi.getIntExtra(BatteryManager.EXTRA_HEALTH, -1);
            int plugged = bi.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0);
            int temp = bi.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
            int voltage = bi.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1);

            f.add(level >= 0 && scale > 0
                    ? field("Charge", (level * 100 / scale) + "%", AVAILABLE, null)
                    : field("Charge", null, UNSUPPORTED, null));
            f.add(field("Status", batteryStatus(status), AVAILABLE, null));
            f.add(field("Health", batteryHealth(health), AVAILABLE,
                    "Coarse category reported by the battery controller. It is not a measured capacity."));
            f.add(field("Power source", powerSource(plugged), AVAILABLE, null));
            f.add(temp == Integer.MIN_VALUE
                    ? field("Temperature", null, UNSUPPORTED, null)
                    : field("Temperature", String.format(Locale.US, "%.1f °C", temp / 10.0),
                            AVAILABLE, null));
            f.add(voltage > 0
                    ? field("Voltage", voltage + " mV", AVAILABLE, null)
                    : field("Voltage", null, UNSUPPORTED, null));
        } else {
            f.add(field("Battery", null, UNSUPPORTED, "Battery broadcast not available."));
        }

        BatteryManager bm = context.getSystemService(BatteryManager.class);

        int chargeUah = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER);
        f.add(chargeUah == Integer.MIN_VALUE
                ? field("Remaining charge", null, UNSUPPORTED,
                        "This device does not report remaining charge.")
                : field("Remaining charge", (chargeUah / 1000) + " mAh", AVAILABLE,
                        "Remaining charge reported by the battery controller."));

        int currentUa = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW);
        f.add(currentUa == Integer.MIN_VALUE
                ? field("Current", null, UNSUPPORTED,
                        "This device does not report instantaneous current.")
                : field("Current", (currentUa / 1000) + " mA", AVAILABLE,
                        "Positive or negative depending on charging or discharging."));

        f.add(field("Design capacity", null, UNSUPPORTED,
                "Not exposed through public Android APIs, so it can't be shown honestly."));
        return f;
    }

    private List<Map<String, Object>> graphicsFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        PackageManager pm = context.getPackageManager();

        String glEs = null;
        int vkLevel = -1;
        int vkVersion = -1;
        for (FeatureInfo fi : pm.getSystemAvailableFeatures()) {
            if (fi.name == null && fi.reqGlEsVersion != 0) {
                glEs = fi.getGlEsVersion();
            } else if (PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL.equals(fi.name)) {
                vkLevel = fi.version;
            } else if (PackageManager.FEATURE_VULKAN_HARDWARE_VERSION.equals(fi.name)) {
                vkVersion = fi.version;
            }
        }

        f.add(value("OpenGL ES version", glEs, null));
        f.add(vkLevel >= 0
                ? field("Vulkan hardware level", String.valueOf(vkLevel), AVAILABLE,
                        "0 = basic, 1 = full, as reported by the device.")
                : field("Vulkan hardware level", null, UNSUPPORTED, "Vulkan not reported."));
        f.add(vkVersion > 0
                ? field("Vulkan version",
                        String.format(Locale.US, "%d.%d.%d",
                                vkVersion >> 22, (vkVersion >> 12) & 0x3ff, vkVersion & 0xfff),
                        AVAILABLE, null)
                : field("Vulkan version", null, UNSUPPORTED, null));
        f.add(field("GPU model", null, UNSUPPORTED,
                "Reading the GPU name needs an OpenGL context. Not included in this version."));
        return f;
    }

    private List<Map<String, Object>> cameraFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        CameraManager cm = context.getSystemService(CameraManager.class);

        try {
            String[] ids = cm.getCameraIdList();
            if (ids.length == 0) {
                f.add(field("Cameras", null, UNSUPPORTED, "No camera reported."));
                return f;
            }
            for (String id : ids) {
                try {
                    // Reads metadata only; does not open the camera.
                    CameraCharacteristics c = cm.getCameraCharacteristics(id);
                    Integer facing = c.get(CameraCharacteristics.LENS_FACING);
                    Size px = c.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE);
                    float[] focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS);
                    Integer level = c.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL);

                    List<String> parts = new ArrayList<>();
                    if (px != null) {
                        parts.add(String.format(Locale.US, "%.1f MP",
                                px.getWidth() * (double) px.getHeight() / 1_000_000.0));
                    }
                    if (focal != null && focal.length > 0) {
                        parts.add(String.format(Locale.US, "%.1f mm", focal[0]));
                    }
                    boolean has = !parts.isEmpty();
                    f.add(field(
                            "Camera " + id + " · " + facingName(facing),
                            has ? String.join(" · ", parts) : null,
                            has ? AVAILABLE : UNSUPPORTED,
                            "Hardware level: " + levelName(level)));
                } catch (CameraAccessException | IllegalArgumentException e) {
                    f.add(field("Camera " + id, null, ERROR,
                            "Could not read this camera's characteristics."));
                }
            }
        } catch (CameraAccessException e) {
            f.add(field("Cameras", null, ERROR, "Camera service unavailable."));
        }
        return f;
    }

    private List<Map<String, Object>> sensorFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        SensorManager sm = context.getSystemService(SensorManager.class);
        List<Sensor> sensors = sm.getSensorList(Sensor.TYPE_ALL);
        if (sensors.isEmpty()) {
            f.add(field("Sensors", null, UNSUPPORTED, "No sensors reported."));
        }
        for (Sensor s : sensors) {
            f.add(value(s.getName(), s.getVendor(), null));
        }
        return f;
    }

    private List<Map<String, Object>> featureFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        PackageManager pm = context.getPackageManager();
        String[][] checks = {
                {"Bluetooth LE", PackageManager.FEATURE_BLUETOOTH_LE},
                {"NFC", PackageManager.FEATURE_NFC},
                {"Wi-Fi", PackageManager.FEATURE_WIFI},
                {"Fingerprint sensor", PackageManager.FEATURE_FINGERPRINT},
                {"Telephony", PackageManager.FEATURE_TELEPHONY},
                {"Camera (any)", PackageManager.FEATURE_CAMERA_ANY},
        };
        for (String[] c : checks) {
            f.add(field(c[0], pm.hasSystemFeature(c[1]) ? "Yes" : "No", AVAILABLE, null));
        }
        return f;
    }

    // ---------- helpers ----------

    private Map<String, Object> buildSection(String title, FieldSupplier supplier) {
        try {
            return section(title, supplier.get());
        } catch (Exception e) {
            List<Map<String, Object>> f = new ArrayList<>();
            f.add(field("Section", e.getMessage() == null ? "Failed" : e.getMessage(), ERROR,
                    "This section could not be read."));
            return section(title, f);
        }
    }

    private static Map<String, Object> section(String title, List<Map<String, Object>> fields) {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("title", title);
        s.put("fields", fields);
        return s;
    }

    private static Map<String, Object> field(String label, String value, String status, String note) {
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("label", label);
        f.put("value", value);
        f.put("status", status);
        f.put("note", note);
        return f;
    }

    /** AVAILABLE when the value is present, otherwise UNSUPPORTED. */
    private static Map<String, Object> value(String label, String value, String note) {
        boolean has = value != null && !value.isEmpty() && !Build.UNKNOWN.equalsIgnoreCase(value);
        return field(label, has ? value : null, has ? AVAILABLE : UNSUPPORTED, note);
    }

    private static String cpuPath(int index, String file) {
        return "/sys/devices/system/cpu/cpu" + index + "/cpufreq/" + file;
    }

    private static String readLine(String path) {
        try (BufferedReader r = new BufferedReader(new FileReader(path))) {
            String line = r.readLine();
            return line == null ? null : line.trim();
        } catch (IOException e) {
            return null;
        }
    }

    private static Long parseLong(String s) {
        if (s == null) return null;
        try {
            return Long.parseLong(s.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static String formatKhz(long khz) {
        return khz >= 1_000_000
                ? String.format(Locale.US, "%.2f GHz", khz / 1_000_000.0)
                : (khz / 1000) + " MHz";
    }

    private static String formatBytes(long bytes) {
        return String.format(Locale.US, "%.1f GB", bytes / 1_073_741_824.0);
    }

    private static String join(String[] items) {
        if (items == null || items.length == 0) return null;
        return String.join(", ", items);
    }

    private static String joinInts(List<Integer> items) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < items.size(); i++) {
            if (i > 0) sb.append(", ");
            sb.append(items.get(i));
        }
        return sb.toString();
    }

    private static String batteryStatus(int s) {
        switch (s) {
            case BatteryManager.BATTERY_STATUS_CHARGING: return "Charging";
            case BatteryManager.BATTERY_STATUS_DISCHARGING: return "Discharging";
            case BatteryManager.BATTERY_STATUS_FULL: return "Full";
            case BatteryManager.BATTERY_STATUS_NOT_CHARGING: return "Not charging";
            default: return "Unknown";
        }
    }

    private static String batteryHealth(int h) {
        switch (h) {
            case BatteryManager.BATTERY_HEALTH_GOOD: return "Good";
            case BatteryManager.BATTERY_HEALTH_OVERHEAT: return "Overheat";
            case BatteryManager.BATTERY_HEALTH_DEAD: return "Dead";
            case BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE: return "Over voltage";
            case BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE: return "Failure";
            case BatteryManager.BATTERY_HEALTH_COLD: return "Cold";
            default: return "Unknown";
        }
    }

    private static String powerSource(int plugged) {
        switch (plugged) {
            case BatteryManager.BATTERY_PLUGGED_AC: return "AC charger";
            case BatteryManager.BATTERY_PLUGGED_USB: return "USB";
            case BatteryManager.BATTERY_PLUGGED_WIRELESS: return "Wireless";
            case 0: return "Not plugged in";
            default: return "Unknown";
        }
    }

    private static String facingName(Integer facing) {
        if (facing == null) return "Unknown";
        switch (facing) {
            case CameraCharacteristics.LENS_FACING_FRONT: return "Front";
            case CameraCharacteristics.LENS_FACING_BACK: return "Rear";
            case CameraCharacteristics.LENS_FACING_EXTERNAL: return "External";
            default: return "Unknown";
        }
    }

    private static String levelName(Integer level) {
        if (level == null) return "Unknown";
        switch (level) {
            case CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY: return "Legacy";
            case CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED: return "Limited";
            case CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_FULL: return "Full";
            case CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_3: return "Level 3";
            case CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL: return "External";
            default: return "Unknown";
        }
    }
}