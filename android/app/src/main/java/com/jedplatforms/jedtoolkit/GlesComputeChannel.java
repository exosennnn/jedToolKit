package com.jedplatforms.jedtoolkit;

import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLExt;
import android.opengl.EGLSurface;
import android.opengl.GLES20;
import android.opengl.GLES30;
import android.opengl.GLES31;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * GPU compute test through OpenGL ES 3.1 compute shaders (pure Java, no NDK code).
 * Measures FMA throughput (GFLOPS) and buffer copy bandwidth (GB/s).
 *
 * Safety: every GPU submission is calibrated to about SLICE_MS and the GPU gets a
 * short break between submissions, so the display never starves. If even the tiny
 * probe run is slow, the test stops instead of risking a freeze.
 *
 * Register from MainActivity:  GlesComputeChannel.register(flutterEngine);
 */
public final class GlesComputeChannel {
    private static final String CHANNEL = "jedtoolkit/gles_compute";

    private static final int THREADS = 1 << 20;     // ALU test threads
    private static final int PROBE_ITERS = 32;      // tiny calibration run
    private static final int MAX_ITERS = 4096;
    private static final double FLOPS_PER_ITER = 16.0; // 8 FMA x 2 FLOPs
    private static final long BW_TOTAL_BYTES = 64L << 20;
    private static final int BW_MAX_REPS = 16;
    private static final int TIMED_RUNS = 7;        // minimum number of timed runs
    private static final double SLICE_MS = 10.0;    // target time of one submission
    private static final double ABORT_MS = 200.0;   // probe slower than this => stop

    private static final String ALU_SRC =
            "#version 310 es\n"
            + "precision highp float;\n"
            + "precision highp int;\n"
            + "layout(local_size_x = 256) in;\n"
            + "layout(std430, binding = 0) buffer Out { float data[]; };\n"
            + "uniform uint iters;\n"
            + "uniform float seed;\n"
            + "void main() {\n"
            + "  uint id = gl_GlobalInvocationID.x;\n"
            + "  float x = float(id) * 1e-6 + seed;\n"
            + "  float a0 = x, a1 = x + 1.0, a2 = x + 2.0, a3 = x + 3.0;\n"
            + "  float a4 = x + 4.0, a5 = x + 5.0, a6 = x + 6.0, a7 = x + 7.0;\n"
            + "  for (uint i = 0u; i < iters; i++) {\n"
            + "    a0 = fma(a0, 0.9999, 0.0001); a1 = fma(a1, 0.9999, 0.0001);\n"
            + "    a2 = fma(a2, 0.9999, 0.0001); a3 = fma(a3, 0.9999, 0.0001);\n"
            + "    a4 = fma(a4, 0.9999, 0.0001); a5 = fma(a5, 0.9999, 0.0001);\n"
            + "    a6 = fma(a6, 0.9999, 0.0001); a7 = fma(a7, 0.9999, 0.0001);\n"
            + "  }\n"
            + "  data[id] = ((a0 + a1) + (a2 + a3)) + ((a4 + a5) + (a6 + a7));\n"
            + "}\n";

    private static final String BW_SRC =
            "#version 310 es\n"
            + "precision highp float;\n"
            + "precision highp int;\n"
            + "layout(local_size_x = 256) in;\n"
            + "layout(std430, binding = 0) buffer Buf { vec4 data[]; };\n"
            + "uniform uint off;\n"
            + "void main() {\n"
            + "  uint id = gl_GlobalInvocationID.x;\n"
            + "  data[id + off] = data[id] * 1.0001;\n"
            + "}\n";

    private static final ExecutorService EXEC = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private GlesComputeChannel() {}

