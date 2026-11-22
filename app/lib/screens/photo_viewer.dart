import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models.dart';
import '../services/store.dart';

/// Full-screen photo viewer. Sets Android FLAG_SECURE while open so the
/// photo cannot be screenshotted or screen-recorded from this device,
/// and opening it consumes one of the sender-chosen views — the server
/// deletes the blob when the limit is reached.
class PhotoViewer extends StatefulWidget {
  final AppState state;
  final ChatMessage message;
  const PhotoViewer({super.key, required this.state, required this.message});

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  static const _channel = MethodChannel(AppConfig.secureChannel);
  PhotoResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _channel.invokeMethod('setSecure', true);
    _load();
  }

  @override
  void dispose() {
    _channel.invokeMethod('setSecure', false);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.state.fetchPhoto(widget.message);
      if (mounted) setState(() => _result = res);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e.toString().contains('404') || e.toString().contains('410')
                ? 'This photo is gone.'
                : 'Could not open photo: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Photo', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _error != null
            ? Text(_error!,
                style: const TextStyle(color: Colors.white70, fontSize: 16))
            : _result == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                          child: Image.memory(_result!.bytes,
                              fit: BoxFit.contain)),
                      if (_result!.viewsLeft != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                              _result!.viewsLeft! > 0
                                  ? 'Views left: ${_result!.viewsLeft}'
                                  : 'That was the last view — the photo is '
                                      'now deleted from the server.',
                              style: const TextStyle(color: Colors.white70)),
                        ),
                    ],
                  ),
      ),
    );
  }
}
