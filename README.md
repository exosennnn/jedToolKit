# jedToolKit for Android

**jedToolKit** is an all-in-one device toolkit for Android: inspect your phone's hardware, run guided diagnostics, benchmark the CPU/GPU/memory, and check RAM and storage health, all in a clean iOS-style (Cupertino) interface.

This is the Android port of the jedToolKit iOS app, built with **Flutter** and native **Java** platform channels.

> **Also on iOS:** [jedToolKit 27.0.1](https://github.com/ProtonyteTV/jedToolKit) (codename **jedIntelligence**). The iOS app is **closed source**; this repository covers the Android version only.

- **Package / application ID:** `com.jedplatforms.jedtoolkit`
- **Version:** 1.0.0 (codename **jedIntelligence**)
- **Min SDK:** 24 (Android 7.0), required by the Vulkan-based native benchmark code
- **Offline-first:** the app starts in Offline Mode, and network traffic from Dart is blocked until you turn it off

---

## Modules

| Module | What it does |
| --- | --- |
| **jedPhoneInfo** | Device, CPU, memory, display and battery details |
| **jedHWChecker** | Guided hardware tests that you confirm yourself (see below) |
| **jedBenchmark 2** | CPU (single and multi-core), memory and GPU benchmarks with a sustained-load stress phase |
| **jedRAMChecker** | Live memory metrics: footprint, resident, virtual and available budget, plus a Normal / Warning / Critical pressure level |
| **jedDiskChecker** | Storage space info plus sequential write and read speed tests (MB/s), with history |
| Panic Analyzer | *Coming soon* |
| OS Security | *Coming soon* |
| Terminal Lite | *Coming soon* |

### jedHWChecker tests

Accelerometer · Gyroscope · Magnetometer · Proximity sensor · Camera · LED flash · Microphone · Speaker · Vibration · Brightness · Biometrics · Bluetooth · Wi-Fi · Cellular / VoLTE · Charger · Battery info · Physical buttons

### jedBenchmark 2

- **CPU:** 16 single-core tasks (zipping files, route calculation, HTML/document rendering, photo sorting and effects, object recognition, HDR processing, 3D rendering and more) plus multi-core workloads, run on pinned cores via `sched_setaffinity`.
- **Sustained load:** an all-core stress phase (default 180 s) that shows how much performance the phone keeps once it is hot.
- **Memory:** bandwidth test that runs for at least 10 s.
- **GPU:** compute tests (OpenGL ES compute and OpenCL; reports GFLOPS and GB/s with a sustained-speed percentage) plus Flutter raster scenes.
- **Scoring:** every phone runs the same workload, and **2500 points = Samsung Galaxy S20** (Snapdragon 865 / Adreno 650). Scores are weighted geometric means, so they compare directly between devices.
- **Safety:** the test stops itself on severe thermal throttling (`THERMAL_STATUS_SEVERE`) or when the battery reaches 46 °C.
- **History:** past results are saved and can be browsed in-app.

Total runtime with the default settings is roughly **6 minutes**. Durations live in `lib/modules/benchmark/benchmark_config.dart`.

### App features

- Customizable dock (up to 3 tabs, Home always first) and pinned modules on Home
- Light / dark app theme and selectable accent color
- First-run welcome and setup flow, plus a "What's New" screen shown once per version
- User profile (name and photo) and optional **App Lock** using biometrics
- Offline Mode switch that blocks outgoing connections from Dart (loopback is still allowed)

---

## Tech stack

| Layer | Details |
| --- | --- |
| UI | Flutter with `CupertinoApp` and a custom **jedUI** design system (`lib/core/jedui`) |
| Native | Java 17 platform channels (`MethodChannel` / `EventChannel`) |
| Native compute | CMake / NDK library `jedbench` (OpenCL and Vulkan) for GPU benchmarking |
| Dart FFI | `dart:ffi` + `package:ffi` for CPU affinity |
| Packages | `shared_preferences`, `local_auth`, `image_picker`, `camera`, `path_provider`, `ffi` |
| Build | Gradle (Kotlin DSL), Android Gradle Plugin 9.3.1, Kotlin 2.4.20, Gradle wrapper 9.5.0 |

### Native channels

| Channel | Purpose |
| --- | --- |
| `com.jedplatforms.jedtoolkit/phoneinfo` | Device, CPU, memory and display info |
| `com.jedplatforms.jedtoolkit/disk` | Disk space and read/write benchmark |
| `jedtoolkit/hwchecker` (+ `_sensors`, `_keys`) | Hardware queries, live sensor stream, physical button events |
| `jedtoolkit/hwchecker_media` (+ `_mic_level`) | Camera, mic and biometric tests |
| `jedtoolkit/device_specs` | Device specification lookup |
| `jedtoolkit/gles_compute` | OpenGL ES compute benchmark |
| `jedtoolkit/thermal` | Thermal status and temperature monitoring |
| `jedtoolkit/screen` | Keep-screen-awake during tests |

---

## Project structure

```
jedToolKit/
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       └── java/com/jedplatforms/jedtoolkit/
│           ├── MainActivity.java            # phoneinfo + disk channels
│           ├── DeviceInfoCollector.java
│           ├── DeviceSpecsChannel.java
│           ├── DiskBenchmark.java
│           ├── GlesComputeChannel.java
│           ├── HWCheckerChannel.java
│           ├── HwMediaBiometricChannel.java
│           ├── RamMetricsCollector.java
│           ├── ScreenChannel.java
│           └── ThermalChannel.java
└── lib/
    ├── main.dart
    ├── app/                  # App shell (dock + navigation)
    ├── core/
    │   ├── jedui/            # Theme, components, dock, routes
    │   ├── network/          # Offline Mode manager
    │   ├── profile/          # Profile, account page, App Lock
    │   └── settings/         # App settings, tab modules
    └── modules/
        ├── appsetup/   benchmark/   diskchecker/   home/
        ├── hwchecker/  phoneinfo/   ramchecker/    settings/
        └── welcome/    whatsnew/
```

---

## Permissions

| Permission | Used for |
| --- | --- |
| `CAMERA` | Camera and LED flash tests |
| `RECORD_AUDIO` | Microphone test |
| `VIBRATE` | Vibration test |
| `USE_BIOMETRIC` | Biometric test and App Lock |
| `BLUETOOTH`, `BLUETOOTH_ADMIN` (API ≤ 30), `BLUETOOTH_CONNECT` | Bluetooth test |
| `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` | Wi-Fi / network test |
| `READ_PHONE_STATE` | Cellular / VoLTE info |
| `INTERNET` | Required by Flutter tooling; blocked in-app while Offline Mode is on |

Camera and flash hardware are declared `required="false"`, so the app also installs on devices without them. `libOpenCL.so` is also optional.

---

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- Android Studio or the Android command-line tools
- Android NDK and CMake (installed via the SDK Manager; needed for the native benchmark library)
- JDK 17
- A physical Android 7.0+ (API 24+) device recommended; most hardware tests and the benchmark are not meaningful on an emulator

### Build and run

```bash
# 1. Get dependencies
flutter pub get

# 2. Run on a connected device (debug)
flutter run

# 3. Release build (use this for benchmarking)
flutter build apk --release
```

`android/local.properties` must point to your Flutter and Android SDKs (Flutter normally generates it):

```properties
flutter.sdk=/path/to/flutter
sdk.dir=/path/to/Android/sdk
```

> **Benchmark tip:** always benchmark with a **release** build. Debug builds are significantly slower and will give misleading scores.

---

## Calibrating benchmark scores

Scores are anchored to a Galaxy S20. To recalibrate (for example after changing test durations):

1. Set `kCalibrationMode = true` in `lib/modules/benchmark/s20_baseline.dart`.
2. Build a release APK and run it on the S20 when cool.
3. Run each test about 5 times and copy the "Baseline snippet" from each result's details.
4. Paste the median values into `s20_baseline.dart`, then set `kCalibrationMode` back to `false`.

---

## Release signing

The release build type currently uses the **debug** signing config so `flutter run --release` works out of the box. Before publishing, create your own keystore, add a `key.properties` file, and configure a proper `signingConfig` in `android/app/build.gradle.kts`. Never commit your keystore or `key.properties` (both are already in `.gitignore`).

---

## Roadmap

- [ ] Panic Analyzer
- [ ] Terminal Lite
- [ ] Bug Fixes

---

## Credits

Made by **jedPlatforms**. Android port of the jedToolKit iOS app.

## Platforms

| Platform | Version | Codename | Source | Link |
| --- | --- | --- | --- | --- |
| Android | 1.0.0 | jedIntelligence | Open source (this repo) | You're here |
| iOS | 27.0.1 | jedIntelligence | Closed source | [github.com/ProtonyteTV/jedToolKit](https://github.com/ProtonyteTV/jedToolKit) |