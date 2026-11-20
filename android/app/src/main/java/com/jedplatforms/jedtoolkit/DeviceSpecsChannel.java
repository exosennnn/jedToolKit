package com.jedplatforms.jedtoolkit; // TODO: change to your app's package name

import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.opengl.GLES20;
import android.os.Build;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * Gives Flutter the real SoC name and the GPU renderer string.
 * Register it from MainActivity:
 *
 *   @Override
 *   public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
 *       super.configureFlutterEngine(flutterEngine);
 *       DeviceSpecsChannel.register(flutterEngine);
 *   }
 */
public final class DeviceSpecsChannel {
    private static final String CHANNEL = "jedtoolkit/device_specs";
    private static String cachedGpu = null;

    private DeviceSpecsChannel() {}

    public static void register(@NonNull FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("getSpecs".equals(call.method)) {
                        Map<String, String> map = new HashMap<>();
                        map.put("manufacturer", nn(Build.MANUFACTURER));
                        map.put("model", nn(Build.MODEL));
                        map.put("hardware", nn(Build.HARDWARE));
                        map.put("board", nn(Build.BOARD));
                        if (Build.VERSION.SDK_INT >= 31) {
                            map.put("socManufacturer", nn(Build.SOC_MANUFACTURER));
                            map.put("socModel", nn(Build.SOC_MODEL));
                        }
                        map.put("gpuRenderer", gpuRenderer());
                        result.success(map);
                    } else {
                        result.notImplemented();
                    }
                });
    }

    private static String nn(String s) {
        return s == null ? "" : s;
    }

    /** Reads GL_RENDERER (e.g. "Adreno (TM) 740", "Mali-G715") from a throwaway EGL context. */
    private static synchronized String gpuRenderer() {
        if (cachedGpu != null) return cachedGpu;
        String name = "";
        try {
            EGLDisplay display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
            int[] ver = new int[2];
            if (display != EGL14.EGL_NO_DISPLAY && EGL14.eglInitialize(display, ver, 0, ver, 1)) {
                int[] attribs = {
                        EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                        EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                        EGL14.EGL_NONE
                };
                EGLConfig[] configs = new EGLConfig[1];
                int[] num = new int[1];
                if (EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0) && num[0] > 0) {
                    EGLContext ctx = EGL14.eglCreateContext(
                            display, configs[0], EGL14.EGL_NO_CONTEXT,
                            new int[]{EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE}, 0);
                    EGLSurface surf = EGL14.eglCreatePbufferSurface(
                            display, configs[0],
                            new int[]{EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE}, 0);
                    if (EGL14.eglMakeCurrent(display, surf, surf, ctx)) {
                        String r = GLES20.glGetString(GLES20.GL_RENDERER);
                        if (r != null) name = r;
                    }
                    EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT);
                    EGL14.eglDestroySurface(display, surf);
                    EGL14.eglDestroyContext(display, ctx);
                }
                EGL14.eglTerminate(display);
            }
        } catch (Throwable ignored) {
        }
        cachedGpu = name;
        return name;
    }
}