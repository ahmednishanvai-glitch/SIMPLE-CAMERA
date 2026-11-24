import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import 'preview_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _albumName = 'SimpleCamera';

  List<CameraDescription> _cameras = const [];
  CameraDescription? _current;
  CameraController? _controller;
  FlashMode _flashMode = FlashMode.off;
  bool _initializing = true;
  bool _saving = false;
  String? _error;
  final List<String> _photos = [];

  bool get _busy => _initializing || _saving;

  bool get _isFront => _current?.lensDirection == CameraLensDirection.front;

  bool get _canSwitch =>
      _cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
      _cameras.any((c) => c.lensDirection == CameraLensDirection.back);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      if (controller != null) {
        setState(() => _controller = null);
        controller.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      final camera = _current;
      if (_controller == null &&
          !_initializing &&
          _error == null &&
          camera != null) {
        _startCamera(camera);
      }
    }
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      _fail(e.description ?? e.code);
      return;
    }
    if (_cameras.isEmpty) {
      _fail('No camera found on this device.');
      return;
    }
    final back = _cameras.where(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    await _startCamera(back.isNotEmpty ? back.first : _cameras.first);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _initializing = false;
    });
  }

  Future<void> _startCamera(CameraDescription description) async {
    if (!mounted) return;
    final previous = _controller;
    setState(() {
      _controller = null;
      _current = description;
      _initializing = true;
      _error = null;
    });
    await previous?.dispose();

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      if (description.lensDirection == CameraLensDirection.back) {
        await _applyFlash(controller, _flashMode);
      }
    } on CameraException catch (e) {
      await controller.dispose();
      _fail(
        e.code == 'CameraAccessDenied'
            ? 'Camera permission was denied. Allow camera access in the '
                'system settings, then try again.'
            : (e.description ?? e.code),
      );
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _initializing = false;
    });
  }

  Future<void> _applyFlash(CameraController controller, FlashMode mode) async {
    try {
      await controller.setFlashMode(mode);
    } on CameraException {
      // Device has no flash unit; ignore.
    }
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || _isFront || _busy) return;
    final next = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    await _applyFlash(controller, next);
    if (mounted) setState(() => _flashMode = next);
  }

  Future<void> _switchCamera() async {
    final current = _current;
    if (current == null || _busy) return;
    final target = current.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final candidates = _cameras.where((c) => c.lensDirection == target);
    if (candidates.isEmpty) return;
    await _startCamera(candidates.first);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _busy) {
      return;
    }
    setState(() => _saving = true);
    try {
      final shot = await controller.takePicture();
      _photos.add(shot.path);
      await _saveToGallery(shot.path);
    } on CameraException catch (e) {
      _toast('Capture failed: ${e.description ?? e.code}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveToGallery(String path) async {
    try {
      final granted = await Gal.hasAccess(toAlbum: true) ||
          await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        _toast('Gallery access denied. The photo was not saved.');
        return;
      }
      await Gal.putImage(path, album: _albumName);
      _toast('Saved to gallery');
    } on GalException catch (e) {
      _toast('Could not save photo: ${e.type.message}');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  void _openPreview(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreviewScreen(
          photos: List<String>.of(_photos),
          initialIndex: index,
        ),
      ),
    );
  }

  void _retry() {
    if (_cameras.isEmpty) {
      setState(() {
        _error = null;
        _initializing = true;
      });
      _setup();
    } else {
      _startCamera(_current ?? _cameras.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildPreview()),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final icon = switch (_flashMode) {
      FlashMode.auto => Icons.flash_auto,
      FlashMode.always => Icons.flash_on,
      _ => Icons.flash_off,
    };
    final enabled = !_isFront && !_busy && _controller != null;
    return SizedBox(
      height: 56,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: IconButton(
            tooltip: _isFront ? 'Flash unavailable on front camera' : 'Flash',
            iconSize: 28,
            onPressed: enabled ? _cycleFlash : null,
            icon: Icon(_isFront ? Icons.flash_off : icon),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, size: 48),
              const SizedBox(height: 16),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _retry, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(child: CameraPreview(controller));
  }

  Widget _buildControls() {
    return SizedBox(
      height: 112,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildThumbnail(),
          _buildShutter(),
          SizedBox(
            width: 56,
            height: 56,
            child: _canSwitch
                ? IconButton(
                    tooltip: 'Switch camera',
                    iconSize: 32,
                    onPressed: _busy ? null : _switchCamera,
                    icon: const Icon(Icons.cameraswitch),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    if (_photos.isEmpty) return const SizedBox(width: 56, height: 56);
    return GestureDetector(
      onTap: () => _openPreview(_photos.length - 1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(_photos.last),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          cacheWidth: 168,
          errorBuilder: (context, error, stack) =>
              const ColoredBox(color: Colors.white24),
        ),
      ),
    );
  }

  Widget _buildShutter() {
    final ready = _controller != null && !_busy;
    return GestureDetector(
      onTap: ready ? _capture : null,
      child: Opacity(
        opacity: ready ? 1 : 0.5,
        child: Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: _saving
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.black,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
