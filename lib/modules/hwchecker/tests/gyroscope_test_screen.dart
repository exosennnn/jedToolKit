import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class GyroscopeTestScreen extends StatefulWidget {
  const GyroscopeTestScreen({super.key});

  @override
  State<GyroscopeTestScreen> createState() => _GyroscopeTestScreenState();
}

class _GyroscopeTestScreenState extends State<GyroscopeTestScreen>
    with SingleTickerProviderStateMixin {
  bool _isCalibrated = false;
  String _statusText = 'Initializing Gyroscope...';

  // Orientation of the cube as a row-major 3x3 rotation matrix (screen frame:
  // x right, y down, z into the screen). Starts slightly tilted so it reads as 3D.
  List<double> _rot = _initialRotation();

  static List<double> _initialRotation() {
    var r = _identity;
    r = _mul(r, _axisAngle(1, 0, 0, 0.45));
    r = _mul(r, _axisAngle(0, 1, 0, -0.6));
    return r;
  }

  DateTime? _lastTimestamp;
  StreamSubscription<Map<String, dynamic>>? _sub;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    })..start();

    _sub = HwNativeBridge.sensorStream('gyroscope').listen(
      (data) {
        final rx = (data['rx'] as num?)?.toDouble() ?? 0.0;
        final ry = (data['ry'] as num?)?.toDouble() ?? 0.0;
        final rz = (data['rz'] as num?)?.toDouble() ?? 0.0;

        final now = DateTime.now();
        if (_lastTimestamp != null) {
          final dt = now.difference(_lastTimestamp!).inMicroseconds / 1e6;
          if (dt > 0 && dt < 0.2) {
            // Gyro axes: x right, y up, z out of the screen (rad/s, device frame).
            // Convert to screen frame (y down, z into screen) = (x, -y, -z), then
            // apply the rotation in the device's own frame so the cube mirrors the phone.
            final step = _axisAngleVec(rx * dt, -ry * dt, -rz * dt);
            _rot = _orthonormalize(_mul(_rot, step));
          }
        }
        _lastTimestamp = now;

        if (!_isCalibrated) {
          if (rx.abs() > 0.4 || ry.abs() > 0.4 || rz.abs() > 0.4) {
            _isCalibrated = true;
            _statusText = 'Rotation Tracked Successfully';
          } else if (_statusText == 'Initializing Gyroscope...') {
            _statusText = 'Rotate device in any direction';
          }
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _statusText = 'Gyroscope hardware unavailable.');
        }
      },
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);

    return HwTestPage(
      title: 'Gyroscope Test',
      instruction:
          'Rotate your device in any direction. The cube should follow your movements in real-time.',
      canPass: _isCalibrated,
      content: HwCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          children: [
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: hwLabel(context, 0.025),
                borderRadius: BorderRadius.circular(14),
              ),
              child: CustomPaint(
                painter: _Cube3DPainter(rot: _rot, baseColor: accent),
              ),
            ),
            const SizedBox(height: 20),
            HwStatusPill(
              icon: _isCalibrated
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.rotate_right,
              text: _statusText,
              color: green,
              active: _isCalibrated,
            ),
          ],
        ),
      ),
    );
  }
}

const List<double> _identity = [1, 0, 0, 0, 1, 0, 0, 0, 1];

List<double> _mul(List<double> a, List<double> b) {
  final o = List<double>.filled(9, 0);
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      o[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c];
    }
  }
  return o;
}

/// Rodrigues rotation for axis (x, y, z) (need not be unit) and angle in radians.
List<double> _axisAngle(double x, double y, double z, double angle) {
  final n = math.sqrt(x * x + y * y + z * z);
  if (n == 0) return _identity;
  return _axisAngleVec(x / n * angle, y / n * angle, z / n * angle);
}

/// Rotation by the vector w: axis = w / |w|, angle = |w|.
List<double> _axisAngleVec(double wx, double wy, double wz) {
  final t = math.sqrt(wx * wx + wy * wy + wz * wz);
  if (t < 1e-9) return _identity;
  final x = wx / t, y = wy / t, z = wz / t;
  final c = math.cos(t), s = math.sin(t), k = 1 - c;
  return [
    c + x * x * k, x * y * k - z * s, x * z * k + y * s,
    y * x * k + z * s, c + y * y * k, y * z * k - x * s,
    z * x * k - y * s, z * y * k + x * s, c + z * z * k,
  ];
}

/// Keeps the matrix a pure rotation (removes numerical drift).
List<double> _orthonormalize(List<double> m) {
  var x = [m[0], m[3], m[6]];
  var y = [m[1], m[4], m[7]];
  double dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  List<double> norm(List<double> a) {
    final l = math.sqrt(dot(a, a));
    return l == 0 ? a : [a[0] / l, a[1] / l, a[2] / l];
  }

  x = norm(x);
  final d = dot(y, x);
  y = norm([y[0] - d * x[0], y[1] - d * x[1], y[2] - d * x[2]]);
  final z = [
    x[1] * y[2] - x[2] * y[1],
    x[2] * y[0] - x[0] * y[2],
    x[0] * y[1] - x[1] * y[0],
  ];
  return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]];
}

