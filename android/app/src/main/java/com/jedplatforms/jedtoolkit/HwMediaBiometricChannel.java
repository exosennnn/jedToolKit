package com.jedplatforms.jedtoolkit;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaPlayer;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public final class HwMediaBiometricChannel {
    private static final String METHOD_CHANNEL = "jedtoolkit/hwchecker_media";
    private static final String MIC_LEVEL_CHANNEL = "jedtoolkit/hwchecker_mic_level";

    private static final ExecutorService EXEC = Executors.newCachedThreadPool();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private static final AtomicBoolean isPlayingTone = new AtomicBoolean(false);
    private static final AtomicBoolean isRecording = new AtomicBoolean(false);
    private static EventChannel.EventSink micLevelSink;
    private static MediaPlayer micPlayer;

    private HwMediaBiometricChannel() {}

    public static void register(@NonNull Activity activity, @NonNull FlutterEngine engine) {
        final Context app = activity.getApplicationContext();

        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), METHOD_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        // ---------------- Speaker 440 Hz Tone ----------------
                        case "startSpeakerTone": {
                            if (isPlayingTone.compareAndSet(false, true)) {
                                EXEC.execute(() -> playSineTone(app));
                            }
                            result.success(null);
                            break;
                        }
                        case "stopSpeakerTone": {
                            isPlayingTone.set(false);
                            result.success(null);
                            break;
                        }

                        // ---------------- Microphone Record & Playback ----------------
                        case "startMicRecord": {
                            if (ContextCompat.checkSelfPermission(app, Manifest.permission.RECORD_AUDIO)
                                    != PackageManager.PERMISSION_GRANTED) {
                                ActivityCompat.requestPermissions(
                                        activity,
                                        new String[]{Manifest.permission.RECORD_AUDIO},
                                        701
                                );
                                result.error("PERMISSION_REQUIRED", "Microphone permission is required.", null);
                                break;
                            }
                            stopMicPlayback();
                            if (isRecording.compareAndSet(false, true)) {
                                File outFile = new File(app.getCacheDir(), "jed_mic_test.wav");
                                EXEC.execute(() -> recordWav(outFile));
                            }
                            result.success(true);
                            break;
                        }
                        case "stopMicRecord": {
                            isRecording.set(false);
                            result.success(null);
                            break;
                        }
                        case "playMicRecording": {
                            isRecording.set(false);
                            File wavFile = new File(app.getCacheDir(), "jed_mic_test.wav");
                            if (!wavFile.exists() || wavFile.length() <= 44) {
                                result.error("NO_RECORDING", "No recorded audio available.", null);
                                break;
                            }
                            stopMicPlayback();
                            try {
                                micPlayer = new MediaPlayer();
                                micPlayer.setDataSource(wavFile.getAbsolutePath());
                                micPlayer.setOnCompletionListener(mp -> {
                                    stopMicPlayback();
                                    if (micLevelSink != null) {
                                        Map<String, Object> ev = new HashMap<>();
                                        ev.put("playbackDone", true);
                                        MAIN.post(() -> {
                                            if (micLevelSink != null) micLevelSink.success(ev);
                                        });
                                    }
                                });
                                micPlayer.prepare();
                                micPlayer.start();
                                result.success(true);
                            } catch (IOException e) {
                                result.error("PLAY_ERROR", e.getMessage(), null);
                            }
                            break;
                        }
                        case "stopMicPlayback": {
                            stopMicPlayback();
                            result.success(null);
                            break;
                        }

                        // ---------------- Biometric Authentication ----------------
                        case "authenticateBiometric": {
                            authenticateBiometric(activity, app, result);
                            break;
                        }

                        // ---------------- Camera Runtime Permission ----------------
                        case "requestCameraPermission": {
                            if (ContextCompat.checkSelfPermission(app, Manifest.permission.CAMERA)
                                    == PackageManager.PERMISSION_GRANTED) {
                                result.success(true);
                            } else {
                                ActivityCompat.requestPermissions(
                                        activity,
                                        new String[]{Manifest.permission.CAMERA},
                                        702
                                );
                                result.success(false);
                            }
                            break;
                        }

                        default:
                            result.notImplemented();
                            break;
                    }
                });

        new EventChannel(engine.getDartExecutor().getBinaryMessenger(), MIC_LEVEL_CHANNEL)
                .setStreamHandler(new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object arguments, EventChannel.EventSink events) {
                        micLevelSink = events;
                    }

                    @Override
                    public void onCancel(Object arguments) {
                        micLevelSink = null;
                        isRecording.set(false);
                        stopMicPlayback();
                    }
                });
    }

    // --- 440 Hz Pure Sine Wave Generator ---
    private static void playSineTone(Context context) {
        final int sampleRate = 44100;
        final double freq = 440.0;
        final int minBuf = AudioTrack.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT);

        AudioTrack track = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                .setAudioFormat(new AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build())
                .setBufferSizeInBytes(Math.max(minBuf, 4096))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build();

        short[] buffer = new short[1024];
        double phase = 0.0;
        double phaseStep = 2.0 * Math.PI * freq / sampleRate;

        try {
            track.play();
            while (isPlayingTone.get()) {
                for (int i = 0; i < buffer.length; i++) {
                    buffer[i] = (short) (Math.sin(phase) * 24000.0);
                    phase += phaseStep;
                    if (phase >= 2.0 * Math.PI) phase -= 2.0 * Math.PI;
                }
                track.write(buffer, 0, buffer.length);
            }
        } catch (Throwable ignored) {
        } finally {
            isPlayingTone.set(false);
            try {
                track.stop();
                track.release();
            } catch (Throwable ignored) {}
        }
    }

    // --- PCM -> WAV Recorder + Live Normalized RMS Level ---
    @SuppressLint("MissingPermission")
    private static void recordWav(File outFile) {
        final int sampleRate = 44100;
        final int minBuf = AudioRecord.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        final int bufSize = Math.max(minBuf, 2048);

        AudioRecord recorder = new AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufSize
        );

        short[] shorts = new short[bufSize / 2];
        byte[] bytes = new byte[shorts.length * 2];
        long totalAudioBytes = 0;

        try (FileOutputStream fos = new FileOutputStream(outFile)) {
            writeWavHeader(fos, 0, sampleRate, 1, 16);
            recorder.startRecording();

            while (isRecording.get()) {
                int read = recorder.read(shorts, 0, shorts.length);
                if (read > 0) {
                    double sumSq = 0.0;
                    for (int i = 0; i < read; i++) {
                        short s = shorts[i];
                        sumSq += (double) s * s;
                        bytes[i * 2] = (byte) (s & 0xFF);
                        bytes[i * 2 + 1] = (byte) ((s >> 8) & 0xFF);
                    }
                    fos.write(bytes, 0, read * 2);
                    totalAudioBytes += read * 2L;

                    double rms = Math.sqrt(sumSq / read);
                    // Normalize speech level (0.0 to 1.0)
                    double norm = Math.min(1.0, Math.max(0.0, rms / 9000.0));
                    Map<String, Object> ev = new HashMap<>();
                    ev.put("level", norm);
                    MAIN.post(() -> {
                        if (micLevelSink != null) micLevelSink.success(ev);
                    });
                }
            }
            fos.flush();
            updateWavHeader(outFile, totalAudioBytes);
        } catch (Throwable ignored) {
        } finally {
            isRecording.set(false);
            try {
                recorder.stop();
                recorder.release();
            } catch (Throwable ignored) {}
        }
    }

    private static void writeWavHeader(FileOutputStream out, long audioLen, int sampleRate, int channels, int bitsPerSample) throws IOException {
        long totalDataLen = audioLen + 36;
        long byteRate = (long) sampleRate * channels * bitsPerSample / 8;
        byte[] header = new byte[44];
        header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
        header[4] = (byte) (totalDataLen & 0xff);
        header[5] = (byte) ((totalDataLen >> 8) & 0xff);
        header[6] = (byte) ((totalDataLen >> 16) & 0xff);
        header[7] = (byte) ((totalDataLen >> 24) & 0xff);
        header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';
        header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
        header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0;
        header[20] = 1; header[21] = 0;
        header[22] = (byte) channels; header[23] = 0;
        header[24] = (byte) (sampleRate & 0xff);
        header[25] = (byte) ((sampleRate >> 8) & 0xff);
        header[26] = (byte) ((sampleRate >> 16) & 0xff);
        header[27] = (byte) ((sampleRate >> 24) & 0xff);
        header[28] = (byte) (byteRate & 0xff);
        header[29] = (byte) ((byteRate >> 8) & 0xff);
        header[30] = (byte) ((byteRate >> 16) & 0xff);
        header[31] = (byte) ((byteRate >> 24) & 0xff);
        header[32] = (byte) (channels * bitsPerSample / 8); header[33] = 0;
        header[34] = (byte) bitsPerSample; header[35] = 0;
        header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
        header[40] = (byte) (audioLen & 0xff);
        header[41] = (byte) ((audioLen >> 8) & 0xff);
        header[42] = (byte) ((audioLen >> 16) & 0xff);
        header[43] = (byte) ((audioLen >> 24) & 0xff);
        out.write(header, 0, 44);
    }

    private static void updateWavHeader(File file, long audioLen) {
        try (RandomAccessFile raf = new RandomAccessFile(file, "rw")) {
            long totalDataLen = audioLen + 36;
            raf.seek(4);
            raf.write(new byte[]{
                    (byte) (totalDataLen & 0xff),
                    (byte) ((totalDataLen >> 8) & 0xff),
                    (byte) ((totalDataLen >> 16) & 0xff),
                    (byte) ((totalDataLen >> 24) & 0xff)
            });
            raf.seek(40);
            raf.write(new byte[]{
                    (byte) (audioLen & 0xff),
                    (byte) ((audioLen >> 8) & 0xff),
                    (byte) ((audioLen >> 16) & 0xff),
                    (byte) ((audioLen >> 24) & 0xff)
            });
        } catch (IOException ignored) {}
    }

    private static void stopMicPlayback() {
        if (micPlayer != null) {
            try {
                if (micPlayer.isPlaying()) micPlayer.stop();
                micPlayer.release();
            } catch (Throwable ignored) {}
            micPlayer = null;
        }
    }

    // --- Native Android BiometricPrompt (API 28+) ---
    private static void authenticateBiometric(Activity activity, Context app, MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("UNSUPPORTED", "BiometricPrompt requires Android 9 (API 28) or higher.", null);
            return;
        }
        PackageManager pm = app.getPackageManager();
        boolean hasBiometricHardware = pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
                || pm.hasSystemFeature(PackageManager.FEATURE_FACE)
                || pm.hasSystemFeature(PackageManager.FEATURE_IRIS);
        if (!hasBiometricHardware) {
            result.error("NO_HARDWARE", "No biometric hardware sensor detected on this device.", null);
            return;
        }

        MAIN.post(() -> {
            try {
                BiometricPrompt.Builder builder = new BiometricPrompt.Builder(activity)
                        .setTitle("Verify Biometric Sensor")
                        .setSubtitle("jedHWChecker Hardware Diagnostic")
                        .setDescription("Scan your fingerprint or face to verify sensor hardware.");

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    builder.setAllowedAuthenticators(
                            BiometricManager.Authenticators.BIOMETRIC_STRONG
                                    | BiometricManager.Authenticators.BIOMETRIC_WEAK
                    );
                }
                builder.setNegativeButton("Cancel", activity.getMainExecutor(), (dialog, which) ->
                        result.error("CANCELLED", "Authentication cancelled.", null));

                BiometricPrompt prompt = builder.build();
                prompt.authenticate(
                        new CancellationSignal(),
                        activity.getMainExecutor(),
                        new BiometricPrompt.AuthenticationCallback() {
                            @Override
                            public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult authResult) {
                                result.success(true);
                            }

                            @Override
                            public void onAuthenticationError(int errorCode, CharSequence errString) {
                                result.error("AUTH_ERROR", errString != null ? errString.toString() : "Biometric error", null);
                            }

                            @Override
                            public void onAuthenticationFailed() {
                                // Keep prompt open for retry; Android handles lockout automatically
                            }
                        }
                );
            } catch (Throwable t) {
                result.error("BIOMETRIC_INIT_FAILED", t.getMessage(), null);
            }
        });
    }
}