import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/storage_backup_service.dart';

class VoiceNotesScreen extends StatefulWidget { const VoiceNotesScreen({super.key}); @override State<VoiceNotesScreen> createState()=>_VoiceNotesScreenState(); }
class _VoiceNotesScreenState extends State<VoiceNotesScreen> {
 final storage=StorageBackupService.instance, recorder=AudioRecorder(), speech=stt.SpeechToText(), player=AudioPlayer();
 final transcript=TextEditingController(), title=TextEditingController();
 bool recording=false,listening=false,ready=false,busy=false; String? tempAudio,playing;
 List<Map<String,dynamic>> get notes=>storage.records('voiceNotes');
 @override void initState(){super.initState();speech.initialize().then((v){if(mounted)setState(()=>ready=v);});player.onPlayerComplete.listen((_) {if(mounted)setState(()=>playing=null);});}
 @override void dispose(){recorder.dispose();speech.stop();player.dispose();transcript.dispose();title.dispose();super.dispose();}
 void suggest(){final w=transcript.text.trim().split(RegExp(r'\s+')).take(5).join(' ');if(title.text.trim().isEmpty&&w.isNotEmpty)title.text=w;}
 Future<void> listen()async{if(!ready){msg('Speech recognition available nahi hai.');return;}if(listening){await speech.stop();setState(()=>listening=false);suggest();return;}setState(()=>listening=true);await speech.listen(localeId:'hi_IN',onResult:(r){transcript.text=r.recognizedWords;transcript.selection=TextSelection.collapsed(offset:transcript.text.length);if(r.finalResult){setState(()=>listening=false);suggest();}else if(mounted)setState((){});});}
 Future<void> start()async{if(!await recorder.hasPermission()){msg('Microphone permission allow karein.');return;}tempAudio=p.join(Directory.systemTemp.path,'khata_voice_${DateTime.now().millisecondsSinceEpoch}.m4a');await recorder.start(const RecordConfig(encoder:AudioEncoder.aacLc),path:tempAudio!);setState(()=>recording=true);}
 Future<void> stop()async{tempAudio=await recorder.stop()??tempAudio;setState(()=>recording=false);}
 Future<void> save()async{if(busy)return;if(tempAudio==null&&transcript.text.trim().isEmpty){msg('Audio record ya bolkar text likhein.');return;}setState(()=>busy=true);try{final now=DateTime.now();final words=transcript.text.trim().split(RegExp(r'\s+')).take(5).join(' ');final t=title.text.trim().isEmpty?(words.isEmpty?'Voice Note ${now.day}/${now.month}/${now.year}':words):title.text.trim();String? audio;if(tempAudio!=null&&await File(tempAudio!).exists())audio=await storage.keepFile(tempAudio!,folder:'VoiceNotes',filename:'voice.m4a');await storage.addRecord('voiceNotes',{'id':now.microsecondsSinceEpoch.toString(),'title':t,'transcript':transcript.text.trim(),'audio':audio,'date':now.toIso8601String()});transcript.clear();title.clear();tempAudio=null;if(mounted)setState(()=>busy=false);msg('Voice note saved.');}catch(e){if(mounted)setState(()=>busy=false);msg('Save nahi hua: $e');}}
 Future<void> delete(Map<String,dynamic> n)async{final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Delete voice note?'),content:Text('“${n['title']}” delete ho jayega.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))]));if(ok!=true)return;await storage.deleteRecord('voiceNotes',n['id'] as String);final path=n['audio'] as String?;if(path!=null){try{final file=File(path);if(await file.exists())await file.delete();}catch(_){}}if(mounted)setState((){});}
 Future<void> play(String path)async{if(playing==path){await player.pause();setState(()=>playing=null);}else{await player.play(DeviceFileSource(path));setState(()=>playing=path);}}
 void msg(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
 @override Widget build(BuildContext context)=>Scaffold(body:ListView(padding:const EdgeInsets.fromLTRB(16,12,16,90),children:[
 Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 const Text('Naya Voice Note',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),
 TextField(controller:title,decoration:const InputDecoration(labelText:'Title (optional)',hintText:'Auto title suggested')),
 const SizedBox(height:8),TextField(controller:transcript,minLines:2,maxLines:5,decoration:InputDecoration(labelText:'Bolkar text / notes',hintText:'Mic dabakar boliye…',suffixIcon:IconButton(onPressed:listen,icon:Icon(listening?Icons.mic:Icons.mic_none,color:listening?Colors.red:null)))),
 const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:recording?stop:start,icon:Icon(recording?Icons.stop:Icons.fiber_manual_record,color:recording?Colors.red:null),label:Text(recording?'Stop recording':'Record audio'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:busy?null:save,icon:const Icon(Icons.save),label:Text(busy?'Saving…':'Save note')))]),
 if(tempAudio!=null)const Padding(padding:EdgeInsets.only(top:8),child:Text('Audio ready to save',style:TextStyle(color:Colors.green))),
 ]))),
 const SizedBox(height:10),Text('Saved Voice Notes (${notes.length})',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
 if(notes.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('Abhi koi voice note nahi hai.')),
 ...notes.map((n)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.mic)),title:Text(n['title'] as String? ?? 'Voice note'),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[if((n['transcript'] as String? ?? '').isNotEmpty)Text(n['transcript'] as String,maxLines:3,overflow:TextOverflow.ellipsis),Text(n['date'] as String? ?? '',style:const TextStyle(fontSize:11))]),trailing:Wrap(mainAxisSize:MainAxisSize.min,children:[if(n['audio'] is String&&File(n['audio']).existsSync())IconButton(icon:Icon(playing==n['audio']?Icons.pause:Icons.play_arrow),onPressed:()=>play(n['audio'] as String)),IconButton(icon:const Icon(Icons.delete_outline,color:Colors.red),onPressed:()=>delete(n))]))),
 ]));
}