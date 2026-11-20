package com.jedplatforms.jedtoolkit;

import android.content.Context;
import android.os.Build;
import android.os.Environment;
import android.os.StatFs;
import android.os.storage.StorageManager;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Android port of jedPulseBrain.swift + DiskSpaceProvider.swift.
 *
 * Same test as iOS: 3 passes, each writes a 1 GB temp file in 16 MB chunks
 * (fsync'd before the clock stops) and reads it back; results are averaged.
 *
 * Events are delivered through {@link Listener} from the worker thread, in order.
 * MainActivity forwards them to Flutter on the main thread.
 */
public final class DiskBenchmark {

    public interface Listener {
        void onEvent(Map<String, Object> event);
    }

    private static final int TEST_FILE_MB = 1024;
    private static final int PASSES = 3;
    private static final int CHUNK_MB = 16;
    private static final long REQUIRED_BYTES = 2L * 1024 * 1024 * 1024;
    private static final double UPDATE_INTERVAL_S = 0.15;
    private static final double MIB = 1024.0 * 1024.0;

    private static final class CancelledException extends IOException {
    }

    private final Context context;
    private final Listener listener;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicBoolean running = new AtomicBoolean(false);
    private final AtomicBoolean cancelled = new AtomicBoolean(false);
    private final SimpleDateFormat logFormat =
            new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US);

    // One 16 MB buffer, reused for writing and then for reading.
    private byte[] buffer;

    public DiskBenchmark(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    // ---------------------------------------------------------------- public API

    /** @return false if a test is already running. */
    public boolean start() {
        if (!running.compareAndSet(false, true)) return false;
        cancelled.set(false);
        executor.execute(this::run);
        return true;
    }

    public void cancel() {
        cancelled.set(true);
    }

    public void shutdown() {
        cancelled.set(true);
        executor.shutdownNow();
    }

    /** Port of DiskSpaceProvider: total / available / "optimistic" available, in bytes. */
    public Map<String, Object> getDiskSpace() {
        Map<String, Object> out = new HashMap<>();
        StatFs stat = new StatFs(Environment.getDataDirectory().getPath());
        long total = stat.getTotalBytes();
        long available = stat.getAvailableBytes();
        long optimistic = available;

        // iOS "important usage" counts purgeable space; the Android equivalent is
        // space the system would free by clearing cached data (API 26+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                StorageManager sm = (StorageManager) context.getSystemService(Context.STORAGE_SERVICE);
                if (sm != null) {
                    optimistic = Math.max(available, sm.getAllocatableBytes(StorageManager.UUID_DEFAULT));
                }
            } catch (Throwable ignored) {
            }
        }
        out.put("totalBytes", total);
        out.put("availableBytes", available);
        out.put("optimisticBytes", optimistic);
        return out;
    }

    // ---------------------------------------------------------------- test logic

    private void run() {
        try {
            log("Starting Disk Benchmark Test Suite...");

            File dir = context.getCacheDir();
            long free = new StatFs(dir.getPath()).getAvailableBytes();
            log("System Free Space Detected: " + (free / (1024L * 1024 * 1024)) + " GB");
            if (free <= REQUIRED_BYTES) {
                log("ERROR: Insufficient storage available.");
                complete(false, 0, 0,
                        "Not enough free storage to perform the test. Please free up at least 2 GB of space.");
                return;
            }

            log("Pre-allocating optimized memory buffers to minimize CPU bottlenecks...");
            buffer = new byte[CHUNK_MB * 1024 * 1024];
            new Random().nextBytes(buffer);

            log("Running multi-pass test (" + PASSES + " passes total)...");
            double sumWrite = 0, sumRead = 0;
            for (int pass = 1; pass <= PASSES; pass++) {
                log("--- Launching Pass " + pass + " of " + PASSES + " ---");
                double[] r = runSinglePass(dir, pass);
                sumWrite += r[0];
                sumRead += r[1];
                log(String.format(Locale.US,
                        "Pass %d Complete. Write: %.2f MB/s | Read: %.2f MB/s", pass, r[0], r[1]));
            }

            double avgWrite = sumWrite / PASSES;
            double avgRead = sumRead / PASSES;
            log(String.format(Locale.US,
                    "Benchmark Final Average -> Write: %.2f MB/s | Read: %.2f MB/s", avgWrite, avgRead));
            complete(true, avgWrite, avgRead, null);

        } catch (CancelledException e) {
            Map<String, Object> m = new HashMap<>();
            m.put("type", "complete");
            m.put("success", false);
            m.put("cancelled", true);
            running.set(false);
            emit(m);
        } catch (Throwable t) {
            String msg = t.getMessage() != null ? t.getMessage() : t.getClass().getSimpleName();
            log("Crucial test failure: " + msg);
            complete(false, 0, 0, msg);
        } finally {
            buffer = null; // release the 16 MB buffer
            running.set(false);
        }
    }

    /** @return {writeMBps, readMBps} */
    private double[] runSinglePass(File dir, int pass) throws IOException {
        int chunkBytes = CHUNK_MB * 1024 * 1024;
        int chunkCount = TEST_FILE_MB / CHUNK_MB;
        File file = new File(dir, "jedPulseTestFile_" + UUID.randomUUID() + ".tmp");

        try {
            // ---- Write phase ----
            state("writing", pass);
            log("Executing sequential write stream test...");
            double writeSeconds = performWrite(file, chunkCount, chunkBytes, pass);
            double writeSpeed = TEST_FILE_MB / writeSeconds;

            // ---- Read phase ----
            state("reading", pass);
            log("Executing sequential read stream test...");
            double readSeconds = performRead(file, pass);
            double readSpeed = TEST_FILE_MB / readSeconds;

            return new double[]{writeSpeed, readSpeed};
        } finally {
            log("Cleaning up temporary baseline file at path...");
            //noinspection ResultOfMethodCallIgnored
            file.delete();
        }
    }

    private double performWrite(File file, int chunkCount, int chunkBytes, int pass) throws IOException {
        try (FileOutputStream out = new FileOutputStream(file)) {
            long start = System.nanoTime();
            long lastUpdate = start;
            long bytesSince = 0;

            for (int i = 1; i <= chunkCount; i++) {
                checkCancelled();
                out.write(buffer, 0, chunkBytes);
                bytesSince += chunkBytes;

                long now = System.nanoTime();
                double since = (now - lastUpdate) / 1e9;
                if (since > UPDATE_INTERVAL_S) {
                    double speed = bytesSince / since / MIB;
                    double overall = (pass - 1) / (double) PASSES
                            + ((double) i / chunkCount) / PASSES;
                    progress(overall, speed);
                    lastUpdate = now;
                    bytesSince = 0;
                }
            }

            // Make sure the data is really on the flash before the clock stops.
            out.getFD().sync();
            return (System.nanoTime() - start) / 1e9;
        }
    }

    private double performRead(File file, int pass) throws IOException {
        long totalSize = Math.max(1L, file.length());
        try (FileInputStream in = new FileInputStream(file)) {
            long totalRead = 0;
            long start = System.nanoTime();
            long lastUpdate = start;
            long bytesSince = 0;
            int n;

            while ((n = in.read(buffer, 0, buffer.length)) > 0) {
                checkCancelled();
                bytesSince += n;
                totalRead += n;

                long now = System.nanoTime();
                double since = (now - lastUpdate) / 1e9;
                if (since > UPDATE_INTERVAL_S) {
                    double speed = bytesSince / since / MIB;
                    double overall = (pass - 1) / (double) PASSES
                            + ((double) totalRead / totalSize) / PASSES;
                    progress(overall, speed);
                    lastUpdate = now;
                    bytesSince = 0;
                }
            }
            return (System.nanoTime() - start) / 1e9;
        }
    }

    private void checkCancelled() throws CancelledException {
        if (cancelled.get()) throw new CancelledException();
    }

    // ---------------------------------------------------------------- events

    private void emit(Map<String, Object> m) {
        listener.onEvent(m);
    }

    private void log(String message) {
        Map<String, Object> m = new HashMap<>();
        m.put("type", "log");
        m.put("message", "[" + logFormat.format(new Date()) + "] " + message);
        emit(m);
    }

    private void state(String state, int pass) {
        Map<String, Object> m = new HashMap<>();
        m.put("type", "state");
        m.put("state", state);
        m.put("pass", pass);
        m.put("totalPasses", PASSES);
        emit(m);
    }

    private void progress(double overall, double speedMBps) {
        Map<String, Object> m = new HashMap<>();
        m.put("type", "progress");
        m.put("overall", overall);
        m.put("speed", speedMBps);
        emit(m);
    }

    /** Mirrors iOS reportCompletion: a "finished" state, then the result. */
    private void complete(boolean success, double write, double read, String error) {
        running.set(false); // free before Flutter hears about it so "run again" works instantly
        Map<String, Object> s = new HashMap<>();
        s.put("type", "state");
        s.put("state", "finished");
        s.put("pass", PASSES);
        s.put("totalPasses", PASSES);
        emit(s);

        Map<String, Object> m = new HashMap<>();
        m.put("type", "complete");
        m.put("success", success);
        m.put("writeSpeedMBps", write);
        m.put("readSpeedMBps", read);
        if (error != null) m.put("error", error);
        emit(m);
    }
}