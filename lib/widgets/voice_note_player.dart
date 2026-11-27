import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({required this.path, super.key});

  final String path;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  late final AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _player.onPositionChanged.listen((value) {
      if (!mounted) return;
      setState(() => _position = value);
    });
    _player.onPlayerStateChanged.listen((value) {
      if (!mounted) return;
      setState(() {
        _state = value;
        if (value == PlayerState.completed) _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _time(Duration value) {
    final seconds = value.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
      } else if (_state == PlayerState.paused) {
        await _player.resume();
      } else {
        if (!await File(widget.path).exists()) {
          throw FileSystemException('Voice note file is missing', widget.path);
        }
        await _player.play(DeviceFileSource(widget.path));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play voice note: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final max = _duration.inMilliseconds;
    final current = _position.inMilliseconds.clamp(0, max > 0 ? max : 1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: _state == PlayerState.playing ? 'Pause voice note' : 'Play voice note',
            onPressed: _loading ? null : _toggle,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_state == PlayerState.playing
                    ? Icons.pause_circle
                    : Icons.play_circle),
          ),
          Expanded(
            child: Slider(
              value: current.toDouble(),
              max: (max > 0 ? max : 1).toDouble(),
              onChanged: max <= 0
                  ? null
                  : (value) => _player.seek(
                        Duration(milliseconds: value.round()),
                      ),
            ),
          ),
          Text(
            '${_time(_position)} / ${_time(_duration)}',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
