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
import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.opengl.GLES20;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Environment;
import android.os.PowerManager;
import android.os.StatFs;
import android.provider.Settings;
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
        sections.add(buildSection("CPU", this::cpuFields));
        sections.add(buildSection("GPU", this::graphicsFields));
        sections.add(buildSection("System", this::systemFields));
        sections.add(buildSection("Battery", this::batteryFields));
        sections.add(buildSection("Thermal", this::thermalFields));
        sections.add(buildSection("Sensors", this::sensorFields));
        return sections;
    }

    // ---------- friendly names ----------

    private static String capitalize(String s) {
        if (s == null || s.isEmpty()) return s;
        return Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }

    private static String prop(String key) {
        try {
            Process p = new ProcessBuilder("getprop", key).redirectErrorStream(true).start();
            try (BufferedReader r = new BufferedReader(
                    new java.io.InputStreamReader(p.getInputStream()))) {
                String line = r.readLine();
                return line == null || line.trim().isEmpty() ? null : line.trim();
            }
        } catch (Exception e) {
            return null;
        }
    }

    /** Small lookup for common Samsung model numbers whose marketing name isn't in a property. */
    private static String samsungName(String model) {
        if (model == null) return null;
        String m = model.toUpperCase(Locale.US);
        String[][] known = {
                {"SM-F721", "Galaxy Z Flip4"}, {"SM-F711", "Galaxy Z Flip3"},
                {"SM-F731", "Galaxy Z Flip5"}, {"SM-F741", "Galaxy Z Flip6"},
                {"SM-F936", "Galaxy Z Fold4"}, {"SM-F926", "Galaxy Z Fold3"},
                {"SM-F946", "Galaxy Z Fold5"}, {"SM-F956", "Galaxy Z Fold6"},
        };
        for (String[] k : known) if (m.startsWith(k[0])) return k[1];
        return null;
    }

    /** Best-effort marketing name, e.g. "Galaxy Z Flip4". Falls back to the model number. */
    private String marketingName() {
        String name = prop("ro.product.marketname");
        if (name == null) name = prop("ro.config.marketing_name");
        if (name == null) name = samsungName(Build.MODEL);
        if (name == null) {
            try {
                // User-set phone name; usually the marketing name unless renamed.
                name = Settings.Global.getString(context.getContentResolver(), "device_name");
            } catch (Exception ignored) { }
        }
        if (name == null || name.isEmpty()) name = Build.MODEL;
        return name;
    }

    /** Turns a chip code such as SM8475 into "Snapdragon 8+ Gen 1". Returns null if unknown. */
    private static String chipName(String code) {
        if (code == null) return null;
        String c = code.trim().toUpperCase(Locale.US);
        String[][] map = {
                // Qualcomm Snapdragon
                {"SM8150", "Snapdragon 855"}, {"SM8250", "Snapdragon 865"},
                {"SM8350", "Snapdragon 888"}, {"SM8450", "Snapdragon 8 Gen 1"},
                {"SM8475", "Snapdragon 8+ Gen 1"}, {"SM8550", "Snapdragon 8 Gen 2"},
                {"SM8650", "Snapdragon 8 Gen 3"}, {"SM8750", "Snapdragon 8 Elite"},
                {"SM7325", "Snapdragon 778G"}, {"SM7450", "Snapdragon 7 Gen 1"},
                {"SM7475", "Snapdragon 7+ Gen 2"}, {"SM7550", "Snapdragon 7 Gen 3"},
                {"SM6375", "Snapdragon 695"}, {"SM6450", "Snapdragon 6 Gen 1"},
                {"SM6225", "Snapdragon 680"},
                // Samsung Exynos
                {"S5E9925", "Exynos 2200"}, {"S5E9945", "Exynos 2400"},
                {"S5E8825", "Exynos 1280"}, {"S5E8535", "Exynos 1330"},
                // MediaTek Dimensity
                {"MT6893", "Dimensity 1200"}, {"MT6983", "Dimensity 9000"},
                {"MT6985", "Dimensity 9200"}, {"MT6989", "Dimensity 9300"},
                {"MT6877", "Dimensity 900"},
                // Google Tensor
                {"GS101", "Google Tensor"}, {"GS201", "Google Tensor G2"},
                {"GS301", "Google Tensor G3"}, {"GS401", "Google Tensor G4"},
        };
        for (String[] e : map) if (c.startsWith(e[0])) return e[1];
        return null;
    }

    /** "Qualcomm Snapdragon 8+ Gen 1", or "Qualcomm SM9999" if the code isn't known. */
    private String fullChipName() {
        String maker = null;
        String model = null;
        if (Build.VERSION.SDK_INT >= 31) {
            maker = Build.SOC_MANUFACTURER;
            model = Build.SOC_MODEL;
        }
        String friendly = chipName(model);
        if (friendly == null) friendly = chipName(Build.HARDWARE);
        if (friendly == null) friendly = chipName(Build.BOARD);

        String brand = null;
        if (friendly != null) {
            if (friendly.startsWith("Snapdragon")) brand = "Qualcomm";
            else if (friendly.startsWith("Exynos")) brand = "Samsung";
            else if (friendly.startsWith("Dimensity")) brand = "MediaTek";
            else if (friendly.startsWith("Google")) brand = null;
            return brand == null ? friendly : brand + " " + friendly;
        }
        // Unknown code: show what the device reports instead of guessing.
        boolean hasModel = model != null && !model.isEmpty() && !Build.UNKNOWN.equalsIgnoreCase(model);
        boolean hasMaker = maker != null && !maker.isEmpty() && !Build.UNKNOWN.equalsIgnoreCase(maker);
        if (hasModel) return (hasMaker ? maker + " " : "") + model;
        return Build.HARDWARE;
    }

    // ---------- OpenGL (for the real GPU name) ----------

    private String[] glInfo;
    private boolean glQueried;

    /** Reads GL_RENDERER / GL_VENDOR / GL_VERSION from a throwaway 1x1 pbuffer context. */
    private String[] queryGl() {
        if (glQueried) return glInfo;
        glQueried = true;

        EGLDisplay dpy = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
        if (dpy == null || dpy == EGL14.EGL_NO_DISPLAY) return null;
        int[] ver = new int[2];
        if (!EGL14.eglInitialize(dpy, ver, 0, ver, 1)) return null;

        EGLSurface surf = EGL14.EGL_NO_SURFACE;
        EGLContext ctx = EGL14.EGL_NO_CONTEXT;
        try {
            int[] cfgAttr = {
                    EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                    EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                    EGL14.EGL_NONE};
            EGLConfig[] cfgs = new EGLConfig[1];
            int[] n = new int[1];
            if (!EGL14.eglChooseConfig(dpy, cfgAttr, 0, cfgs, 0, 1, n, 0) || n[0] == 0) return null;

            int[] ctxAttr = {EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE};
            ctx = EGL14.eglCreateContext(dpy, cfgs[0], EGL14.EGL_NO_CONTEXT, ctxAttr, 0);
            int[] surfAttr = {EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE};
            surf = EGL14.eglCreatePbufferSurface(dpy, cfgs[0], surfAttr, 0);
            if (!EGL14.eglMakeCurrent(dpy, surf, surf, ctx)) return null;

            glInfo = new String[]{
                    GLES20.glGetString(GLES20.GL_RENDERER),
                    GLES20.glGetString(GLES20.GL_VENDOR),
                    GLES20.glGetString(GLES20.GL_VERSION)};
            return glInfo;
        } catch (RuntimeException e) {
            return null;
        } finally {
            EGL14.eglMakeCurrent(dpy, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_CONTEXT);
            if (surf != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(dpy, surf);
            if (ctx != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(dpy, ctx);
            // Deliberately no eglTerminate: Flutter shares this display.
        }
    }

    // ---------- sections ----------

    private List<Map<String, Object>> deviceFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        // Quick glance: name, maker, memory, storage.
        f.add(value("Model name", marketingName(), null));
        f.add(value("Manufacturer", capitalize(Build.MANUFACTURER), null));
        f.add(value("Model number", Build.MODEL, null));

        ActivityManager am = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
        am.getMemoryInfo(mi);
        f.add(field("Total memory", formatBytes(mi.totalMem), AVAILABLE, null));
        f.add(field("Available memory", formatBytes(mi.availMem), AVAILABLE,
                "Changes constantly as apps open and close."));

        StatFs s = new StatFs(Environment.getDataDirectory().getPath());
        f.add(field("Total storage", formatBytes(s.getTotalBytes()), AVAILABLE, null));
        f.add(field("Available storage", formatBytes(s.getAvailableBytes()), AVAILABLE, null));
        return f;
    }

    /** Android build, kernel, display, cameras and feature flags. */
    private List<Map<String, Object>> systemFields() throws Exception {
        List<Map<String, Object>> f = new ArrayList<>(androidFields());
        f.add(value("Device codename", Build.DEVICE,
                "Internal device name, often different from the marketing name."));
        f.add(value("Brand", Build.BRAND, null));
        f.add(value("Board", Build.BOARD, null));
        f.addAll(displayFields());
        f.addAll(cameraFields());
        f.addAll(featureFields());
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

    private List<Map<String, Object>> cpuFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        int cores = Runtime.getRuntime().availableProcessors();

        String code = Build.VERSION.SDK_INT >= 31 ? Build.SOC_MODEL : null;
        f.add(value("Processor", fullChipName(),
                "Name matched from the chip code" + (code != null ? " (" + code + ")." : ".")));
        if (Build.VERSION.SDK_INT >= 31) {
            f.add(value("Chip code", Build.SOC_MODEL, null));
        }
        f.add(value("Hardware", Build.HARDWARE, "Platform name reported by the kernel."));

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

        String[] gl = queryGl();
        if (gl != null && gl[0] != null) {
            f.add(value("GPU", gl[0], "Name reported by the graphics driver."));
            f.add(value("GPU vendor", gl[1], null));
            f.add(value("OpenGL ES driver", gl[2], null));
        } else {
            f.add(field("GPU", null, RESTRICTED,
                    "The graphics driver did not report a name."));
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
        return f;
    }

    private List<Map<String, Object>> thermalFields() {
        List<Map<String, Object>> f = new ArrayList<>();
        PowerManager pm = context.getSystemService(PowerManager.class);

        if (Build.VERSION.SDK_INT >= 29 && pm != null) {
            f.add(field("Thermal status", thermalStatus(pm.getCurrentThermalStatus()), AVAILABLE,
                    "How hot Android considers the phone. None means no throttling."));
        } else {
            f.add(field("Thermal status", null, UNSUPPORTED, "Requires Android 10 (API 29) or newer."));
        }

        if (Build.VERSION.SDK_INT >= 30 && pm != null) {
            float headroom = pm.getThermalHeadroom(10);
            f.add(Float.isNaN(headroom)
                    ? field("Thermal headroom", null, UNSUPPORTED,
                            "This device does not report thermal headroom.")
                    : field("Thermal headroom", String.format(Locale.US, "%.0f%%", headroom * 100),
                            AVAILABLE,
                            "Forecast 10 seconds ahead. 100% is where Android starts throttling."));
        } else {
            f.add(field("Thermal headroom", null, UNSUPPORTED, "Requires Android 11 (API 30) or newer."));
        }

        Intent bi = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        int temp = bi == null ? Integer.MIN_VALUE
                : bi.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
        f.add(temp == Integer.MIN_VALUE
                ? field("Battery temperature", null, UNSUPPORTED, null)
                : field("Battery temperature", String.format(Locale.US, "%.1f °C", temp / 10.0),
                        AVAILABLE, null));

        // Kernel thermal zones are usually blocked for apps; show whatever is readable.
        int shown = 0;
        for (int i = 0; i < 40 && shown < 8; i++) {
            String base = "/sys/class/thermal/thermal_zone" + i;
            String type = readLine(base + "/type");
            Long raw = parseLong(readLine(base + "/temp"));
            if (type == null || raw == null) continue;
            double c = Math.abs(raw) >= 1000 ? raw / 1000.0 : raw;
            f.add(field(type, String.format(Locale.US, "%.1f °C", c), AVAILABLE,
                    shown == 0 ? "Kernel thermal zone sensors." : null));
            shown++;
        }
        if (shown == 0) {
            f.add(field("Thermal zones", null, RESTRICTED, NOT_READABLE_NOTE));
        }
        return f;
    }

    private static String thermalStatus(int s) {
        switch (s) {
            case 0: return "None";
            case 1: return "Light";
            case 2: return "Moderate";
            case 3: return "Severe";
            case 4: return "Critical";
            case 5: return "Emergency";
            case 6: return "Shutdown";
            default: return "Unknown";
        }
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