    public static void register(@NonNull FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("run".equals(call.method)) {
                        Number sec = call.argument("seconds");
                        Number warm = call.argument("warmUp");
                        final double seconds = sec == null ? 3.0 : sec.doubleValue();
                        final double warmUp = warm == null ? 1.0 : warm.doubleValue();
                        // EGL context + GL calls all stay on this one worker thread.
                        EXEC.execute(() -> {
                            final Map<String, Object> out = runBench(seconds, warmUp);
                            MAIN.post(() -> result.success(out));
                        });
                    } else {
                        result.notImplemented();
                    }
                });
    }

    // ------------------------------------------------------------------ bench

    private static Map<String, Object> runBench(double seconds, double warmUp) {
        EGLDisplay display = EGL14.EGL_NO_DISPLAY;
        EGLContext ctx = EGL14.EGL_NO_CONTEXT;
        EGLSurface surf = EGL14.EGL_NO_SURFACE;
        try {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
            int[] ver = new int[2];
            if (display == null || display.equals(EGL14.EGL_NO_DISPLAY)
                    || !EGL14.eglInitialize(display, ver, 0, ver, 1)) {
                return fail("EGL is not available");
            }

            int[] attribs = {
                    EGL14.EGL_RENDERABLE_TYPE, EGLExt.EGL_OPENGL_ES3_BIT_KHR,
                    EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                    EGL14.EGL_NONE
            };
            EGLConfig[] configs = new EGLConfig[1];
            int[] num = new int[1];
            if (!EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0) || num[0] <= 0) {
                return fail("No OpenGL ES 3 config found on this device");
            }
            ctx = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT,
                    new int[]{EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE}, 0);
            if (ctx == null || ctx.equals(EGL14.EGL_NO_CONTEXT)) {
                return fail("Could not create an OpenGL ES 3 context");
            }
            surf = EGL14.eglCreatePbufferSurface(display, configs[0],
                    new int[]{EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE}, 0);
            if (!EGL14.eglMakeCurrent(display, surf, surf, ctx)) {
                return fail("eglMakeCurrent failed");
            }
            return measure(seconds, warmUp);
        } catch (Throwable t) {
            return fail(String.valueOf(t.getMessage()));
        } finally {
            try {
                if (display != null && !display.equals(EGL14.EGL_NO_DISPLAY)) {
                    EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE,
                            EGL14.EGL_NO_CONTEXT);
                    if (surf != null && !surf.equals(EGL14.EGL_NO_SURFACE)) {
                        EGL14.eglDestroySurface(display, surf);
                    }
                    if (ctx != null && !ctx.equals(EGL14.EGL_NO_CONTEXT)) {
                        EGL14.eglDestroyContext(display, ctx);
                    }
                    // No eglTerminate: Flutter uses the same default display.
                }
            } catch (Throwable ignored) {
            }
        }
    }

    private static Map<String, Object> measure(double seconds, double warmUp)
            throws InterruptedException {
        String renderer = GLES20.glGetString(GLES20.GL_RENDERER);
        String version = GLES20.glGetString(GLES20.GL_VERSION);
        Matcher m = Pattern.compile("OpenGL ES (\\d+)\\.(\\d+)")
                .matcher(version == null ? "" : version);
        if (!m.find()) return fail("Unknown OpenGL ES version: " + version);
        int major = Integer.parseInt(m.group(1));
        int minor = Integer.parseInt(m.group(2));
        if (major * 10 + minor < 31) {
            return fail("This GPU driver only offers OpenGL ES " + major + "." + minor
                    + " (compute shaders need 3.1)");
        }

        int[] tmp = new int[1];
        GLES20.glGetIntegerv(GLES31.GL_MAX_COMPUTE_WORK_GROUP_INVOCATIONS, tmp, 0);
        if (tmp[0] < 256) return fail("GPU does not support 256-thread work groups");
        GLES20.glGetIntegerv(GLES31.GL_MAX_SHADER_STORAGE_BLOCK_SIZE, tmp, 0);
        long maxBlock = tmp[0] > 0 ? tmp[0] : BW_TOTAL_BYTES;

        // ---- ALU (FMA) throughput
        int aluIters;
        double aluMs;
        double aluSustained;
        {
            int prog = buildProgram(ALU_SRC);
            int[] buf = new int[1];
            GLES20.glGenBuffers(1, buf, 0);
            GLES20.glBindBuffer(GLES31.GL_SHADER_STORAGE_BUFFER, buf[0]);
            GLES20.glBufferData(GLES31.GL_SHADER_STORAGE_BUFFER, THREADS * 4, null,
                    GLES20.GL_DYNAMIC_DRAW);
            GLES30.glBindBufferBase(GLES31.GL_SHADER_STORAGE_BUFFER, 0, buf[0]);
            GLES20.glUseProgram(prog);
            int locIters = GLES20.glGetUniformLocation(prog, "iters");
            int locSeed = GLES20.glGetUniformLocation(prog, "seed");
            GLES20.glUniform1f(locSeed, 0.5f);

            double probe = 0;
            for (int i = 0; i < 2; i++) {  // 1st run = warm-up, 2nd = probe
                GLES30.glUniform1ui(locIters, PROBE_ITERS);
                probe = dispatchMs(THREADS / 256, 1);
                breathe();
            }
            if (probe > ABORT_MS) {
                return fail("GPU is too slow or busy for the compute test (skipped to avoid a hang)");
            }
            aluIters = (int) Math.min(MAX_ITERS,
                    Math.max(PROBE_ITERS, SLICE_MS / (Math.max(probe, 0.001) / PROBE_ITERS)));

            // Warm-up: keep the GPU busy so its clock ramps up before timing starts.
            long w0 = System.nanoTime();
            while ((System.nanoTime() - w0) / 1e9 < warmUp) {
                GLES30.glUniform1ui(locIters, aluIters);
                dispatchMs(THREADS / 256, 1);
                breathe();
            }
            List<Double> t = new ArrayList<>();
            long t0 = System.nanoTime();
            for (int i = 0; i < TIMED_RUNS || (System.nanoTime() - t0) / 1e9 < seconds; i++) {
                GLES30.glUniform1ui(locIters, aluIters);
                t.add(dispatchMs(THREADS / 256, 1));
                breathe();
            }
            aluMs = median(t);
            aluSustained = sustained(t);
            GLES20.glUseProgram(0);
            GLES20.glDeleteProgram(prog);
            GLES20.glDeleteBuffers(1, buf, 0);
        }

        // ---- memory bandwidth (copy first half of the buffer into the second half)
        int half = (int) ((Math.min(BW_TOTAL_BYTES, maxBlock) / 2 / 16) / 256 * 256);
        int bwReps;
        double bwMs;
        double bwSustained;
        {
            int prog = buildProgram(BW_SRC);
            int[] buf = new int[1];
            GLES20.glGenBuffers(1, buf, 0);
            GLES20.glBindBuffer(GLES31.GL_SHADER_STORAGE_BUFFER, buf[0]);
            GLES20.glBufferData(GLES31.GL_SHADER_STORAGE_BUFFER, half * 16 * 2, null,
                    GLES20.GL_DYNAMIC_DRAW);
            GLES30.glBindBufferBase(GLES31.GL_SHADER_STORAGE_BUFFER, 0, buf[0]);
            GLES20.glUseProgram(prog);
            GLES30.glUniform1ui(GLES20.glGetUniformLocation(prog, "off"), half);

            double probe = 0;
            for (int i = 0; i < 2; i++) {
                probe = dispatchMs(half / 256, 1);
                breathe();
            }
            if (probe > ABORT_MS) {
                return fail("GPU memory is too slow or busy for the bandwidth test (skipped)");
            }
            bwReps = (int) Math.min(BW_MAX_REPS, Math.max(1.0, SLICE_MS / Math.max(probe, 0.001)));

            long w0 = System.nanoTime();
            while ((System.nanoTime() - w0) / 1e9 < warmUp) {
                dispatchMs(half / 256, bwReps);
                breathe();
            }
            List<Double> t = new ArrayList<>();
            long t0 = System.nanoTime();
            for (int i = 0; i < TIMED_RUNS || (System.nanoTime() - t0) / 1e9 < seconds; i++) {
                t.add(dispatchMs(half / 256, bwReps));
                breathe();
            }
            bwMs = median(t);
            bwSustained = sustained(t);
            GLES20.glUseProgram(0);
            GLES20.glDeleteProgram(prog);
            GLES20.glDeleteBuffers(1, buf, 0);
        }

        Map<String, Object> out = new HashMap<>();
        out.put("ok", true);
        out.put("device", (renderer == null ? "GPU" : renderer) + " (OpenGL ES " + major + "." + minor + ")");
        out.put("gflops", (double) THREADS * aluIters * FLOPS_PER_ITER / (aluMs * 1e6));
        out.put("gbps", (double) half * 16.0 * 2.0 * bwReps / (bwMs * 1e6));
        out.put("aluSustained", aluSustained);
        out.put("bwSustained", bwSustained);
        return out;
    }

    // ---------------------------------------------------------------- helpers

    /** Runs `reps` back-to-back dispatches and returns the wall time until the GPU finished. */
    private static double dispatchMs(int groups, int reps) {
        long t0 = System.nanoTime();
        for (int r = 0; r < reps; r++) {
            GLES31.glDispatchCompute(groups, 1, 1);
            if (r + 1 < reps) GLES31.glMemoryBarrier(GLES31.GL_SHADER_STORAGE_BARRIER_BIT);
        }
        GLES20.glFinish();
        double ms = (System.nanoTime() - t0) / 1e6;
        int e = GLES20.glGetError();
        if (e != GLES20.GL_NO_ERROR) {
            throw new IllegalStateException("OpenGL error 0x" + Integer.toHexString(e));
        }
        return ms;
    }

    private static int buildProgram(String src) {
        int sh = GLES20.glCreateShader(GLES31.GL_COMPUTE_SHADER);
        GLES20.glShaderSource(sh, src);
        GLES20.glCompileShader(sh);
        int[] ok = new int[1];
        GLES20.glGetShaderiv(sh, GLES20.GL_COMPILE_STATUS, ok, 0);
        if (ok[0] == 0) {
            String log = GLES20.glGetShaderInfoLog(sh);
            GLES20.glDeleteShader(sh);
            throw new IllegalStateException("Compute shader failed to compile: " + log);
        }
        int p = GLES20.glCreateProgram();
        GLES20.glAttachShader(p, sh);
        GLES20.glLinkProgram(p);
        GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, ok, 0);
        GLES20.glDeleteShader(sh);
        if (ok[0] == 0) {
            String log = GLES20.glGetProgramInfoLog(p);
            GLES20.glDeleteProgram(p);
            throw new IllegalStateException("Compute program failed to link: " + log);
        }
        return p;
    }

    /** Lets SurfaceFlinger draw between GPU submissions. */
    private static void breathe() throws InterruptedException {
        Thread.sleep(2);
    }

    private static double median(List<Double> v) {
        List<Double> s = new ArrayList<>(v);
        Collections.sort(s);
        return s.get(s.size() / 2);
    }

    /** Speed of the last quarter of the runs as a percentage of the first quarter. */
    private static double sustained(List<Double> ms) {
        if (ms.size() < 8) return 100.0;
        int q = ms.size() / 4;
        double first = median(ms.subList(0, q));
        double last = median(ms.subList(ms.size() - q, ms.size()));
        return first / last * 100.0;
    }

    private static Map<String, Object> fail(String msg) {
        Map<String, Object> out = new HashMap<>();
        out.put("ok", false);
        out.put("error", msg);
        return out;
    }
}