class _Cube3DPainter extends CustomPainter {
  final List<double> rot;
  final Color baseColor;

  _Cube3DPainter({required this.rot, required this.baseColor});

  static const _vertices = [
    [-1.0, -1.0, -1.0], // 0
    [1.0, -1.0, -1.0], // 1
    [1.0, 1.0, -1.0], // 2
    [-1.0, 1.0, -1.0], // 3
    [-1.0, -1.0, 1.0], // 4
    [1.0, -1.0, 1.0], // 5
    [1.0, 1.0, 1.0], // 6
    [-1.0, 1.0, 1.0], // 7
  ];

  // Winding does not matter: outward normals are derived from the face centre.
  static const _faces = [
    [0, 1, 2, 3], // z = -1
    [4, 5, 6, 7], // z = +1
    [0, 3, 7, 4], // x = -1
    [1, 2, 6, 5], // x = +1
    [0, 1, 5, 4], // y = -1
    [3, 2, 6, 7], // y = +1
  ];

  // Per-face hue shifts so you can tell the faces apart while it spins.
  static const _hueShift = [0.0, 25.0, -25.0, 50.0, -50.0, 80.0];

  // Camera sits at z = -camDist looking along +z.
  static const _camDist = 4.2;

  List<double> _rotate(List<double> v) => [
        rot[0] * v[0] + rot[1] * v[1] + rot[2] * v[2],
        rot[3] * v[0] + rot[4] * v[1] + rot[5] * v[2],
        rot[6] * v[0] + rot[7] * v[1] + rot[8] * v[2],
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = math.min(size.width, size.height) * 0.26;

    final rotated = _vertices.map(_rotate).toList();
    final projected = rotated.map((v) {
      final f = _camDist / (_camDist + v[2]);
      return Offset(cx + v[0] * scale * f, cy + v[1] * scale * f);
    }).toList();

    // Light comes from the top-front-left (up = -y, toward the viewer = -z).
    const lx = -0.4, ly = -0.6, lz = -0.7;
    final ll = math.sqrt(lx * lx + ly * ly + lz * lz);

    final visible = <({int index, double depth, double shade})>[];
    for (var fi = 0; fi < _faces.length; fi++) {
      final face = _faces[fi];
      final v0 = rotated[face[0]], v1 = rotated[face[1]], v2 = rotated[face[2]];
      final ux = v1[0] - v0[0], uy = v1[1] - v0[1], uz = v1[2] - v0[2];
      final vx = v2[0] - v0[0], vy = v2[1] - v0[1], vz = v2[2] - v0[2];
      var nx = uy * vz - uz * vy;
      var ny = uz * vx - ux * vz;
      var nz = ux * vy - uy * vx;
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len == 0) continue;
      nx /= len; ny /= len; nz /= len;

      // Face centre; the cube is centred on the origin, so the outward normal
      // is the one pointing the same way as the centre.
      var cxf = 0.0, cyf = 0.0, czf = 0.0;
      for (final idx in face) {
        cxf += rotated[idx][0] / 4;
        cyf += rotated[idx][1] / 4;
        czf += rotated[idx][2] / 4;
      }
      if (nx * cxf + ny * cyf + nz * czf < 0) {
        nx = -nx; ny = -ny; nz = -nz;
      }

      // Visible when the outward normal faces the camera at (0, 0, -camDist).
      final toCam = nx * (0 - cxf) + ny * (0 - cyf) + nz * (-_camDist - czf);
      if (toCam <= 0) continue;

      final shade = ((nx * lx + ny * ly + nz * lz) / ll).clamp(0.0, 1.0);
      visible.add((index: fi, depth: czf, shade: shade));
    }

    // Painter's algorithm: far faces first.
    visible.sort((a, b) => b.depth.compareTo(a.depth));

    final hsl = HSLColor.fromColor(baseColor);
    for (final f in visible) {
      final lightness = (hsl.lightness * (0.6 + 0.6 * f.shade)).clamp(0.18, 0.85);
      final hue = (hsl.hue + _hueShift[f.index]) % 360;
      final color = hsl.withHue(hue < 0 ? hue + 360 : hue).withLightness(lightness).toColor();

      final face = _faces[f.index];
      final path = Path()..moveTo(projected[face[0]].dx, projected[face[0]].dy);
      for (var k = 1; k < 4; k++) {
        path.lineTo(projected[face[k]].dx, projected[face[k]].dy);
      }
      path.close();

      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = CupertinoColors.white.withAlpha(72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Cube3DPainter old) {
    if (old.baseColor != baseColor) return true;
    for (var i = 0; i < 9; i++) {
      if (old.rot[i] != rot[i]) return true;
    }
    return false;
  }
}
