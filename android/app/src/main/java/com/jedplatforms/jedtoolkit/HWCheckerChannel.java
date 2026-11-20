package com.jedplatforms.jedtoolkit;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.BatteryManager;
import android.os.Build;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.provider.Settings;
import android.telephony.TelephonyManager;
import android.view.KeyEvent;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public final class HWCheckerChannel {
    private static final String METHOD_CHANNEL = "jedtoolkit/hwchecker";
    private static final String SENSOR_CHANNEL = "jedtoolkit/hwchecker_sensors";
    private static final String KEY_CHANNEL = "jedtoolkit/hwchecker_keys";

    private static EventChannel.EventSink keySink;
    private static boolean interceptHardwareKeys = false;
    private static String rearTorchCameraId = null;

    private HWCheckerChannel() {}

    public static void register(@NonNull Activity activity, @NonNull FlutterEngine engine) {
        final Context app = activity.getApplicationContext();

        // 1. MethodChannel for one-shot hardware queries & actions
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), METHOD_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        // --- LED Flash ---
                        case "setTorch": {
                            boolean enabled = Boolean.TRUE.equals(call.argument("enabled"));
                            try {
                                CameraManager cm = (CameraManager) app.getSystemService(Context.CAMERA_SERVICE);
                                if (rearTorchCameraId == null) {
                                    for (String id : cm.getCameraIdList()) {
                                        CameraCharacteristics c = cm.getCameraCharacteristics(id);
                                        Boolean hasFlash = c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                                        Integer facing = c.get(CameraCharacteristics.LENS_FACING);
                                        if (Boolean.TRUE.equals(hasFlash) && facing != null
                                                && facing == CameraCharacteristics.LENS_FACING_BACK) {
                                            rearTorchCameraId = id;
                                            break;
                                        }
                                    }
                                }
                                if (rearTorchCameraId == null) {
                                    result.error("NO_TORCH", "Device does not have a rear LED flash.", null);
                                } else {
                                    cm.setTorchMode(rearTorchCameraId, enabled);
                                    result.success(true);
                                }
                            } catch (Exception e) {
                                result.error("TORCH_ERROR", e.getMessage(), null);
                            }
                            break;
                        }

                        // --- Haptics / Vibration ---
                        case "vibrate": {
                            int durationMs = call.argument("durationMs") != null
                                    ? ((Number) call.argument("durationMs")).intValue() : 100;
                            int amplitude = call.argument("amplitude") != null
                                    ? ((Number) call.argument("amplitude")).intValue() : VibrationEffect.DEFAULT_AMPLITUDE;
                            Vibrator vibrator = getVibrator(app);
                            if (vibrator == null || !vibrator.hasVibrator()) {
                                result.success(false);
                                break;
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator.vibrate(VibrationEffect.createOneShot(durationMs, amplitude));
                            } else {
                                vibrator.vibrate(durationMs);
                            }
                            result.success(true);
                            break;
                        }

                        // --- Screen Brightness ---
                        case "getBrightness": {
                            float winB = activity.getWindow().getAttributes().screenBrightness;
                            if (winB >= 0f) {
                                result.success((double) winB);
                            } else {
                                try {
                                    int sysB = Settings.System.getInt(app.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS);
                                    result.success(Math.max(0.0, Math.min(1.0, sysB / 255.0)));
                                } catch (Exception e) {
                                    result.success(0.5);
                                }
                            }
                            break;
                        }
                        case "setBrightness": {
                            double val = call.argument("value") != null
                                    ? ((Number) call.argument("value")).doubleValue() : -1.0;
                            activity.runOnUiThread(() -> {
                                WindowManager.LayoutParams lp = activity.getWindow().getAttributes();
                                lp.screenBrightness = (float) val;
                                activity.getWindow().setAttributes(lp);
                                result.success(null);
                            });
                            break;
                        }

                        // --- Connectivity (Wi-Fi / Cellular / BT) ---
                        case "getConnectivityStatus": {
                            Map<String, Object> out = new HashMap<>();
                            ConnectivityManager cm = (ConnectivityManager) app.getSystemService(Context.CONNECTIVITY_SERVICE);
                            boolean wifiConnected = false;
                            boolean cellConnected = false;
                            boolean otherConnected = false;

                            if (cm != null) {
                                Network active = cm.getActiveNetwork();
                                NetworkCapabilities caps = active != null ? cm.getNetworkCapabilities(active) : null;
                                if (caps != null) {
                                    wifiConnected = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI);
                                    cellConnected = caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR);
                                    otherConnected = !wifiConnected && !cellConnected
                                            && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);
                                }
                            }
                            out.put("wifiConnected", wifiConnected);
                            out.put("cellularConnected", cellConnected);
                            out.put("otherConnected", otherConnected);

                            TelephonyManager tm = (TelephonyManager) app.getSystemService(Context.TELEPHONY_SERVICE);
                            String carrier = tm != null ? tm.getNetworkOperatorName() : "";
                            out.put("carrierName", (carrier == null || carrier.isEmpty()) ? "No SIM / Unknown" : carrier);

                            BluetoothManager bm = (BluetoothManager) app.getSystemService(Context.BLUETOOTH_SERVICE);
                            BluetoothAdapter adapter = bm != null ? bm.getAdapter() : null;
                            if (adapter == null) {
                                out.put("btState", "unsupported");
                            } else if (adapter.isEnabled()) {
                                out.put("btState", "poweredOn");
                            } else {
                                out.put("btState", "poweredOff");
                            }
                            result.success(out);
                            break;
                        }

                        // --- Battery & Connected Bluetooth Accessories ---
                        case "getBatteryAndAccessories": {
                            result.success(collectBatteryAndAccessories(app));
                            break;
                        }

                        // --- Hardware Key Interception Toggle ---
                        case "setKeyIntercept": {
                            interceptHardwareKeys = Boolean.TRUE.equals(call.argument("enabled"));
                            result.success(null);
                            break;
                        }

                        // --- Share Text ---
                        case "shareText": {
                            String text = call.argument("text");
                            if (text != null) {
                                Intent sendIntent = new Intent(Intent.ACTION_SEND);
                                sendIntent.setType("text/plain");
                                sendIntent.putExtra(Intent.EXTRA_TEXT, text);
                                Intent chooser = Intent.createChooser(sendIntent, "Share Test Results");
                                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                                app.startActivity(chooser);
                            }
                            result.success(null);
                            break;
                        }

                        default:
                            result.notImplemented();
                            break;
                    }
                });

        // 2. EventChannel for live SensorManager stream
        new EventChannel(engine.getDartExecutor().getBinaryMessenger(), SENSOR_CHANNEL)
                .setStreamHandler(new SensorStreamHandler(app));

        // 3. EventChannel for Physical Button presses
        new EventChannel(engine.getDartExecutor().getBinaryMessenger(), KEY_CHANNEL)
                .setStreamHandler(new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object args, EventChannel.EventSink events) {
                        keySink = events;
                    }

                    @Override
                    public void onCancel(Object args) {
                        keySink = null;
                        interceptHardwareKeys = false;
                    }
                });
    }

    public static boolean handleKeyEvent(KeyEvent event) {
        if (!interceptHardwareKeys || keySink == null) return false;
        int code = event.getKeyCode();
        if (code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                Map<String, Object> payload = new HashMap<>();
                payload.put("keyCode", code);
                keySink.success(payload);
            }
            return true;
        }
        return false;
    }

    private static Vibrator getVibrator(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            VibratorManager vm = (VibratorManager) context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
            return vm != null ? vm.getDefaultVibrator() : null;
        }
        return (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
    }

    @SuppressLint("MissingPermission")
    private static Map<String, Object> collectBatteryAndAccessories(Context context) {
        Map<String, Object> out = new HashMap<>();
        Intent bi = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        int level = 0;
        String state = "Unknown";
        String powerSource = "Internal Battery Power";
        boolean isCharging = false;

        if (bi != null) {
            int rawLevel = bi.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
            int scale = bi.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
            if (rawLevel >= 0 && scale > 0) level = (rawLevel * 100 / scale);

            int status = bi.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
            int plugged = bi.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0);
            isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING
                    || status == BatteryManager.BATTERY_STATUS_FULL
                    || plugged != 0;

            if (status == BatteryManager.BATTERY_STATUS_FULL) {
                state = "Fully Charged";
                powerSource = "AC Power (Fully Charged)";
            } else if (isCharging) {
                state = "Charging";
                powerSource = plugged == BatteryManager.BATTERY_PLUGGED_WIRELESS
                        ? "Wireless Charger" : "External USB / AC Power";
            } else {
                state = "Discharging";
            }
        }

        PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        boolean lowPower = pm != null && pm.isPowerSaveMode();
        String thermal = "Normal";
        if (pm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            int ts = pm.getCurrentThermalStatus();
            if (ts == PowerManager.THERMAL_STATUS_MODERATE) thermal = "Fair";
            else if (ts == PowerManager.THERMAL_STATUS_SEVERE) thermal = "Serious (Warm)";
            else if (ts >= PowerManager.THERMAL_STATUS_CRITICAL) thermal = "Critical (Hot)";
        }

        out.put("level", level);
        out.put("state", state);
        out.put("isCharging", isCharging);
        out.put("powerSource", powerSource);
        out.put("lowPowerMode", lowPower);
        out.put("thermalState", thermal);

        List<Map<String, Object>> accessories = new ArrayList<>();
        try {
            BluetoothManager bm = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
            BluetoothAdapter adapter = bm != null ? bm.getAdapter() : null;
            if (adapter != null && adapter.isEnabled()) {
                Set<BluetoothDevice> bonded = adapter.getBondedDevices();
                if (bonded != null) {
                    for (BluetoothDevice dev : bonded) {
                        boolean connected = isDeviceConnected(dev);
                        if (!connected) continue;
                        Map<String, Object> item = new HashMap<>();
                        item.put("id", dev.getAddress());
                        item.put("name", dev.getName() != null ? dev.getName() : "Bluetooth Accessory");
                        item.put("type", "Bluetooth Accessory");
                        item.put("isConnected", true);
                        int bat = getDeviceBatteryLevel(dev);
                        if (bat >= 0 && bat <= 100) item.put("batteryLevel", bat);
                        accessories.add(item);
                    }
                }
            }
        } catch (Throwable ignored) {}

        out.put("accessories", accessories);
        return out;
    }

    private static boolean isDeviceConnected(BluetoothDevice device) {
        try {
            Method m = device.getClass().getMethod("isConnected");
            return Boolean.TRUE.equals(m.invoke(device));
        } catch (Throwable t) {
            return false;
        }
    }

    private static int getDeviceBatteryLevel(BluetoothDevice device) {
        try {
            Method m = device.getClass().getMethod("getBatteryLevel");
            Object res = m.invoke(device);
            return res instanceof Integer ? (Integer) res : -1;
        } catch (Throwable t) {
            return -1;
        }
    }

    private static final class SensorStreamHandler implements EventChannel.StreamHandler, SensorEventListener {
        private final SensorManager sm;
        private EventChannel.EventSink sink;
        private float maxProximityRange = 5.0f;
        private float lastProximity = Float.NaN;

        SensorStreamHandler(Context context) {
            this.sm = (SensorManager) context.getSystemService(Context.SENSOR_SERVICE);
        }

        @Override
        public void onListen(Object arguments, EventChannel.EventSink events) {
            this.sink = events;
            lastProximity = Float.NaN;
            String type = arguments instanceof String ? (String) arguments : "";
            int sensorType = switch (type) {
                case "accelerometer" -> Sensor.TYPE_ACCELEROMETER;
                case "gyroscope" -> Sensor.TYPE_GYROSCOPE;
                case "magnetometer" -> Sensor.TYPE_ROTATION_VECTOR;
                case "proximity" -> Sensor.TYPE_PROXIMITY;
                default -> -1;
            };
            Sensor sensor = null;
            if (sm != null && sensorType != -1) {
                sm.unregisterListener(this); // never keep a stale registration
                if (sensorType == Sensor.TYPE_PROXIMITY) {
                    // Prefer the wake-up proximity sensor (what Samsung/OEM tools use),
                    // then the default one, then whatever proximity sensor is listed.
                    sensor = sm.getDefaultSensor(Sensor.TYPE_PROXIMITY, true);
                    if (sensor == null) sensor = sm.getDefaultSensor(Sensor.TYPE_PROXIMITY);
                    if (sensor == null) {
                        List<Sensor> all = sm.getSensorList(Sensor.TYPE_PROXIMITY);
                        if (!all.isEmpty()) sensor = all.get(0);
                    }
                } else {
                    sensor = sm.getDefaultSensor(sensorType);
                }
            }
            if (sensor == null) {
                events.error("UNAVAILABLE", "Sensor not available on this device.", null);
                return;
            }
            boolean ok;
            if (sensorType == Sensor.TYPE_PROXIMITY) {
                maxProximityRange = sensor.getMaximumRange();
                // On-change sensor: NORMAL rate is plenty and works on every OEM.
                ok = sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL);
            } else {
                ok = sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME);
            }
            if (!ok) {
                events.error("UNAVAILABLE", "Could not register the sensor listener.", null);
            }
        }

        @Override
        public void onCancel(Object arguments) {
            if (sm != null) sm.unregisterListener(this);
            sink = null;
        }

        @Override
        public void onSensorChanged(SensorEvent event) {
            if (sink == null) return;
            Map<String, Object> data = new HashMap<>();
            int type = event.sensor.getType();
            if (type == Sensor.TYPE_ACCELEROMETER) {
                data.put("x", event.values[0] / 9.80665);
                data.put("y", event.values[1] / 9.80665);
                data.put("z", event.values[2] / 9.80665);
            } else if (type == Sensor.TYPE_GYROSCOPE) {
                data.put("rx", event.values[0]);
                data.put("ry", event.values[1]);
                data.put("rz", event.values[2]);
            } else if (type == Sensor.TYPE_ROTATION_VECTOR) {
                float[] rotMatrix = new float[9];
                float[] orientation = new float[3];
                SensorManager.getRotationMatrixFromVector(rotMatrix, event.values);
                SensorManager.getOrientation(rotMatrix, orientation);
                data.put("yaw", (double) orientation[0]);
                data.put("pitch", (double) orientation[1]);
                data.put("roll", (double) orientation[2]);
            } else if (type == Sensor.TYPE_PROXIMITY) {
                float dist = event.values[0];
                // Only forward real changes; some phones repeat the same reading constantly.
                if (dist == lastProximity) return;
                lastProximity = dist;
                float max = event.sensor.getMaximumRange();
                // Most phones are binary: "near" = 0 (or a small value), "far" = max range.
                // Anything below the far value counts as covered.
                data.put("isCovered", dist < max);
                data.put("distance", (double) dist);
                data.put("maxRange", (double) max);
            }
            sink.success(data);
        }

        @Override
        public void onAccuracyChanged(Sensor sensor, int accuracy) {}
    }
}