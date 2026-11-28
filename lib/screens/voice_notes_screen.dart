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
  String _makeSmartTitle(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    final lower = t.toLowerCase();

    // Water transactions: identify source and person.
    final source = lower.contains('नहर') || lower.contains('nahar') || lower.contains('canal')
        ? 'नहर'
        : (lower.contains('कुआ') || lower.contains('कुए') || lower.contains('kuan') || lower.contains('kuwe') || lower.contains('well')
            ? 'कुएँ'
            : (lower.contains('ट्यूबवेल') || lower.contains('tubewell') || lower.contains('tube well') ? 'ट्यूबवेल' : null));
    if (source != null && (lower.contains('पानी') || lower.contains('water') || lower.contains('minut') || lower.contains('मिनट'))) {
      final action = (lower.contains('लिया') || lower.contains('liye') || lower.contains('liya') || lower.contains('ले') || lower.contains('used'))
          ? 'पानी लिया'
          : ((lower.contains('दिया') || lower.contains('diya') || lower.contains('दे')) ? 'पानी दिया' : 'पानी का लेन-देन');
      final person = _extractPerson(t, fromMarkers: ['से', 'se'], toMarkers: ['को', 'ko']);
      return person == null ? '$source का $action' : '$source का $action - $person से';
    }

    // Farm input purchases: create a short category title, not the full transcript.
    final isPurchase = lower.contains('खरीद') || lower.contains(' खरीदा') || lower.contains('purchase') || lower.contains('bought') || lower.contains('buy');
    if (isPurchase) {
      final items = <String>[];
      if (lower.contains('खाद') || lower.contains('fertilizer') || lower.contains('khaad')) items.add('खाद');
      if (lower.contains('बीज') || lower.contains('seed') || lower.contains('beej')) items.add('बीज');
      if (lower.contains('दवा') || lower.contains('स्प्रे') || lower.contains('pesticide') || lower.contains('spray')) items.add('दवा/स्प्रे');
      if (lower.contains('डीजल') || lower.contains('diesel')) items.add('डीजल');
      if (lower.contains('कीटनाशक') || lower.contains('insecticide')) items.add('कीटनाशक');
      if (items.isEmpty) items.add('सामान खरीदा');
      final person = _extractPerson(t, fromMarkers: ['से', 'se'], toMarkers: ['को', 'ko']);
      final amount = _extractAmount(t);
      final base = person == null ? '${items.join(' और ')} खरीदी' : '${items.join(' और ')} खरीदी - ${person} से';
      return amount == null ? base : '$base - ₹$amount';
    }

    // Money transactions: distinguish money received from money paid.
    final isMoney = lower.contains('पैसे') || lower.contains('रुपये') || lower.contains('रुपए') ||
        lower.contains('रुपया') || lower.contains('paise') || lower.contains('paisa') ||
        lower.contains('rupees') || lower.contains('payment') || lower.contains('पेमेंट') ||
        lower.contains('उधार') || lower.contains('जमा');
    if (isMoney) {
      final paid = lower.contains('दिए') || lower.contains('दी') || lower.contains('diye') ||
          lower.contains('diya') || lower.contains('pay kiye') || lower.contains('paid') ||
          lower.contains('दे दिए') || lower.contains('देना');
      final received = lower.contains('लिए') || lower.contains('liya') || lower.contains('liye') ||
          lower.contains('मिले') || lower.contains('mila') || lower.contains('received') ||
          lower.contains('वापस मिला');
      final person = _extractPerson(t, fromMarkers: ['से', 'se'], toMarkers: ['को', 'ko']);
      final amount = _extractAmount(t);
      final suffix = amount == null ? '' : ' - ₹$amount';
      if (paid && person != null) return '$person को पैसे दिए$suffix';
      if (received && person != null) return '$person से पैसे लिए$suffix';
      if (paid) return 'पैसे दिए$suffix';
      if (received) return 'पैसे लिए$suffix';
      return 'पैसों का लेन-देन$suffix';
    }
    return 'Voice Note';
  }

  String? _extractAmount(String text) {
    // Capture numeric amount, including Hindi digits, when spoken in the note.
    final normalized = text
        .replaceAll('०', '0').replaceAll('१', '1').replaceAll('२', '2')
        .replaceAll('३', '3').replaceAll('४', '4').replaceAll('५', '5')
        .replaceAll('६', '6').replaceAll('७', '7').replaceAll('८', '8')
        .replaceAll('९', '9');
    final matches = RegExp(r'(?<![A-Za-z])(?:₹|rs\\.?\\s*)?([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]+)?)(?![A-Za-z])', caseSensitive: false).allMatches(normalized);
    if (matches.isEmpty) return null;
    // Prefer a number explicitly tied to rupees/amount; otherwise use the first number.
    for (final match in matches) {
      final value = match.group(1)?.replaceAll(',', '');
      if (value == null) continue;
      final after = normalized.substring(match.end).toLowerCase();
      final before = normalized.substring(0, match.start).toLowerCase();
      if (after.startsWith(RegExp(r'\\s*(रुपये|रुपए|रुपया|rs|rupees|रू)')) ||
          before.endsWith(RegExp(r'(₹|rs\\.?\\s*)'))) return value;
    }
    return matches.first.group(1)?.replaceAll(',', '');
  }

  String? _extractPerson(String text, {required List<String> fromMarkers, required List<String> toMarkers}) {
    // Prefer explicit person phrases: "X से" / "X को", then "से X" / "को X".
    final patterns = [
      RegExp(r'([\\p{L}]+(?:\\s+[\\p{L}]+){0,2})\\s+(?:से|को|se|ko)', unicode: true, caseSensitive: false),
      RegExp(r'(?:से|को|se|ko)\\s+([\\p{L}]+(?:\\s+[\\p{L}]+){0,2})', unicode: true, caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final candidate = match.group(1)?.trim();
      if (candidate == null || candidate.isEmpty) continue;
      if (RegExp(r'(पानी|नहर|कुए|मिनट|लिए|लिया|दिया|आज|कल|काम|पैसे|रुपये|रुपए|रुपया|उधार|लेन|देन|payment|water|money|from|to)', unicode: true, caseSensitive: false).hasMatch(candidate)) continue;
      return candidate;
    }
    return null;
  }
  void suggestTitle() {
    if (title.text.trim().isNotEmpty) return;
    final suggested = _makeSmartTitle(transcript.text);
    if (suggested.isNotEmpty) title.text = suggested;
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
      final autoTitle = _makeSmartTitle(transcript.text);
      final noteTitle = title.text.trim().isNotEmpty ? title.text.trim() : (autoTitle.isNotEmpty ? autoTitle : 'Voice Note ${now.day}/${now.month}/${now.year}');
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
            if (hasAudio) IconButton(icon: Icon(playing == audio ? Icons.pause : Icons.play_arrow), onPressed: () => playAudio(audio)),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => deleteNote(note)),
          ]),
        ));
      }),
    ]),
  );
}
