import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/storage_backup_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = StorageBackupService.instance;
  final _search = TextEditingController();
  String _filter = 'All';

  DateTime _date(Map<String, dynamic> row) {
    for (final key in ['updatedAt', 'createdAt', 'date']) {
      final value = row[key];
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return DateTime.now();
  }

  String _str(dynamic value) => value is String ? value.trim() : '';
  String _minutes(dynamic value) {
    final m = value is int ? value : int.tryParse('$value') ?? 0;
    return m >= 60 ? '${m ~/ 60} hr ${m % 60} min' : '$m min';
  }

  List<_Item> _items() {
    final all = <_Item>[];
    for (final r in _storage.records('hisabs')) {
      all.add(_Item('HISAB', _str(r['title']).isEmpty ? _str(r['category']) : _str(r['title']),
        [_str(r['category']), if (_str(r['amount']).isNotEmpty) '₹${r['amount']}', _str(r['note'])].where((s)=>s.isNotEmpty).join(' · '), _date(r)));
    }
    for (final r in _storage.records('khet')) {
      final water = r.containsKey('source') || r.containsKey('minutes') || r.containsKey('direction');
      all.add(_Item(water ? 'PANI' : 'KHET',
        water ? '${_str(r['contact']).isEmpty ? 'Pani' : _str(r['contact'])} · ${_str(r['source'])}' : (_str(r['title']).isEmpty ? _str(r['type']) : _str(r['title'])),
        water ? '${_str(r['direction'])} · ${_minutes(r['minutes'])}' : [_str(r['type']), if (_str(r['price']).isNotEmpty) '₹${r['price']}', _str(r['note'])].where((s)=>s.isNotEmpty).join(' · '), _date(r)));
    }
    for (final r in _storage.records('members')) {
      final docs = (r['documents'] as List? ?? []).length;
      all.add(_Item('DOCUMENTS', 'Member · ${_str(r['name'])}', docs == 0 ? 'Member record' : '$docs document(s)', _date(r)));
    }
    for (final r in _storage.records('products')) {
      all.add(_Item('DOCUMENTS', 'Product · ${_str(r['name'])}', _str(r['note']), _date(r)));
    }
    all.sort((a,b)=>b.date.compareTo(a.date));
    final q=_search.text.trim().toLowerCase();
    return all.where((i)=>(_filter=='All'||i.type==_filter)&&('${i.type} ${i.title} ${i.subtitle}').toLowerCase().contains(q)).toList();
  }

  @override
  void dispose(){_search.dispose();super.dispose();}
  @override
  Widget build(BuildContext context) {
    final rows=_items();
    const filters=['All','HISAB','KHET','PANI','DOCUMENTS'];
    return Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,8,16,10),child:TextField(controller:_search,onChanged:(_)=>setState(()=>{}),decoration:InputDecoration(hintText:'Search history',prefixIcon:const Icon(Icons.search),suffixIcon:_search.text.isEmpty?null:IconButton(icon:const Icon(Icons.clear),onPressed:()=>setState(_search.clear)),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none)))),
      SizedBox(height:44,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),children:filters.map((f)=>Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:ChoiceChip(label:Text(f),selected:_filter==f,onSelected:(_)=>setState(()=>_filter=f))).toList())),
      Expanded(child:rows.isEmpty?const Center(child:Text('No history records found')):ListView.builder(padding:const EdgeInsets.all(16),itemCount:rows.length,itemBuilder:(context,index){final i=rows[index];final icon=switch(i.type){'HISAB'=>Icons.receipt_long_outlined,'KHET'=>Icons.agriculture_outlined,'PANI'=>Icons.water_drop_outlined,_=>Icons.folder_outlined};return Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(leading:CircleAvatar(child:Icon(icon)),title:Text(i.title.isEmpty?i.type:i.title,style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text('${i.subtitle.isEmpty?'':i.subtitle+'\n'}${DateFormat('dd MMM yyyy · hh:mm a').format(i.date)}'),isThreeLine:i.subtitle.isNotEmpty,trailing:Text(i.type,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold))));})),
    ]);
  }
}

class _Item {
  _Item(this.type,this.title,this.subtitle,this.date);
  final String type,title,subtitle;
  final DateTime date;
}
