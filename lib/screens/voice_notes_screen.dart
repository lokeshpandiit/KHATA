import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/storage_backup_service.dart';

class VoiceNotesScreen extends StatefulWidget {
  const VoiceNotesScreen({super.key});
  @override
  State<VoiceNotesScreen> createState() => _VoiceNotesScreenState();
}
class _VoiceNotesScreenState extends State<VoiceNotesScreen> {
  final storage = StorageBackupService.instance;
  final recorder = AudioRecorder();
  final speech = stt.SpeechToText();
  final player = AudioPlayer();
  final transcript = TextEditingController();
  final title = TextEditingController();
  bool recording = false, listening = false, speechReady = false, busy = false;
  String? tempAudio, playing;
  List<Map<String, dynamic>> get notes => storage.records('voiceNotes');
  @override
  void initState() {
    super.initState();
    speech.initialize().then((ready) { if (mounted) setState(() => speechReady = ready); });
    player.onPlayerComplete.listen((_) { if (mounted) setState(() => playing = null); });
  }
  @override
  void dispose() {
    recorder.dispose(); speech.stop(); player.dispose(); transcript.dispose(); title.dispose(); super.dispose();
  }
  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
  void suggestTitle() {
    if (title.text.trim().isNotEmpty) return;
    final words = transcript.text.trim().split(RegExp(r'\\s+')).take(5).join(' ');
    if (words.isNotEmpty) title.text = words;
  }
  Future<void> toggleSpeech() async {
    if (!speechReady) { showMessage('Speech recognition available nahi hai.'); return; }
    if (listening) { await speech.stop(); if (mounted) setState(() => listening = false); suggestTitle(); return; }
    setState(() => listening = true);
    await speech.listen(localeId: 'hi_IN', onResult: (result) {
      transcript.text = result.recognizedWords;
      transcript.selection = TextSelection.collapsed(offset: transcript.text.length);
      if (result.finalResult) { if (mounted) setState(() => listening = false); suggestTitle(); }
      else if (mounted) setState(() {});
    });
  }
  Future<void> startRecording() async {
    if (!await recorder.hasPermission()) { showMessage('Microphone permission allow karein.'); return; }
    final temp = await getTemporaryDirectory();
    tempAudio = p.join(temp.path, 'khata_voice_${DateTime.now().microsecondsSinceEpoch}.m4a');
    await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: tempAudio!);
    if (mounted) setState(() => recording = true);
  }
  Future<void> stopRecording() async {
    tempAudio = await recorder.stop() ?? tempAudio;
    if (mounted) setState(() => recording = false);
  }
  Future<void> saveNote() async {
    if (busy) return;
    if (tempAudio == null && transcript.text.trim().isEmpty) { showMessage('Audio record ya bolkar text likhein.'); return; }
    setState(() => busy = true);
    try {
      final now = DateTime.now();
      final words = transcript.text.trim().split(RegExp(r'\\s+')).take(5).join(' ');
      final noteTitle = title.text.trim().isNotEmpty ? title.text.trim() : (words.isNotEmpty ? words : 'Voice Note ${now.day}/${now.month}/${now.year}');
      String? audioPath;
      if (tempAudio != null && await File(tempAudio!).exists()) audioPath = await storage.keepFile(tempAudio!, folder: 'VoiceNotes', filename: 'voice.m4a');
      await storage.addRecord('voiceNotes', {'id': now.microsecondsSinceEpoch.toString(), 'title': noteTitle, 'transcript': transcript.text.trim(), 'audio': audioPath, 'date': now.toIso8601String()});
      transcript.clear(); title.clear(); tempAudio = null;
      if (mounted) setState(() => busy = false);
      showMessage('Voice note saved.');
    } catch (error) {
      if (mounted) setState(() => busy = false);
      showMessage('Save nahi hua: $error');
    }
  }
  Future<void> deleteNote(Map<String, dynamic> note) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Delete voice note?'), content: Text('${note['title']} delete ho jayega.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete'))],
    ));
    if (confirmed != true) return;
    await storage.deleteRecord('voiceNotes', note['id'] as String);
    final path = note['audio'] as String?;
    if (path != null) { try { final f = File(path); if (await f.exists()) await f.delete(); } catch (_) {} }
    if (mounted) setState(() {});
  }
  Future<void> playAudio(String path) async {
    if (playing == path) { await player.pause(); if (mounted) setState(() => playing = null); }
    else { await player.play(DeviceFileSource(path)); if (mounted) setState(() => playing = path); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Voice Notes')),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Naya Voice Note', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title (optional)')),
        const SizedBox(height: 8),
        TextField(controller: transcript, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: 'Voice-to-text / notes', hintText: 'Mic dabakar boliye…', suffixIcon: IconButton(onPressed: toggleSpeech, icon: Icon(listening ? Icons.mic : Icons.mic_none, color: listening ? Colors.red : null)))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: recording ? stopRecording : startRecording, icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record, color: recording ? Colors.red : null), label: Text(recording ? 'Stop recording' : 'Record audio'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(onPressed: busy ? null : saveNote, icon: const Icon(Icons.save), label: Text(busy ? 'Saving…' : 'Save note'))),
        ]),
        if (tempAudio != null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Audio ready to save', style: TextStyle(color: Colors.green))),
      ]))),
      const SizedBox(height: 10),
      Text('Saved Voice Notes (${notes.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      if (notes.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Abhi koi voice note nahi hai.')),
      ...notes.map((note) {
        final audio = note['audio'] as String?;
        final hasAudio = audio != null && File(audio).existsSync();
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.mic)),
          title: Text(note['title'] as String? ?? 'Voice note'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((note['transcript'] as String? ?? '').isNotEmpty) Text(note['transcript'] as String, maxLines: 3, overflow: TextOverflow.ellipsis),
            Text(note['date'] as String? ?? '', style: const TextStyle(fontSize: 11)),
          ]),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (hasAudio) IconButton(icon: Icon(playing == audio ? Icons.pause : Icons.play_arrow), onPressed: () => playAudio(audio ?? '')),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => deleteNote(note)),
          ]),
        ));
      }),
    ]),
  );
}
