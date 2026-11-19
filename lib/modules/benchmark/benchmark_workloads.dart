import 'dart:typed_data';

const int kSieveLimit = 5000000;
const int kSievePasses = 3;
const int kExpectedPrimeCount = 348513; // π(5,000,000)

const int kBufferBytes = 64 * 1024 * 1024;
const int kCopiesPerRound = 8;

int _sievePrimeCount(int limit) {
  final composite = Uint8List(limit + 1);
  var count = 0;
  for (var i = 2; i <= limit; i++) {
    if (composite[i] == 0) {
      count++;
      for (var j = i * i; j <= limit; j += i) {
        composite[j] = 1;
      }
    }
  }
  return count;
}

/// Runs the sieve [passes] times. Returns [elapsedMicroseconds, 1 if every pass verified].
List<int> cpuPasses(int passes) {
  var ok = 1;
  final sw = Stopwatch()..start();
  for (var p = 0; p < passes; p++) {
    if (_sievePrimeCount(kSieveLimit) != kExpectedPrimeCount) ok = 0;
  }
  sw.stop();
  return [sw.elapsedMicroseconds, ok];
}

/// Copies one 64 MiB buffer into the other repeatedly.
/// Returns [elapsedMicroseconds, 1 if the final contents verified].
List<int> memoryCopyPass(int copies) {
  final a = Uint8List(kBufferBytes)..fillRange(0, kBufferBytes, 1);
  final b = Uint8List(kBufferBytes)..fillRange(0, kBufferBytes, 2);

  final sw = Stopwatch()..start();
  for (var c = 0; c < copies; c++) {
    if (c.isEven) {
      b.setRange(0, kBufferBytes, a);
    } else {
      a.setRange(0, kBufferBytes, b);
    }
  }
  sw.stop();

  // After the first copy both buffers hold 1s, so the final values must be 1.
  final ok = (a[kBufferBytes - 1] == 1 && b[kBufferBytes - 1] == 1) ? 1 : 0;
  return [sw.elapsedMicroseconds, ok];
}