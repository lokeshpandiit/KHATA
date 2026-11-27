import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// A reusable, large microphone control that writes live Hindi speech into
/// the text field belonging to the current KHATA form.
class VoiceDictationField extends StatefulWidget {
  const VoiceDictationField({
    required this.controller,
    required this.label,
    this.hint = 'Mic dabakar boliye. Aapki baat yahan likh jayegi.',
    this.minLines = 2,
    this.maxLines = 4,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int minLines;
  final int maxLines;

  @override
  State<VoiceDictationField> createState() => _VoiceDictationFieldState();
}

class _VoiceDictationFieldState extends State<VoiceDictationField> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  bool _initializing = false;
  String _baseText = '';

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _toggleListening() async {
    if (_initializing) return;
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    setState(() => _initializing = true);
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() => _listening = false);
            _message('Voice input error: ${error.errorMsg}');
          }
        },
      );

      if (!mounted) return;
      setState(() => _initializing = false);
      if (!available) {
        _message('Speech recognition available nahi hai. Phone ki voice typing service check karein.');
        return;
      }

      _baseText = widget.controller.text.trim();
      setState(() => _listening = true);
      await _speech.listen(
        localeId: 'hi_IN',
        onResult: (result) {
          final spoken = result.recognizedWords.trim();
          if (spoken.isEmpty) return;
          final combined = _baseText.isEmpty ? spoken : '$_baseText\n$spoken';
          widget.controller.value = TextEditingValue(
            text: combined,
            selection: TextSelection.collapsed(offset: combined.length),
          );
          if (result.finalResult && mounted) {
            setState(() => _listening = false);
          }
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _listening = false;
        });
        _message('Voice input start nahi hua: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _listening;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: active ? const Color(0xFFFFEEEE) : const Color(0xFFEAF4EF),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Material(
                  color: active ? Colors.red : const Color(0xFF176B52),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _toggleListening,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: Center(
                        child: _initializing
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Icon(
                                active ? Icons.stop_rounded : Icons.mic_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _initializing
                            ? 'Microphone starting…'
                            : active
                                ? 'Sun raha hai…'
                                : 'Bolkar likhein',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active
                            ? 'Bolna band karne ke liye mic dabayein.'
                            : 'Badi mic button dabayein. Aapki baat isi record ke note mein aa jayegi.',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: widget.controller,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
