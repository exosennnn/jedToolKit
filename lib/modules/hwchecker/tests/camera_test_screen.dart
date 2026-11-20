import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';

class CameraTestScreen extends StatefulWidget {
  const CameraTestScreen({super.key});

  @override
  State<CameraTestScreen> createState() => _CameraTestScreenState();
}

class _CameraTestScreenState extends State<CameraTestScreen> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _selectedIndex = 0;
  final Set<int> _testedLenses = {};
  bool _capturedPhoto = false;
  bool _flashShutter = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCameras();
  }

  Future<void> _initCameras() async {
    try {
      final list = await availableCameras();
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() => _error = 'No cameras reported on this device.');
        return;
      }
      setState(() => _cameras = list);
      await _selectCamera(0);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Camera access denied or unavailable.');
      }
    }
  }

  Future<void> _selectCamera(int index) async {
    final prev = _controller;
    _controller = null;
    await prev?.dispose();

    final cam = _cameras[index];
    final next = CameraController(cam, ResolutionPreset.high, enableAudio: false);
    try {
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        _selectedIndex = index;
        _controller = next;
        _testedLenses.add(index);
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to open lens ${cam.name}.');
      }
    }
  }

  Future<void> _captureTestFrame() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    HapticFeedback.mediumImpact();
    setState(() => _flashShutter = true);
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _flashShutter = false);
    });
    try {
      await ctrl.takePicture();
      if (mounted) setState(() => _capturedPhoto = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _lensLabel(CameraDescription cam, int index) {
    final dir = switch (cam.lensDirection) {
      CameraLensDirection.back => 'Rear',
      CameraLensDirection.front => 'Front',
      CameraLensDirection.external => 'External',
    };
    return '$dir ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final ctrl = _controller;

    return HwTestPage(
      title: 'Camera Test',
      instruction:
          'Switch between available front and rear camera lenses and capture a test frame to verify optics.',
      canPass: _capturedPhoto || _testedLenses.length == _cameras.length && _cameras.isNotEmpty,
      content: HwCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Live viewfinder
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 300,
                width: double.infinity,
                color: CupertinoColors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_error != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: CupertinoColors.white, fontSize: 14),
                          ),
                        ),
                      )
                    else if (ctrl != null && ctrl.value.isInitialized)
                      CameraPreview(ctrl)
                    else
                      const Center(child: CupertinoActivityIndicator(color: CupertinoColors.white)),
                    if (_flashShutter)
                      Container(color: CupertinoColors.white.withOpacity(0.85)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Lens selector pills
            if (_cameras.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _cameras.length; i++)
                      Padding(
                        padding: EdgeInsets.only(right: i == _cameras.length - 1 ? 0 : 8),
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minSize: 0,
                          color: _selectedIndex == i ? accent : hwLabel(context, 0.06),
                          borderRadius: BorderRadius.circular(100),
                          onPressed: () => _selectCamera(i),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_testedLenses.contains(i)) ...[
                                Icon(
                                  CupertinoIcons.checkmark_circle_fill,
                                  size: 13,
                                  color: _selectedIndex == i ? CupertinoColors.white : green,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Text(
                                _lensLabel(_cameras[i], i),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedIndex == i
                                      ? CupertinoColors.white
                                      : CupertinoColors.label.resolveFrom(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            HwStatusPill(
              icon: _capturedPhoto ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.camera_fill,
              text: _capturedPhoto
                  ? 'Frame Captured (${_testedLenses.length}/${_cameras.length} Lenses Checked)'
                  : 'Lenses Checked: ${_testedLenses.length} of ${_cameras.length}',
              color: green,
              active: _capturedPhoto,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                color: accent,
                borderRadius: BorderRadius.circular(14),
                onPressed: ctrl != null && ctrl.value.isInitialized ? _captureTestFrame : null,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.camera_viewfinder, size: 18, color: CupertinoColors.white),
                    SizedBox(width: 8),
                    Text(
                      'Capture Test Frame',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}