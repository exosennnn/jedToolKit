import 'panic_models.dart';

/// Built-in samples for the jedPanicAnalyzer mock test. Each one must be
/// recognized as [expected] and produce a finding whose title contains
/// [expectedFinding], so a regression in the parser shows up as FAIL.
class MockPanicSample {
  final String name;
  final PanicKind expected;
  final String expectedFinding;
  final String text;

  const MockPanicSample({
    required this.name,
    required this.expected,
    required this.expectedFinding,
    required this.text,
  });
}

class MockResult {
  final MockPanicSample sample;
  final PanicReport report;
  final bool passed;

  MockResult(MockPanicSample s, PanicReport r)
      : sample = s,
        report = r,
        passed = r.kind == s.expected &&
            r.findings.any((f) => f.title.contains(s.expectedFinding));
}

const List<MockPanicSample> kMockPanicSamples = [
  MockPanicSample(
    name: 'Java crash (NullPointerException)',
    expected: PanicKind.javaCrash,
    expectedFinding: 'Null value used as an object',
    text: '''
E/AndroidRuntime(21544): FATAL EXCEPTION: main
E/AndroidRuntime(21544): Process: com.example.mockapp, PID: 21544
E/AndroidRuntime(21544): java.lang.NullPointerException: Attempt to invoke virtual method 'int java.lang.String.length()' on a null object reference
E/AndroidRuntime(21544):     at com.example.mockapp.MainActivity.onCreate(MainActivity.java:42)
E/AndroidRuntime(21544):     at android.app.Activity.performCreate(Activity.java:8051)
E/AndroidRuntime(21544):     at android.app.Instrumentation.callActivityOnCreate(Instrumentation.java:1309)
''',
  ),
  MockPanicSample(
    name: 'ANR with main thread waiting',
    expected: PanicKind.anr,
    expectedFinding: 'Main thread was WAITING',
    text: '''
ANR in com.example.mockapp (com.example.mockapp/.MainActivity)
PID: 21544
Reason: Input dispatching timed out (Waiting to send non-key event because the touch target has not finished processing the previous event.)
Load: 2.31 / 2.10 / 1.97
CPU usage from 1200ms to 0ms ago:

"main" prio=5 tid=1 Waiting
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x7a1b2c00 self=0x7c1234
  | sysTid=21544 nice=-10 cgrp=top-app sched=0/0 handle=0x7d0a1b2c
  | state=S schedstat=( 1234567 89012 345 ) utm=98 stm=25 core=2 HZ=100
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x0a1b2c3d> (a java.lang.Object) held by tid=14 (Thread-3)
  at java.lang.Object.wait(Object.java:442)
  java.lang.Thread.State: WAITING
  at com.example.mockapp.SyncCache.load(SyncCache.java:57)
  at com.example.mockapp.MainActivity.onClick(MainActivity.java:88)

"Thread-3" prio=5 tid=14 Runnable
  at com.example.mockapp.Worker.run(Worker.java:21)
''',
  ),
  MockPanicSample(
    name: 'Native crash (SIGSEGV tombstone)',
    expected: PanicKind.nativeCrash,
    expectedFinding: 'Invalid memory access (SIGSEGV)',
    text: '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
Build fingerprint: 'google/sdk/emulator:14/UE1A/12345:userdebug/test-keys'
pid: 21544, tid: 21601, name: RenderThread  >>> com.example.mockapp <<<
signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0
backtrace:
    #00 pc 0000000000012a4c  /data/app/~~Ab12==/com.example.mockapp-Cd34==/lib/arm64/libmockgfx.so (render_frame+100)
    #01 pc 00000000000045d0  /apex/com.android.runtime/lib64/bionic/libc.so (__libc_send+4)
''',
  ),
  MockPanicSample(
    name: 'Unrecognized text',
    expected: PanicKind.unknown,
    expectedFinding: 'No known crash or ANR format found',
    text: '''
Hello from the app
Nothing in this file matches a crash format.
''',
  ),
];