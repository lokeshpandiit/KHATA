import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/contact_picker_service.dart';
import '../services/khata_sharing_service.dart';
import '../services/storage_backup_service.dart';
import '../widgets/khata_widgets.dart';
import '../widgets/plot_selector.dart';
import '../widgets/multi_plot_selector.dart';
import '../widgets/farm_fields.dart';
import '../services/farm_reminder_service.dart';
import '../services/future_date_reminder_prompt.dart';
import '../widgets/voice_dictation_field.dart';

class KhetScreen extends StatefulWidget {
  const KhetScreen({super.key});

  @override
  State<KhetScreen> createState() => _KhetScreenState();
}

class _KhetScreenState extends State<KhetScreen> {
  final _storage = StorageBackupService.instance;
  final _search = TextEditingController();
  String _tab = 'ALL';
  String _month = 'All months';
  String _seasonFilter = 'All seasons';
  int? _yearFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _entries => _storage.records('khet');
  List<Map<String, dynamic>> get _contacts => _storage.records('contacts');

  String _plotLabel(dynamic id) => plotLabelForId(_storage, id);

  double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;
  }

  double _balance(Map<String, dynamic> row) {
    final value = row['balance'];
    if (value is num) return value.toDouble();
    return (_amount(row['totalAmount'] ?? row['price']) - _amount(row['paidAmount']))
        .clamp(0, double.infinity).toDouble();
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _entries.where((row) {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      final category = row['type'] as String? ?? '';
      final isPending = category == 'TRACTOR' ? _balance(row) > 0 : category == 'KHET_PURCHASE' && _purchaseBalance(row) > 0;
      final isPersonWaterLedger = category == 'PANI' && row['ledgerMode'] == 'PERSON';
      final isPurchase = category == 'KHET_PURCHASE' || category == 'KHET_PURCHASE_PAYMENT' || category == 'KHET_STOCK_USE';
      final typeMatch = _tab == 'ALL' ||
          (_tab == 'PENDING'
              ? isPending
              : _tab == 'PURCHASE'
                  ? isPurchase
                  : _tab == 'KUA'
                      ? (category == 'KUA' && row['direction'] == 'Dusre ne hamara kua chalaya') ||
                          (isPersonWaterLedger && row['direction'] == 'Diya')
                      : category == _tab);
      final monthMatch = _month == 'All months' ||
          (date != null && monthKey(date) == _month);
      final seasonMatch = _seasonFilter == 'All seasons' || row['season'] == _seasonFilter;
      final yearMatch = _yearFilter == null ||
          (date != null ? date.year == _yearFilter : row['year'] == _yearFilter);
      final searchable =
          '${row['title'] ?? ''} ${row['note'] ?? ''} ${row['contact'] ?? ''} ${row['source'] ?? ''} ${row['wellType'] ?? ''} ${row['customerName'] ?? ''} ${row['farmName'] ?? ''} ${row['work'] ?? ''} ${row['cropName'] ?? ''} ${row['seedName'] ?? ''} ${row['purpose'] ?? ''}'
              .toLowerCase();
      return typeMatch && monthMatch && seasonMatch && yearMatch && searchable.contains(query);
    }).toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
  }

  Future<void> _addEntry() async {
    if (_tab == 'ALL') {
      await _chooseEntryType();
    } else if (_tab == 'PENDING') {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const AddTractorWorkScreen(),
      ));
    } else if (_tab == 'KUA') {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddKuaHisabScreen()));
    } else if (_tab == 'PANI') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AddPaniScreen()),
      );
    } else if (_tab == 'TRACTOR') {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const AddTractorWorkScreen(),
      ));
    } else if (_tab == 'PURCHASE') {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KhetPurchaseScreen()));
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AddKhetItemScreen(type: _tab),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _chooseEntryType() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: ['PURCHASE', 'DAWAI', 'KHAD', 'FASAL', 'TRACTOR', 'OTHER']
              .map((item) => ListTile(
                    leading: Icon(item == 'TRACTOR' ? Icons.agriculture : Icons.add_circle_outline),
                    title: Text(item),
                    onTap: () => Navigator.pop(context, item),
                  ))
              .toList(),
        ),
      ),
    );
    if (type == null || !mounted) return;
    setState(() => _tab = type);
    await _addEntry();
  }

  Future<void> _addContact() async {
    try {
      final picked = await ContactPickerService.pickPhoneContact();
      if (picked == null) return;
      final phone = KhataSharingService.normalizePhone(picked['phone']!);
      final existing = _contacts.where(
        (item) => KhataSharingService.normalizePhone((item['phone'] ?? '').toString()) == phone,
      );
      if (existing.isEmpty) {
        final now = DateTime.now();
        await _storage.addRecord('contacts', {
          'id': now.microsecondsSinceEpoch.toString(),
          'name': picked['name'],
          'phone': picked['phone'],
          'date': now.toIso8601String(),
        });
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not pick contact: $error');
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<Map<String, dynamic>> _vendorPurchases(dynamic vendorId) => _entries.where((r) => r['type']=='KHET_PURCHASE' && r['vendorId']==vendorId).toList();
  List<Map<String, dynamic>> _vendorPayments(dynamic vendorId) => _entries.where((r) => r['type']=='KHET_PURCHASE_PAYMENT' && r['vendorId']==vendorId).toList();
  double _vendorBalance(dynamic vendorId) {
    final p=_vendorPurchases(vendorId);
    return p.fold<double>(0,(s,r)=>s+_amount(r['totalAmount'])-_amount(r['paidAmount']))-
      _vendorPayments(vendorId).fold<double>(0,(s,r)=>s+_amount(r['amount']));
  }
  double _purchaseBalance(Map<String,dynamic> purchase) {
    final purchases=_vendorPurchases(purchase['vendorId'])..sort((a,b)=>(a['invoiceDate']??a['date']??'').toString().compareTo((b['invoiceDate']??b['date']??'').toString()));
    var pay=_vendorPayments(purchase['vendorId']).fold<double>(0,(s,r)=>s+_amount(r['amount']));
    for(final p in purchases){
      var balance=(_amount(p['totalAmount'])-_amount(p['paidAmount'])).clamp(0,double.infinity).toDouble();
      final applied=pay<balance?pay:balance;balance-=applied;pay-=applied;
      if(p['id']==purchase['id'])return balance;
    }
    return _balance(purchase);
  }
  Widget _vendorNetCards(){
    final ids=_entries.where((r)=>r['type']=='KHET_PURCHASE').map((r)=>r['vendorId']).where((id)=>id!=null).toSet();
    if(ids.isEmpty)return const SizedBox.shrink();
    return SizedBox(height:108,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),children:ids.map((id){
      final purchases=_vendorPurchases(id);final name=(purchases.first['vendorName']??'Shop').toString();final balance=_vendorBalance(id);
      return SizedBox(width:220,child:Card(child:InkWell(onTap:()=>_showVendorLedger(id),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(name,style:const TextStyle(fontWeight:FontWeight.w800)),const Spacer(),
        Text(balance>=0?'Pending ₹${balance.toStringAsFixed(0)}':'Advance ₹${balance.abs().toStringAsFixed(0)}',style:TextStyle(fontWeight:FontWeight.w800,color:balance>0?Colors.red:Colors.green)),
        const Text('Tap to open vendor khata',style:TextStyle(fontSize:11)),
      ])))));
    }).toList()));
  }
  Future<void> _showVendorLedger(dynamic vendorId)async{
    final p=_vendorPurchases(vendorId);if(p.isEmpty)return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>KhetVendorLedgerScreen(vendorId:vendorId.toString(),vendorName:(p.first['vendorName']??'Shop').toString())));
    if(mounted)setState((){});
  }
  Future<void> _usePurchaseStock(Map<String,dynamic> purchase)async{
    final available=(_amount(purchase['quantity'])-_entries.where((r)=>r['type']=='KHET_STOCK_USE'&&r['purchaseId']==purchase['id']).fold<double>(0,(s,r)=>s+_amount(r['quantityUsed']))).clamp(0,double.infinity).toDouble();
    if(available<=0){_error('Is purchase ka stock poora use ho chuka hai.');return;}
    final qty=TextEditingController();String? plotId;DateTime date=DateTime.now();
    final result=await showDialog<Map<String,dynamic>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD){
      final plots=_storage.records('plots').where((p)=>p['isMine']!=false).toList();
      return AlertDialog(title:Text('Use ${purchase['title']} in Khet'),content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Available ${available.toStringAsFixed(2)} ${purchase['unit']??''}'),
        TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Quantity used')),
        DropdownButtonFormField<String>(value:plotId,decoration:const InputDecoration(labelText:'Killa'),items:plots.map((p)=>DropdownMenuItem(value:p['id'].toString(),child:Text(plotLabel(p)))).toList(),onChanged:(v)=>setD(()=>plotId=v)),
        OutlinedButton(onPressed:()async{final p=await showDatePicker(context:ctx,initialDate:date,firstDate:DateTime(DateTime.now().year-8),lastDate:DateTime(DateTime.now().year+8));if(p!=null)setD(()=>date=p);},child:Text('Use date: ${dateLabel(date)}')),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:(){final n=double.tryParse(qty.text);if(n!=null&&n>0&&n<=available&&plotId!=null)Navigator.pop(ctx,{'qty':n,'plot':plotId,'date':date});},child:const Text('Save'))]);
    }));
    qty.dispose();if(result==null)return;
    final cycle=_cropCycleForDate(_storage,result['plot'] as String,result['date'] as DateTime);
    final q=_amount(purchase['quantity']);final unitCost=_amount(purchase['totalAmount'])/(q<=0?1:q);
    await _storage.addRecord('khet',{'id':DateTime.now().microsecondsSinceEpoch.toString(),'type':'KHET_STOCK_USE','purchaseId':purchase['id'],'title':purchase['title'],'purchaseCategory':purchase['purchaseCategory'],'quantityUsed':result['qty'],'unit':purchase['unit'],'price':unitCost*(result['qty'] as double),'plotId':result['plot'],'cropCycleId':cycle?['cropCycleId'],'cropAtUse':cycle?['cropName']??cycle?['title'],'vendorId':purchase['vendorId'],'vendorName':purchase['vendorName'],'date':(result['date'] as DateTime).toIso8601String(),'note':'Purchase date: ${purchase['invoiceDate']}'});
    if(mounted)setState((){});
  }
  bool _isPersonWaterLedger(Map<String, dynamic> row) =>
      row['type'] == 'PANI' && row['ledgerMode'] == 'PERSON';

  List<Map<String, dynamic>> _personWaterRows(dynamic contactId) => _entries
      .where((row) => _isPersonWaterLedger(row) && row['contactId'] == contactId)
      .toList();

  int _personWaterTotal(List<Map<String, dynamic>> rows, String direction) =>
      rows.where((row) => row['direction'] == direction).fold<int>(
        0,
        (sum, row) => sum + ((row['minutes'] as num?)?.toInt() ?? 0),
      );

  int _personWaterTotalByWell(
    List<Map<String, dynamic>> rows,
    String direction,
    String wellType,
  ) =>
      rows.where((row) =>
          row['direction'] == direction && row['wellType'] == wellType).fold<int>(
        0,
        (sum, row) => sum + ((row['minutes'] as num?)?.toInt() ?? 0),
      );

  Widget _personWaterNetCards() {
    final cards = <Widget>[];
    for (final contact in _contacts) {
      final rows = _personWaterRows(contact['id']);
      if (rows.isEmpty) continue;
      final given = _personWaterTotal(rows, 'Diya');
      final taken = _personWaterTotal(rows, 'Liya');
      final solarNet = _personWaterTotalByWell(rows, 'Diya', 'Solar') -
          _personWaterTotalByWell(rows, 'Liya', 'Solar');
      final dieselNet = _personWaterTotalByWell(rows, 'Diya', 'Diesel') -
          _personWaterTotalByWell(rows, 'Liya', 'Diesel');
      final net = solarNet + dieselNet;
      cards.add(Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(
                    (contact['name'] ?? 'व्यक्ति').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  )),
                  IconButton(
                    tooltip: 'व्यक्ति का नेट हिसाब शेयर करें',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _shareNet(contact),
                    icon: const Icon(Icons.share_outlined, size: 19),
                  ),
                ]),
                Text('दिया: +${formatMinutes(given)}   लिया: −${formatMinutes(taken)}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  '☀️ सोलर: ${formatSignedMinutes(solarNet)}   ⛽ डीजल: ${formatSignedMinutes(dieselNet)}',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 5),
                Text(
                  'NET: ${formatSignedMinutes(net)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: net > 0 ? Colors.green : net < 0 ? Colors.red : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (cards.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('व्यक्ति के पानी का हिसाब यहाँ दिखाई देगा।',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('व्यक्ति-wise पानी का नेट हिसाब',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          ...cards,
        ],
      ),
    );
  }

  Future<void> _sharePani(Map<String, dynamic> row) async {
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    final contact = _contacts.where((item) => item['id'] == row['contactId']).toList();
    final phone = (row['contactPhone'] ?? (contact.isEmpty ? null : contact.first['phone']))?.toString();
    final note = (row['note'] as String? ?? '').trim();
    var includeNote = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Share Pani Hisab'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: includeNote,
            onChanged: note.isEmpty
                ? null
                : (value) => setDialogState(() => includeNote = value ?? false),
            title: const Text('Note bhi bhejna hai?'),
            subtitle: Text(
              note.isEmpty ? 'Is entry mein koi note nahi hai.' : note,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Share'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    final template = prefs.getString(row['direction'] == 'Liya' ? 'pani_received_message' : 'pani_given_message') ??
        (row['direction'] == 'Liya' ? 'Maine {naam} se {minute} minute pani liya. Date: {date}' : 'Maine {naam} ko {minute} minute pani diya. Date: {date}');
    final contactName = (row['contact'] ?? 'samne wale').toString();
    final minuteText = formatMinutes((row['minutes'] as num?)?.toInt() ?? 0);
    final dateText = date == null ? '' : dateLabel(date);
    final customized = template
        .replaceAll('{naam}', contactName)
        .replaceAll('{minute}', minuteText)
        .replaceAll('{date}', dateText);
    await KhataSharingService.share(
      phone: phone,
      text: [
        customized,
        if (row['wellType'] != null) 'Kua: ${row['wellType']}' else 'Source: ${row['source']}',
        if (row['plotId'] != null && _plotLabel(row['plotId']).isNotEmpty) 'Killa: ${_plotLabel(row['plotId'])}',
        if (row['wetKyaris'] != null) 'Kyari: ${row['wetKyaris']} bheegi, ${row['remainingKyaris']} baaki',
        if (row['season'] != null || row['year'] != null) 'Season: ${row['season'] ?? ''} ${row['year'] ?? ''}',
        if (includeNote && note.isNotEmpty) 'Note: $note',
      ].join('\n'),
    );
  }

  Future<void> _shareKhet(Map<String, dynamic> row) async {
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    final files = _paths(row, 'itemPhotos', 'itemPhoto') +
        _paths(row, 'billPhotos', 'billPhoto');
    await KhataSharingService.share(
      text: [
        'Khet Hisab - ${_storage.senderName}',
        'Type: ${row['type']}',
        if (row['plotId'] != null && _plotLabel(row['plotId']).isNotEmpty) 'Killa: ${_plotLabel(row['plotId'])}',
        if (row['season'] != null || row['year'] != null) 'Season: ${row['season'] ?? ''} ${row['year'] ?? ''}',
        if (row['purpose'] != null) 'Dawai type: ${row['purpose']}',
        if (row['cropAtUse'] != null) 'Current crop: ${row['cropAtUse']}',
        if (row['kyariNumber'] != null) 'Kyari: ${row['kyariNumber']}',
        if ((row['title'] as String? ?? '').isNotEmpty) 'Name: ${row['title']}',
        if ((row['price'] as String? ?? '').isNotEmpty) 'Price: ₹${row['price']}',
        if ((row['note'] as String? ?? '').isNotEmpty) 'Note: ${row['note']}',
        if (date != null) 'Date: ${dateLabel(date)} ${timeLabel(date)}',
      ].join('\n'),
      files: files,
    );
  }

  List<String> _paths(Map<String, dynamic> row, String listKey, String legacyKey) {
    final list = (row[listKey] as List? ?? const []).whereType<String>().toList();
    final legacy = row[legacyKey];
    if (legacy is String && legacy.isNotEmpty && !list.contains(legacy)) list.insert(0, legacy);
    return list.where((path) => File(path).existsSync()).toList();
  }

  Future<void> _shareTractor(Map<String, dynamic> row) async {
    final due = DateTime.tryParse(row['dueDate'] as String? ?? '');
    final files = (_paths(row, 'billPhotos', 'billPhoto') +
        _paths(row, 'itemPhotos', 'itemPhoto')).toSet().toList();
    await KhataSharingService.share(
      phone: row['customerPhone'] as String?,
      text: [
        '🚜 ट्रैक्टर का हिसाब',
        'काम: ${row['work'] ?? ''}',
        'कुल बिल: ₹${_amount(row['totalAmount']).toStringAsFixed(0)}',
        'जमा: ₹${_amount(row['paidAmount']).toStringAsFixed(0)}',
        'बाकी: ₹${_balance(row).toStringAsFixed(0)}',
        if (due != null) 'भुगतान की अंतिम तारीख: ${DateFormat('dd MMM yyyy').format(due)}',
      ].join('\n'),
      files: files,
    );
  }

  Future<void> _shareNet(Map<String, dynamic> contact) async {
    final rows = _personWaterRows(contact['id']);
    final balances = <String, int>{'Solar': 0, 'Diesel': 0};
    for (final row in rows) {
      final well = (row['wellType'] ?? 'Solar').toString();
      final minutes = (row['minutes'] as num?)?.toInt() ?? 0;
      final delta = row['direction'] == 'Diya'
          ? minutes
          : row['direction'] == 'Liya'
              ? -minutes
              : 0;
      balances[well] = (balances[well] ?? 0) + delta;
    }
    final totalNet = balances.values.fold<int>(0, (sum, value) => sum + value);
    await KhataSharingService.share(
      phone: contact['phone'] as String?,
      text: [
        'Pani Net Hisab - ${_storage.senderName}',
        'Solar Kua: ${formatSignedMinutes(balances['Solar'] ?? 0)}',
        'Diesel Kua: ${formatSignedMinutes(balances['Diesel'] ?? 0)}',
        'TOTAL NET: ${formatSignedMinutes(totalNet)}',
      ].join('\n'),
    );
  }

  Future<void> _deletePaniEntry(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Pani entry?'),
        content: Text(
          'Kya ' + (row['contact'] ?? 'Contact').toString() + ' ki ' + (row['direction'] ?? '').toString() + ' wali ' +
          formatMinutes((row['minutes'] as num?)?.toInt() ?? 0) + ' entry delete karni hai? Delete karne ke baad yeh pani hisab/net balance mein nahi dikhegi.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.deleteRecord('khet', row['id'] as String);
    if (mounted) setState(() {});
  }

  Future<void> _recordTractorPayment(Map<String, dynamic> row) async {
    final controller = TextEditingController();
    String direction = 'Diya';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Payment entry'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: direction,
              decoration: const InputDecoration(labelText: 'Payment type'),
              items: const [
                DropdownMenuItem(value: 'Diya', child: Text('💸 Paise diye')),
                DropdownMenuItem(value: 'Liya', child: Text('💰 Paise liye')),
              ],
              onChanged: (v) => setDialogState(() => direction = v ?? direction),
            ),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: direction == 'Diya' ? 'Amount given (₹)' : 'Amount received (₹)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value != null && value > 0) Navigator.pop(dialogContext, {'amount': value, 'direction': direction});
              },
              child: const Text('Save payment'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    final amount = result['amount'] as double;
    direction = result['direction'] as String;
    final total = _amount(row['totalAmount'] ?? row['price']);
    final oldPaid = _amount(row['paidAmount']);
    if (direction == 'Diya' && amount > (total - oldPaid).clamp(0, double.infinity)) {
      _error('Amount given cannot exceed pending balance ₹${(total - oldPaid).clamp(0, double.infinity).toStringAsFixed(0)}');
      return;
    }
    if (direction == 'Liya' && amount > oldPaid) {
      _error('Received amount cannot exceed previously given ₹${oldPaid.toStringAsFixed(0)}');
      return;
    }
    final paid = direction == 'Diya' ? oldPaid + amount : oldPaid - amount;
    final balance = (total - paid).clamp(0, double.infinity).toDouble();
    final updated = Map<String, dynamic>.from(row)
      ..['paidAmount'] = paid
      ..['balance'] = balance
      ..['status'] = balance <= 0 ? 'PAID' : (paid > 0 ? 'PARTIAL' : 'PENDING')
      ..['payments'] = [
        ...(row['payments'] as List? ?? const []),
        {'amount': amount, 'direction': direction, 'date': DateTime.now().toIso8601String()},
      ]
      ..['updatedAt'] = DateTime.now().toIso8601String();
    await _storage.updateRecord('khet', row['id'] as String, updated);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final months = availableMonths(_entries);
    if (!months.contains(_month)) _month = 'All months';
    final rows = _filtered;
    const tabs = ['ALL', 'PURCHASE', 'DAWAI', 'KHAD', 'FASAL', 'TRACTOR', 'KUA', 'OTHER'];
    final addLabel = switch (_tab) {
      'DAWAI' => 'Add Dawai',
      'KHAD' => 'Add Khaad',
      'FASAL' => 'Add Fasal',
      'HARA_BEEJ' => 'Add Hara Beej',
      'PANI' => 'Add Pani',
      'TRACTOR' || 'PENDING' => 'Add Tractor',
      'KUA' => 'Add Kua Hisab',
      'PURCHASE' => 'Add Purchase',
      'OTHER' => 'Add Other',
      _ => 'Add',
    };
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              children: [
                searchField((_) => setState(() {})),
                const SizedBox(height: 10),
                monthFilter(_month, months, (value) {
                  if (value != null) setState(() => _month = value);
                }),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    initialValue: _seasonFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Season', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'All seasons', child: Text('All seasons')),
                      DropdownMenuItem(value: 'Rabi', child: Text('Rabi')),
                      DropdownMenuItem(value: 'Kharif', child: Text('Kharif')),
                    ],
                    onChanged: (value) => setState(() => _seasonFilter = value ?? 'All seasons'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: DropdownButtonFormField<int?>(
                    initialValue: _yearFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Year', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All years')),
                      ...List.generate(9, (i) => DateTime.now().year - 3 + i)
                        .map((year) => DropdownMenuItem<int?>(value: year, child: Text(year.toString()))),
                    ],
                    onChanged: (value) => setState(() => _yearFilter = value),
                  )),
                ]),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: tabs.map((tab) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(tab),
                        selected: _tab == tab,
                        onSelected: (_) => setState(() => _tab = tab),
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
          if (_tab == 'PANI')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addContact,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('+ Pick Phone Contact'),
                ),
              ),
            ),
          if (_tab == 'PANI') _personWaterNetCards(),
          if (_tab == 'PURCHASE') _vendorNetCards(),
          Expanded(
            child: rows.isEmpty
                ? emptyState(
                    _tab == 'PENDING' ? 'No pending payments' : 'No Khet entries',
                    _tab == 'PENDING' ? 'Tractor work balances will appear here.' : 'Add farm and water records here.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: _buildGroups(rows),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEntry,
        icon: const Icon(Icons.add),
        label: Text(addLabel),
      ),
    );
  }

  List<Widget> _buildGroups(List<Map<String, dynamic>> rows) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      final label = date == null ? 'Date unavailable' : dateLabel(date);
      groups.putIfAbsent(label, () => []).add(row);
    }
    return groups.entries.expand((group) => [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(group.key, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF176B52))),
      ),
      ...group.value.map(_entryCard),
    ]).toList();
  }

  Widget _entryCard(Map<String, dynamic> row) {
    if (row['type'] == 'KHET_STOCK_USE') {
      final d=DateTime.tryParse(row['date'] as String? ?? '');
      return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.grass_outlined)),title:Text('Stock use · ${row['title']}'),subtitle:Text('${row['quantityUsed']} ${row['unit']??''} · ${row['plotId']==null?'-':_plotLabel(row['plotId'])} · ₹${_amount(row['price']).toStringAsFixed(0)}${d==null?'':' · ${dateLabel(d)}'}')));
    }
    if (row['type'] == 'KHET_PURCHASE_PAYMENT') {
      final d=DateTime.tryParse(row['date'] as String? ?? '');
      return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.payments_outlined)),title:Text('Payment · ${row['vendorName']??'Vendor'}'),subtitle:Text('₹${_amount(row['amount']).toStringAsFixed(0)} paid${d==null?'':' · ${dateLabel(d)}'}')));
    }
    if (row['type'] == 'KHET_PURCHASE') {
      final balance=_purchaseBalance(row);final d=DateTime.tryParse(row['invoiceDate'] as String? ?? row['date'] as String? ?? '');
      final photos=_paths(row,'itemPhotos','itemPhoto')+_paths(row,'billPhotos','billPhoto');
      return Card(margin:const EdgeInsets.only(bottom:9),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const CircleAvatar(child:Icon(Icons.shopping_bag_outlined)),const SizedBox(width:8),Expanded(child:Text('${row['title']} · ${row['vendorName']}',style:const TextStyle(fontWeight:FontWeight.w800))),Text(balance<=0?'PAID':'PENDING',style:TextStyle(color:balance>0?Colors.red:Colors.green,fontWeight:FontWeight.bold))]),
        Text('${row['purchaseCategory']} · ${row['quantity']} ${row['unit']}'),
        Text('Bill date: ${d==null?'-':dateLabel(d)}'),
        Wrap(spacing:10,children:[Text('Bill ₹${_amount(row['totalAmount']).toStringAsFixed(0)}'),Text('Paid ₹${_amount(row['paidAmount']).toStringAsFixed(0)}'),Text('Pending ₹${balance.toStringAsFixed(0)}')]),
        if(balance>0&&row['dueDate']!=null)Text('Due: ${dateLabel(DateTime.parse(row['dueDate']))}',style:const TextStyle(color:Colors.deepOrange)),
        if(photos.isNotEmpty)Wrap(spacing:6,children:photos.toSet().map((p)=>InkWell(onTap:()=>_preview(p),child:mediaThumbnail(p,size:64))).toList()),
        Wrap(spacing:8,children:[OutlinedButton.icon(onPressed:()=>_showVendorLedger(row['vendorId']),icon:const Icon(Icons.account_balance_wallet_outlined),label:const Text('Vendor Khata')),if(_amount(row['quantity'])>0)FilledButton.tonalIcon(onPressed:()=>_usePurchaseStock(row),icon:const Icon(Icons.grass_outlined),label:const Text('Use in Khet'))]),
      ])));
    }
    if (row['type'] == 'KUA') {
      final mins = (row['wellMinutes'] as Map? ?? const {}).entries
          .map((e) => '${e.key}: ${formatMinutes((e.value as num).toInt())}').join(' · ');
      final cash = _amount(row['cashAmount']);
      final paid = _amount(row['cashPaid']);
      final balance = (cash - paid).clamp(0, double.infinity).toDouble();
      return Card(margin: const EdgeInsets.only(bottom: 9), child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.water_drop_outlined)),
        title: Text((row['contact'] ?? 'Kua hisab').toString()),
        subtitle: Text('${row['direction'] ?? ''}\n$mins\nBadle mein: ${formatMinutes((row['exchangeMinutes'] as num?)?.toInt() ?? 0)} · Cash ₹${cash.toStringAsFixed(0)} · Paid ₹${paid.toStringAsFixed(0)} · Baaki ₹${balance.toStringAsFixed(0)}'),
        isThreeLine: true,
      ));
    }
    if (row['type'] == 'PANI') {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      final personLedger = _isPersonWaterLedger(row);
      final minutes = (row['minutes'] as num?)?.toInt() ?? 0;
      final wellType = (row['wellType'] ?? '').toString();
      final directionLabel = row['direction'] == 'Diya' ? 'पानी दिया' : 'पानी लिया';
      final dateText = date == null ? '' : dateLabel(date);
      return Card(
        margin: const EdgeInsets.only(bottom: 9),
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.water_drop)),
          title: Text([
            (row['contact'] ?? 'Contact').toString(),
            if (personLedger && wellType == 'Solar') '☀️ सोलर कुआँ'
            else if (personLedger && wellType == 'Diesel') '⛽ डीजल कुआँ'
            else if (!personLedger && (row['source'] ?? '').toString().isNotEmpty) row['source'].toString(),
            if (personLedger) directionLabel else (row['direction'] ?? '').toString(),
            if (row['plotId'] != null) _plotLabel(row['plotId']),
          ].where((part) => part.isNotEmpty).join(' · ')),
          subtitle: Text(
            personLedger
                ? '${row['direction'] == 'Diya' ? '+' : '−'}${formatMinutes(minutes)}'
                    '${dateText.isEmpty ? '' : '\\n$dateText'}'
                    '${(row['note'] as String? ?? '').isNotEmpty ? '\\n${row['note']}' : ''}'
                : '${formatMinutes(minutes)}'
                    '${row['wetKyaris'] == null ? '' : '\\nBheegi: ${row['wetKyaris']} / ${row['totalKyarisSnapshot'] ?? '-'} · Baaki: ${row['remainingKyaris'] ?? '-'}'}'
                    '${row['season'] == null ? '' : '\\n${row['season']} ${row['year'] ?? ''}'}'
                    '${(row['note'] as String? ?? '').isNotEmpty ? '\\n${row['note']}' : ''}'
                    '${date == null ? '' : '\\n${timeLabel(date)}'}',
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Share Pani hisab',
                onPressed: () => _sharePani(row),
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: 'Delete Pani entry',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deletePaniEntry(row),
              ),
            ],
          ),
        ),
      );
    }
    if (row['type'] == 'TRACTOR') {
      final due = DateTime.tryParse(row['dueDate'] as String? ?? '');
      final balance = _balance(row);
      final photos = _paths(row, 'itemPhotos', 'itemPhoto');
      return Card(
        margin: const EdgeInsets.only(bottom: 9),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(child: Icon(Icons.agriculture)),
              const SizedBox(width: 10),
              Expanded(child: Text((row['customerName'] ?? 'Customer').toString(),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Text(balance <= 0 ? 'PAID' : (balance < _amount(row['totalAmount']) ? 'PARTIAL' : 'PENDING'),
                style: TextStyle(fontWeight: FontWeight.w800, color: balance <= 0 ? Colors.green : Colors.red)),
            ]),
            const SizedBox(height: 6),
            Text('Field: ${row['farmName'] ?? '-'}'),
            if (row['plotId'] != null && _plotLabel(row['plotId']).isNotEmpty)
              Text('Killa: ${_plotLabel(row['plotId'])}'),
            Text('Work: ${row['work'] ?? '-'}'),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, children: [
              Text('Total ₹${_amount(row['totalAmount']).toStringAsFixed(0)}'),
              Text('Paid ₹${_amount(row['paidAmount']).toStringAsFixed(0)}', style: const TextStyle(color: Colors.green)),
              Text('Pending ₹${balance.toStringAsFixed(0)}', style: TextStyle(color: balance > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.w800)),
            ]),
            if (due != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text('Due date: ${DateFormat('dd MMM yyyy').format(due)}',
                  style: TextStyle(
                    color: due.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)) && balance > 0
                        ? Colors.red : Colors.black54,
                  )),
              ),
            if (photos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, children: photos.take(5).map((path) => InkWell(
                  onTap: () => _preview(path),
                  child: mediaThumbnail(path, size: 58),
                )).toList()),
              ),
            const Divider(height: 20),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => _shareTractor(row),
                icon: const Icon(Icons.share_outlined),
                label: const Text('WhatsApp Bill'),
              ),
              FilledButton.tonalIcon(
                  onPressed: () => _recordTractorPayment(row),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Add Payment'),
                ),
            ]),
          ]),
        ),
      );
    }
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    final photos = _paths(row, 'itemPhotos', 'itemPhoto') +
        _paths(row, 'billPhotos', 'billPhoto');
    final visiblePhotos = photos.toSet().toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row['title'] as String? ?? row['type'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (row['plotId'] != null && _plotLabel(row['plotId']).isNotEmpty)
                    Text(_plotLabel(row['plotId']), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  if ((row['price'] ?? '').toString().isNotEmpty && row['price'] != 0) Text('₹${row['price']}'),
                  if (row['season'] != null || row['year'] != null)
                    Text('Season: ${row['season'] ?? ''} ${row['year'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  if (row['type'] == 'FASAL' && row['sowingDate'] != null)
                    Text('Beejne ki date: ${dateLabel(DateTime.parse(row['sowingDate'] as String))}'),
                  if (row['type'] == 'FASAL' && row['harvested'] == true && row['harvestDate'] != null)
                    Text('Fasal katne ki date: ${dateLabel(DateTime.parse(row['harvestDate'] as String))}', style: const TextStyle(color: Colors.green)),
                  if (row['type'] == 'FASAL' && row['harvested'] != true && row['plannedHarvestDate'] is String)
                    Text('Fasal katne ki planned date: ${dateLabel(DateTime.parse(row['plannedHarvestDate'] as String))}', style: const TextStyle(color: Colors.deepOrange)),
                  if (row['type'] == 'HARA_BEEJ')
                    Text('Kyari: ${row['kyariNumber'] ?? '-'}'),
                  if (row['type'] == 'DAWAI') ...[
                    Text('Dawai: ${row['purpose'] ?? '-'}'),
                    Text('Us waqt fasal: ${row['cropAtUse'] ?? 'Not recorded'}'),
                    if (row['reminderDate'] is String)
                      Text('Reminder: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(row['reminderDate'] as String))}', style: const TextStyle(color: Colors.deepOrange)),
                  ],
                  if ((row['note'] as String? ?? '').isNotEmpty) Text(row['note'] as String),
                  if (date != null)
                    Text('${timeLabel(date)} · ${row['type']}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  if ((row['billPhoto'] as String? ?? '').isNotEmpty || (row['billPhotos'] as List? ?? []).isNotEmpty)
                    const Text('Bill photo attached', style: TextStyle(fontSize: 12)),
                  if (visiblePhotos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Wrap(spacing: 6, runSpacing: 6, children: visiblePhotos.map((path) =>
                        InkWell(onTap: () => _preview(path), child: mediaThumbnail(path, size: 58)),
                      ).toList()),
                    ),
                ],
              ),
            ),
            if (row['type'] != 'FASAL')
              IconButton(tooltip: 'Share', onPressed: () => _shareKhet(row), icon: const Icon(Icons.share_outlined)),
          ],
        ),
      ),
    );
  }

  void _preview(String path) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(child: Image.file(File(path)))),
      ),
    ));
  }
}

Map<String,dynamic>? _cropCycleForDate(StorageBackupService storage,String plotId,DateTime date){
  final day=DateUtils.dateOnly(date);
  final crops=storage.records('khet').where((r){
    if(r['type']!='FASAL'||r['plotId']!=plotId)return false;
    final sow=DateTime.tryParse((r['sowingDate']??r['date']??'').toString());
    if(sow==null||DateUtils.dateOnly(sow).isAfter(day))return false;
    final harvest=DateTime.tryParse((r['harvestDate']??'').toString());
    final completed=r['harvested']==true||r['cropCycleStatus']=='COMPLETED';
    if(completed&&harvest==null)return false;
    return harvest==null||!day.isAfter(DateUtils.dateOnly(harvest));
  }).toList()..sort((a,b)=>(DateTime.tryParse((b['sowingDate']??b['date']??'').toString())??DateTime(0)).compareTo(DateTime.tryParse((a['sowingDate']??a['date']??'').toString())??DateTime(0)));
  if(crops.isEmpty)return null;
  final c=Map<String,dynamic>.from(crops.first);c['cropCycleId']=c['cropCycleId']??'legacy_${c['id']??plotId}';return c;
}

String formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) return '$remaining min';
  if (remaining == 0) return '$hours hr';
  return '$hours hr $remaining min';
}

String formatSignedMinutes(int minutes) {
  final sign = minutes > 0 ? '+' : minutes < 0 ? '-' : '';
  return '$sign${formatMinutes(minutes.abs())}';
}

class AddPaniScreen extends StatefulWidget {
  const AddPaniScreen({this.initialPlotId, super.key});
  final String? initialPlotId;

  @override
  State<AddPaniScreen> createState() => _AddPaniScreenState();
}

class _AddPaniScreenState extends State<AddPaniScreen> {
  final _storage = StorageBackupService.instance;
  final _minutes = TextEditingController();
  final _ownMinutes = TextEditingController();
  final _borrowedMinutes = TextEditingController();
  final _borrowedNaharMinutes = TextEditingController();
  final _borrowedKuaMinutes = TextEditingController();
  String _borrowedSource = 'Nahar';
  final _note = TextEditingController();
  String? _contactId;
  Map<String, int> _selectedPlots = {};
  String _source = 'Tubewell';
  String _wellType = 'Solar';
  bool _borrowedWater = false;
  String _direction = 'Diya';
  String _season = 'Rabi';
  int _year = DateTime.now().year;
  DateTime _activityDate = DateTime.now();
  bool _saving = false;

  List<Map<String, dynamic>> get _contacts => _storage.records('contacts');

  @override
  void initState() {
    super.initState();
    if (widget.initialPlotId != null) {
      final plots = _storage.records('plots').where((p) => p['id'] == widget.initialPlotId);
      if (plots.isNotEmpty) {
        _selectedPlots[widget.initialPlotId!] = (plots.first['totalKyaris'] as num?)?.toInt() ?? 0;
      }
    }
    if (_contacts.isNotEmpty) _contactId = _contacts.first['id'] as String;
    _loadDefaultOwnDuration();
  }

  Future<void> _loadDefaultOwnDuration() async {
    final prefs = await SharedPreferences.getInstance();
    final start = (prefs.getInt('farm_water_turn_start_hour') ?? 12) * 60 +
        (prefs.getInt('farm_water_turn_start_minute') ?? 0);
    final end = (prefs.getInt('farm_water_turn_end_hour') ?? 13) * 60 +
        (prefs.getInt('farm_water_turn_end_minute') ?? 0);
    final duration = (end - start + 1440) % 1440;
    if (duration > 0 && _ownMinutes.text.trim().isEmpty) {
      _ownMinutes.text = duration.toString();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _minutes.dispose();
    _ownMinutes.dispose();
    _borrowedMinutes.dispose();
    _borrowedNaharMinutes.dispose();
    _borrowedKuaMinutes.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    try {
      final picked = await ContactPickerService.pickPhoneContact();
      if (picked == null) return;
      final phone = KhataSharingService.normalizePhone(picked['phone']!);
      final existing = _contacts.where((item) =>
        KhataSharingService.normalizePhone((item['phone'] ?? '').toString()) == phone).toList();
      if (existing.isNotEmpty) {
        setState(() => _contactId = existing.first['id'] as String);
      } else {
        final now = DateTime.now();
        final id = now.microsecondsSinceEpoch.toString();
        await _storage.addRecord('contacts', {
          'id': id, 'name': picked['name'], 'phone': picked['phone'],
          'date': now.toIso8601String(),
        });
        if (mounted) setState(() => _contactId = id);
      }
    } catch (error) {
      _error('Could not select phone contact: ' + error.toString());
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _activityDate,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 8),
    );
    if (picked != null && mounted) {
      setState(() => _activityDate = picked);
      await FutureDateReminderPrompt.check(
        context,
        date: picked,
        taskTitle: 'Khet mein pani dena',
        details: _note.text.trim(),
      );
    }
  }

  void _error(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _activeCropCycleId(String plotId, DateTime onDate) {
    final activityDay = DateUtils.dateOnly(onDate);
    final crops = _storage.records('khet').where((row) {
      if (row['type'] != 'FASAL' || row['plotId'] != plotId) {
        return false;
      }
      final sowingDate = DateTime.tryParse(
        (row['sowingDate'] ?? row['date'] ?? '').toString(),
      );
      if (sowingDate == null || DateUtils.dateOnly(sowingDate).isAfter(activityDay)) {
        return false;
      }
      final harvestDate = DateTime.tryParse((row['harvestDate'] ?? '').toString());
      final completed = row['harvested'] == true || row['cropCycleStatus'] == 'COMPLETED';
      if (completed && harvestDate == null) return false;
      return harvestDate == null ||
          !activityDay.isAfter(DateUtils.dateOnly(harvestDate));
    }).toList();
    crops.sort((a, b) {
      final aDate = DateTime.tryParse((a['sowingDate'] ?? a['date'] ?? '').toString()) ?? DateTime(0);
      final bDate = DateTime.tryParse((b['sowingDate'] ?? b['date'] ?? '').toString()) ?? DateTime(0);
      return bDate.compareTo(aDate);
    });
    if (crops.isEmpty) return null;
    final crop = crops.first;
    final cycleId = crop['cropCycleId']?.toString();
    // Older crop entries did not have a cycle ID. A stable fallback keeps
    // their history separate without rewriting the user's existing records.
    return cycleId != null && cycleId.isNotEmpty
        ? cycleId
        : 'legacy_${crop['id'] ?? plotId}';
  }

  Future<void> _save() async {
    if (_saving) return;
    final plotMode = widget.initialPlotId != null;
    final ownMinutes = int.tryParse(_ownMinutes.text.trim()) ?? 0;
    final borrowedMinutes = _borrowedSource == 'Nahar'
        ? (int.tryParse(_borrowedNaharMinutes.text.trim()) ?? 0)
        : _borrowedSource == 'Kua'
            ? (int.tryParse(_borrowedKuaMinutes.text.trim()) ?? 0)
            : (int.tryParse(_borrowedNaharMinutes.text.trim()) ?? 0) + (int.tryParse(_borrowedKuaMinutes.text.trim()) ?? 0);
    final minutes = plotMode
        ? ownMinutes + (_borrowedWater ? borrowedMinutes : 0)
        : (int.tryParse(_minutes.text.trim()) ?? 0);

    if (minutes <= 0) {
      _error('पानी के सही मिनट भरें');
      return;
    }
    if (!plotMode && _contactId == null) {
      _error('पहले व्यक्ति का संपर्क चुनें');
      return;
    }
    final selectedPlotEntries = _selectedPlots.entries.toList();
    var totalSelectedKyaris = 0;
    if (plotMode) {
      if (selectedPlotEntries.isEmpty) {
        _error('Kam se kam ek killa select karein');
        return;
      }
      for (final entry in selectedPlotEntries) {
        final matches = _storage.records('plots').where((plot) => plot['id'] == entry.key);
        if (matches.isEmpty) {
          _error('Selected killa nahi mila. Dobara select karein.');
          return;
        }
        final total = (matches.first['totalKyaris'] as num?)?.toInt() ?? 0;
        if (total <= 0 || entry.value <= 0 || entry.value > total) {
          _error('Har selected kille ki total kyari Map Edit mein set karein aur valid kyari count chunein.');
          return;
        }
        totalSelectedKyaris += entry.value;
      }
      if (_borrowedWater && borrowedMinutes <= 0) {
        _error('Extra pani ke minutes enter karein');
        return;
      }
      if (_borrowedWater && _contactId == null) {
        _error('Pani kis se liya, contact select karein');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final contact = _contactId == null
          ? null
          : _contacts.firstWhere((item) => item['id'] == _contactId);
      final entryDate = DateTime(
        _activityDate.year,
        _activityDate.month,
        _activityDate.day,
        now.hour,
        now.minute,
      );
      final batchId = now.microsecondsSinceEpoch.toString();
      final baseRecord = <String, dynamic>{
        'id': batchId,
        'batchId': batchId,
        'type': 'PANI',
        'contactId': _contactId,
        'contact': contact?['name'],
        'contactPhone': contact?['phone'],
        'direction': plotMode
            ? (_borrowedWater ? 'Apni baari + Liya' : 'Apni baari')
            : _direction,
        'minutes': minutes,
        'note': _note.text.trim(),
        'date': entryDate.toIso8601String(),
        'borrowedSource': plotMode ? (_borrowedWater ? _borrowedSource : null) : (_direction == 'Liya' ? _wellType : null),
        'borrowedNaharMinutes': plotMode && _borrowedWater ? (int.tryParse(_borrowedNaharMinutes.text.trim()) ?? 0) : (!plotMode && _direction == 'Liya' && _wellType.toLowerCase().contains('nahar') ? minutes : 0),
        'borrowedKuaMinutes': plotMode && _borrowedWater ? (int.tryParse(_borrowedKuaMinutes.text.trim()) ?? 0) : (!plotMode && _direction == 'Liya' && !_wellType.toLowerCase().contains('nahar') ? minutes : 0),
        'borrowedMinutes': plotMode ? 0 : (_direction == 'Liya' ? minutes : 0),
        'waterPaymentPending': plotMode ? _borrowedWater : _direction == 'Liya',
        'waterPaymentStatus': (plotMode ? _borrowedWater : _direction == 'Liya') ? 'PENDING' : null,
        'waterPaymentNote': '',
      };

      if (plotMode) {
        final allPlotIds = selectedPlotEntries.map((entry) => entry.key).toList();
        var allocatedOwnMinutes = 0;
        var allocatedBorrowedMinutes = 0;
        for (var index = 0; index < selectedPlotEntries.length; index++) {
          final entry = selectedPlotEntries[index];
          final plotMatches = _storage.records('plots').where((plot) => plot['id'] == entry.key).toList();
          final totalKyaris = (plotMatches.first['totalKyaris'] as num?)?.toInt() ?? 0;
          final isLast = index == selectedPlotEntries.length - 1;
          final plotOwnMinutes = isLast
              ? ownMinutes - allocatedOwnMinutes
              : (ownMinutes * entry.value ~/ totalSelectedKyaris);
          final plotBorrowedMinutes = _borrowedWater
              ? (isLast
                  ? borrowedMinutes - allocatedBorrowedMinutes
                  : (borrowedMinutes * entry.value ~/ totalSelectedKyaris))
              : 0;
          allocatedOwnMinutes += plotOwnMinutes;
          allocatedBorrowedMinutes += plotBorrowedMinutes;
          final plotRecord = Map<String, dynamic>.from(baseRecord)
            ..['id'] = '${batchId}_$index'
            ..['plotId'] = entry.key
            ..['plotIds'] = allPlotIds
            ..['selectedPlotCount'] = selectedPlotEntries.length
            ..['source'] = _source
            ..['ownMinutes'] = plotOwnMinutes
            ..['borrowedMinutes'] = plotBorrowedMinutes
            ..['borrowedWater'] = _borrowedWater
            ..['borrowedContact'] = (_borrowedWater && contact != null) ? contact['name'] : null
            ..['borrowedContactId'] = _borrowedWater ? _contactId : null
            ..['minutes'] = plotOwnMinutes + plotBorrowedMinutes
            ..['wetKyaris'] = entry.value
            ..['kyariCount'] = entry.value
            ..['totalKyarisSnapshot'] = totalKyaris
            ..['remainingKyaris'] = (totalKyaris - entry.value).clamp(0, totalKyaris)
            ..['fullKilla'] = entry.value == totalKyaris
            ..['season'] = _season
            ..['year'] = _year
            ..['cropCycleId'] = _activeCropCycleId(entry.key, entryDate);
          await _storage.addRecord('khet', plotRecord);
        }
      } else {
        baseRecord.addAll({
          'ledgerMode': 'PERSON',
          'wellType': _wellType,
        });
        await _storage.addRecord('khet', baseRecord);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _error('Could not save Pani hisab: ' + error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts;
    final selected = contacts.where((item) => item['id'] == _contactId).toList();
    final naharPreview = int.tryParse(_borrowedNaharMinutes.text.trim()) ?? 0;
    final kuaPreview = int.tryParse(_borrowedKuaMinutes.text.trim()) ?? 0;
    final _previewBorrowedMinutes = _borrowedSource == 'Nahar' ? naharPreview : _borrowedSource == 'Kua' ? kuaPreview : naharPreview + kuaPreview;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Pani Hisab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.initialPlotId == null || _borrowedWater) ...[
          OutlinedButton.icon(
            onPressed: _pickContact,
            icon: const Icon(Icons.contacts_outlined),
            label: Text(selected.isEmpty ? 'Pick from Phone Contacts' : selected.first['name'].toString() + ' · ' + (selected.first['phone'] ?? '').toString()),
          ),
          const SizedBox(height: 12),
          if (contacts.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _contactId,
              decoration: const InputDecoration(labelText: 'Saved contact'),
              items: contacts.map((item) => DropdownMenuItem(
                value: item['id'] as String,
                child: Text(item['name'].toString() + (item['phone'] == null ? '' : ' · ' + item['phone'].toString())),
              )).toList(),
              onChanged: (value) => setState(() => _contactId = value),
            ),
          const SizedBox(height: 12),
          ],
          if (widget.initialPlotId != null) ...[
            KhetMultiPlotSelector(
              initialSelection: _selectedPlots,
              onChanged: (value) => setState(() {
                _selectedPlots = value;
              }),
            ),
            const SizedBox(height: 8),
            const Text('Har kille mein Full Killa ya Partial kyari alag select karein. Pani ke total minutes kyari ke anupat mein bantenge.',
                style: TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 12),
            SeasonYearFields(
              season: _season,
              year: _year,
              onSeasonChanged: (value) => setState(() => _season = value),
              onYearChanged: (value) => setState(() => _year = value),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('Paani date: ' + DateFormat('dd MMM yyyy').format(_activityDate)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _source,
              decoration: const InputDecoration(labelText: 'Pani Source'),
              items: ['Tubewell', 'Nahar', 'Mix'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: (value) => setState(() => _source = value ?? _source),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              initialValue: _borrowedWater,
              decoration: const InputDecoration(labelText: 'Pani ki baari'),
              items: const [
                DropdownMenuItem(value: false, child: Text('Apni baari ka pani')),
                DropdownMenuItem(value: true, child: Text('Apni baari + kisi se extra pani')),
              ],
              onChanged: (value) => setState(() { _borrowedWater = value ?? false; if (!_borrowedWater) _contactId = null; }),
            ),
            const SizedBox(height: 12),
            TextField(controller: _ownMinutes, keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Apni baari ke minutes (optional)')),
            if (_borrowedWater) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _borrowedSource,
                decoration: const InputDecoration(labelText: 'Extra pani kahan se liya?'),
                items: const [
                  DropdownMenuItem(value: 'Nahar', child: Text('Nahar')),
                  DropdownMenuItem(value: 'Kua', child: Text('Kua')),
                  DropdownMenuItem(value: 'Mix', child: Text('Nahar + Kua (Mix)')),
                ],
                onChanged: (value) => setState(() => _borrowedSource = value ?? _borrowedSource),
              ),
              if (_borrowedSource == 'Nahar' || _borrowedSource == 'Mix')
                TextField(controller: _borrowedNaharMinutes, keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Nahar se liye minutes (required)')),
              if (_borrowedSource == 'Kua' || _borrowedSource == 'Mix')
                TextField(controller: _borrowedKuaMinutes, keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Kua se liye minutes (required)')),
            ],
            const SizedBox(height: 8),
            Text('Total: ' + formatMinutes((int.tryParse(_ownMinutes.text.trim()) ?? 0) + (_borrowedWater ? _previewBorrowedMinutes : 0))),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _wellType,
              decoration: const InputDecoration(labelText: 'किस कुएँ से पानी दिया/लिया?'),
              items: const [
                DropdownMenuItem(value: 'Solar', child: Text('☀️ सोलर कुआँ')),
                DropdownMenuItem(value: 'Diesel', child: Text('⛽ डीजल कुआँ')),
              ],
              onChanged: (value) => setState(() => _wellType = value ?? _wellType),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _direction,
              decoration: const InputDecoration(labelText: 'व्यक्ति के साथ पानी का हिसाब'),
              items: const [
                DropdownMenuItem(value: 'Diya', child: Text('व्यक्ति को पानी दिया (+)')),
                DropdownMenuItem(value: 'Liya', child: Text('व्यक्ति से पानी लिया (−)')),
              ],
              onChanged: (value) => setState(() => _direction = value ?? _direction),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'कितने मिनट पानी दिया/लिया?',
                helperText: 'समय: ' + formatMinutes(int.tryParse(_minutes.text) ?? 0),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('पानी की तारीख: ' + DateFormat('dd MMM yyyy').format(_activityDate)),
            ),
          ],
          VoiceDictationField(
            controller: _note,
            label: 'Note (jaise: shaam ko uski baari ke baad)',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save Pani Hisab'),
          ),
        ],
      ),
    );
  }
}

class AddKhetItemScreen extends StatefulWidget {
  const AddKhetItemScreen({
    required this.type,
    this.initialPlotId,
    this.initialSeason,
    this.initialYear,
    super.key,
  });
  final String type;
  final String? initialPlotId;
  final String? initialSeason;
  final int? initialYear;

  @override
  State<AddKhetItemScreen> createState() => _AddKhetItemScreenState();
}

class _AddKhetItemScreenState extends State<AddKhetItemScreen> {
  final _storage = StorageBackupService.instance;
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  final _kyariNumber = TextEditingController();
  final List<String> _itemPhotos = [];
  final List<String> _billPhotos = [];
  String? _plotId;
  Map<String, int> _selectedPlots = {};
  String _season = 'Rabi';
  int _year = DateTime.now().year;
  String _purpose = 'Herbicide (ghas khatam karne wali)';
  String _fertilizerKind = 'DAP';
  bool _khalaOnly = false;
  final _areaController = TextEditingController();
  DateTime _activityDate = DateTime.now();
  DateTime? _harvestDate;
  bool _harvested = false;
  bool _reminderEnabled = false;
  DateTime? _reminderAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _plotId = widget.initialPlotId;
    if (widget.initialSeason != null) _season = widget.initialSeason!;
    if (widget.initialYear != null) _year = widget.initialYear!;
    if (widget.initialPlotId != null) {
      final plots = _storage.records('plots').where((p) => p['id'] == widget.initialPlotId);
      if (plots.isNotEmpty) {
        _selectedPlots[widget.initialPlotId!] = (plots.first['totalKyaris'] as num?)?.toInt() ?? 0;
      }
    }
  }

  bool get _needsFarmDetails => ['FASAL', 'HARA_BEEJ', 'KHAD'].contains(widget.type);
  String get _dateLabel => widget.type == 'FASAL' || widget.type == 'HARA_BEEJ'
      ? 'Beejne ki date' : widget.type == 'KHAD' ? 'Khaad dalne ki date' : 'Dawai dalne ki date';

  Map<String, dynamic>? _currentCropFor(String? plotId) {
    if (plotId == null) return null;
    final applicationDay = DateUtils.dateOnly(_activityDate);
    DateTime? sowingDate(Map<String, dynamic> row) =>
        DateTime.tryParse((row['sowingDate'] ?? row['date'] ?? '').toString());

    final crops = _storage.records('khet').where((row) {
      if (row['type'] != 'FASAL' || row['plotId'] != plotId) {
        return false;
      }
      final sowing = sowingDate(row);
      if (sowing == null || DateUtils.dateOnly(sowing).isAfter(applicationDay)) {
        return false;
      }
      final harvest = DateTime.tryParse((row['harvestDate'] ?? '').toString());
      final completed = row['harvested'] == true || row['cropCycleStatus'] == 'COMPLETED';
      if (completed && harvest == null) return false;
      return harvest == null ||
          !applicationDay.isAfter(DateUtils.dateOnly(harvest));
    }).toList()
      ..sort((a, b) => (sowingDate(b) ?? DateTime(0))
          .compareTo(sowingDate(a) ?? DateTime(0)));
    if (crops.isEmpty) return null;
    final crop = Map<String, dynamic>.from(crops.first);
    final id = crop['cropCycleId']?.toString();
    crop['cropCycleId'] = id != null && id.isNotEmpty
        ? id
        : 'legacy_${crop['id'] ?? plotId}';
    return crop;
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _note.dispose();
    _kyariNumber.dispose();
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _pickHarvestDate() async {
    final now = DateTime.now();
    final initial = _harvestDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 8),
    );
    if (picked != null && mounted) {
      final futureHarvest = DateUtils.dateOnly(picked).isAfter(
        DateUtils.dateOnly(now),
      );
      setState(() {
        _harvestDate = picked;
        _harvested = !futureHarvest;
      });
      await FutureDateReminderPrompt.check(
        context,
        date: picked,
        taskTitle: 'Fasal katni - ${_title.text.trim()}',
      );
    }
  }

  Future<void> _pickActivityDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _activityDate,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 8),
    );
    if (picked != null && mounted) {
      setState(() => _activityDate = picked);
      await FutureDateReminderPrompt.check(
        context,
        date: picked,
        taskTitle: '${_dateLabel} - ${_title.text.trim()}',
        details: _note.text.trim(),
      );
    }
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final initial = _reminderAt ?? now.add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 8),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderAt ?? now.add(const Duration(days: 7))),
    );
    if (time == null || !mounted) return;
    setState(() => _reminderAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickPhotos(bool bill, ImageSource source) async {
    try {
      final images = source == ImageSource.gallery
          ? await _picker.pickMultiImage(imageQuality: 88)
          : [if (await _picker.pickImage(source: source, imageQuality: 88) case final image?) image];
      final target = bill ? _billPhotos : _itemPhotos;
      for (final image in images) {
        final path = await _storage.keepFile(image.path, folder: 'KhetPhotos');
        if (!target.contains(path)) target.add(path);
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not save photos: ' + error.toString());
    }
  }

  Future<void> _pickBillFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
      for (final item in result?.files ?? const []) {
        final path = item.path;
        if (path != null) {
          final saved = await _storage.keepFile(path, folder: 'KhetPhotos');
          if (!_billPhotos.contains(saved)) _billPhotos.add(saved);
        }
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not save bill images: ' + error.toString());
    }
  }

  void _error(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    final price = widget.type == 'DAWAI' ? 0.0 : (double.tryParse(_price.text.trim()) ?? 0);
    if (_saving) return;
    if (title.isEmpty) {
      _error(widget.type == 'FASAL' ? 'Fasal ka naam likhein' : widget.type == 'DAWAI' ? 'Dawai ka naam likhein' : widget.type == 'KHAD' ? 'Khaad ka naam likhein' : 'Naam likhein');
      return;
    }
    if (widget.type == 'DAWAI' && !_khalaOnly && _plotId == null) {\n      _error('Killa select karein');\n      return;\n    }\n    if (_needsFarmDetails && _selectedPlots.isEmpty) {
      _error('Kam se kam ek killa select karein');
      return;
    }
    var totalSelectedKyaris = 0;
    var hasPartialKyariSelection = false;
    if (_needsFarmDetails) {
      for (final entry in _selectedPlots.entries) {
        final matches = _storage.records('plots').where((plot) => plot['id'] == entry.key);
        if (matches.isEmpty) {
          _error('Selected killa nahi mila. Dobara select karein.');
          return;
        }
        final total = (matches.first['totalKyaris'] as num?)?.toInt() ?? 0;
        if (total <= 0 || entry.value <= 0 || entry.value > total) {
          _error('Har selected kille ki total kyari Map Edit mein set karein aur valid kyari count chunein.');
          return;
        }
        totalSelectedKyaris += entry.value;
        if (entry.value < total) hasPartialKyariSelection = true;
      }
    }
    if (widget.type == 'HARA_BEEJ' && hasPartialKyariSelection && _kyariNumber.text.trim().isEmpty) {
      _error('Partial killa ke liye kyari number/name likhein');
      return;
    }
    if (widget.type == 'DAWAI' && !_khalaOnly && _reminderEnabled && _reminderAt == null) {
      _error('Reminder ke liye date aur time set karein');
      return;
    }
    if (widget.type == 'DAWAI' && !_khalaOnly && _reminderEnabled && !_reminderAt!.isAfter(DateTime.now())) {
      _error('Reminder future date/time par set karein');
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final activityDate = DateTime(
      _activityDate.year, _activityDate.month, _activityDate.day, now.hour, now.minute);
    final batchId = now.microsecondsSinceEpoch.toString();
    final reminderId = int.parse(batchId) % 2000000000;
    final plotEntries = _needsFarmDetails ? _selectedPlots.entries.toList() : <MapEntry<String, int>>[];
    final count = _needsFarmDetails ? plotEntries.length : 1;
    var allocatedPrice = 0.0;
    String? reminderError;

    try {
      for (var index = 0; index < count; index++) {
        final plotEntry = _needsFarmDetails ? plotEntries[index] : null;
        final plotId = plotEntry?.key ?? _plotId;
        final kyariCount = plotEntry?.value ?? 0;
        final plotMatches = plotId == null
            ? <Map<String, dynamic>>[]
            : _storage.records('plots').where((plot) => plot['id'] == plotId).toList();
        final totalKyaris = plotMatches.isEmpty
            ? 0
            : (plotMatches.first['totalKyaris'] as num?)?.toInt() ?? 0;
        final currentCrop = widget.type == 'DAWAI' || widget.type == 'KHAD' ? _currentCropFor(plotId) : null;
        final plotPrice = _needsFarmDetails
            ? (index == count - 1
                ? price - allocatedPrice
                : price * kyariCount / totalSelectedKyaris)
            : price;
        allocatedPrice += plotPrice;
        final record = <String, dynamic>{
          'id': '${batchId}_$index',
          'batchId': batchId,
          'selectedPlotCount': _needsFarmDetails ? plotEntries.length : 0,
          'type': widget.type,
          'plotId': plotId,
          'title': title,
          'price': plotPrice,
          'note': _note.text.trim(),
          'itemPhoto': _itemPhotos.isEmpty ? null : _itemPhotos.first,
          'itemPhotos': _itemPhotos,
          'billPhoto': _billPhotos.isEmpty ? null : _billPhotos.first,
          'billPhotos': _billPhotos,
          'date': activityDate.toIso8601String(),
        };

        if (_needsFarmDetails) {
          record.addAll({
            'season': _season,
            'year': _year,
            'activityDate': activityDate.toIso8601String(),
            'kyariCount': kyariCount,
            'totalKyarisSnapshot': totalKyaris,
            'fullKilla': kyariCount == totalKyaris,
          });
        }
        if (widget.type == 'KHAD') {
          if (currentCrop != null) record['cropCycleId'] = currentCrop['cropCycleId'];
          record['purpose'] = _fertilizerKind;
          record['fertilizerType'] = _fertilizerKind;
          record['cropAtUse'] = currentCrop == null ? 'Fasal record nahi hai' : (currentCrop['cropName'] ?? currentCrop['title'] ?? 'Fasal').toString();
          record['applicationDate'] = activityDate.toIso8601String();
        }
        if (widget.type == 'FASAL') {
          final cycleId = 'cycle_${plotId ?? 'unknown'}_${batchId}_$index';
          record['cropName'] = title;
          record['cropCycleId'] = cycleId;
          record['cropCycleStatus'] = _harvested ? 'COMPLETED' : 'ACTIVE';
          record['sowingDate'] = activityDate.toIso8601String();
          record['harvested'] = _harvested;
          record['harvestDate'] = _harvested ? (_harvestDate ?? DateTime.now()).toIso8601String() : null;
          record['plannedHarvestDate'] = !_harvested && _harvestDate != null ? _harvestDate!.toIso8601String() : null;
        }
        if (widget.type == 'HARA_BEEJ') {
          record['seedName'] = title;
          record['kyariNumber'] = _kyariNumber.text.trim();
          record['sowingDate'] = activityDate.toIso8601String();
        }
        if (widget.type == 'DAWAI') {
          if (currentCrop != null) record['cropCycleId'] = currentCrop['cropCycleId'];
          record['purpose'] = _purpose;
          record['applicationArea'] = _khalaOnly ? (_areaController.text.trim().isEmpty ? 'Khala / kacha nala' : _areaController.text.trim()) : 'Khet';
          record['cropAtUse'] = currentCrop == null
              ? 'Fasal record nahi hai'
              : (currentCrop['cropName'] ?? currentCrop['title'] ?? 'Fasal').toString();
          record['applicationDate'] = activityDate.toIso8601String();
          record['reminderDate'] = _reminderEnabled ? _reminderAt?.toIso8601String() : null;
          record['reminderId'] = _reminderEnabled ? reminderId : null;
        }
        await _storage.addRecord('khet', record);
      }

      if (widget.type == 'DAWAI' && !_khalaOnly && _reminderEnabled && _reminderAt != null) {
        try {
          final killaNames = plotEntries.map((entry) {
            final plot = _storage.records('plots').firstWhere((p) => p['id'] == entry.key);
            return plotLabel(plot);
          }).join(', ');
          await FarmReminderService.schedule(
            id: reminderId,
            scheduledAt: _reminderAt!,
            title: 'KHATA: $title',
            body: 'Dawai dalni hai · $_purpose · Kille: $killaNames',
          );
        } catch (error) {
          reminderError = error.toString();
        }
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        if (reminderError != null) {
          messenger.showSnackBar(SnackBar(content: Text('Entry save ho gayi, reminder nahi laga: $reminderError')));
        }
      }
    } catch (error) {
      _error('Could not save Khet entry: ' + error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _photoButtons(String label, bool bill) {
    final paths = bill ? _billPhotos : _itemPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: () => _pickPhotos(bill, ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera')),
          TextButton.icon(onPressed: bill ? _pickBillFiles : () => _pickPhotos(bill, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined), label: const Text('Add multiple photos')),
        ]),
        if (paths.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: paths.map((path) => Stack(
            alignment: Alignment.topRight,
            children: [
              mediaThumbnail(path, size: 76),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => paths.remove(path)),
                icon: const Icon(Icons.cancel, color: Colors.red),
              ),
            ],
          )).toList()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final farmPlot = _needsFarmDetails;
    final titleLabel = widget.type == 'FASAL' ? 'Fasal ka naam'
      : widget.type == 'HARA_BEEJ' ? 'Hara beej / chara ka naam'
      : widget.type == 'DAWAI' ? 'Dawai ka naam' : widget.type == 'KHAD' ? 'Khaad ka naam' : 'Title / Name';
    return Scaffold(
      appBar: AppBar(title: Text('Add ' + widget.type.replaceAll('_', ' '))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: titleLabel),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          if (farmPlot)
            KhetMultiPlotSelector(
              initialSelection: _selectedPlots,
              onChanged: (value) => setState(() {
                _selectedPlots = value;
                _plotId = value.isEmpty ? null : value.keys.first;
              }),
            )
          else if (!(widget.type == 'DAWAI' && _khalaOnly))
            KhetPlotDropdown(selectedId: _plotId, onChanged: (value) => setState(() => _plotId = value)),

          if (farmPlot) ...[
            const SizedBox(height: 8),
            if (widget.type == 'DAWAI')
              Card(
                child: ListTile(
                  leading: const Icon(Icons.grass_outlined),
                  title: const Text('Is kille mein abhi kaunsi fasal hai?'),
                  subtitle: Text(
                    _selectedPlots.keys.map((id) {
                      final plot = _storage.records('plots').firstWhere((p) => p['id'] == id);
                      final crop = _currentCropFor(id);
                      final cropName = crop == null ? 'Fasal record nahi hai' :
                          (crop['cropName'] ?? crop['title'] ?? 'Fasal').toString();
                      return '${plotLabel(plot)}: $cropName';
                    }).join('\\n'),
                  ),
                ),
              ),
            if (widget.type == 'HARA_BEEJ') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _kyariNumber,
                decoration: const InputDecoration(labelText: 'Kaunsi kyari? (number / naam)'),
              ),
            ],
            if (widget.type == 'DAWAI') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _purpose,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Dawai ka kaam'),
                items: const [
                  DropdownMenuItem(value: 'Herbicide (ghas khatam karne wali)', child: Text('Ghas khatam karne wali')),
                  DropdownMenuItem(value: 'Insecticide (keede ki dawa)', child: Text('Keede ki dawa')),
                  DropdownMenuItem(value: 'Fungicide (fungus ki dawa)', child: Text('Fungus ki dawa')),
                  DropdownMenuItem(value: 'Other spray', child: Text('Other spray')),
                ],
                onChanged: (value) => setState(() => _purpose = value ?? _purpose),
              ),
            ],
            if (widget.type == 'KHAD') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _fertilizerKind,
                decoration: const InputDecoration(labelText: 'Khaad ka type'),
                items: const [
                  DropdownMenuItem(value: 'DAP', child: Text('DAP')),
                  DropdownMenuItem(value: 'Urea', child: Text('Urea')),
                  DropdownMenuItem(value: 'Potash', child: Text('Potash')),
                  DropdownMenuItem(value: 'Other fertilizer', child: Text('Other khaad')),
                ],
                onChanged: (value) => setState(() => _fertilizerKind = value ?? _fertilizerKind),
              ),
            ],
            const SizedBox(height: 12),
            SeasonYearFields(
              season: _season,
              year: _year,
              onSeasonChanged: (value) => setState(() => _season = value),
              onYearChanged: (value) => setState(() => _year = value),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickActivityDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(_dateLabel + ': ' + DateFormat('dd MMM yyyy').format(_activityDate)),
            ),
            if (widget.type == 'FASAL') ...[
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fasal kat gayi hai'),
                subtitle: const Text('Katayi ke baad record history mein rahega, agali fasal add kar sakenge'),
                value: _harvested,
                onChanged: (value) => setState(() {
                  _harvested = value;
                  if (!value) _harvestDate = null;
                  else _harvestDate ??= DateTime.now();
                }),
              ),
              OutlinedButton.icon(
                onPressed: _pickHarvestDate,
                icon: const Icon(Icons.event_available_outlined),
                label: Text(
                  _harvestDate == null
                      ? 'Fasal katne ki date / planned date chunein'
                      : (_harvested ? 'Fasal katne ki date: ' : 'Planned fasal katne ki date: ') +
                          DateFormat('dd MMM yyyy').format(_harvestDate!),
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: widget.type == 'DAWAI' ? 'Dawai ka kharcha (₹)' : widget.type == 'KHAD' ? 'Khaad ka kharcha (₹)' : 'Price / kharcha (₹)',
            ),
          ),
          if (widget.type == 'DAWAI' && false) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Is dawai ke liye future reminder lagayein'),
              value: _reminderEnabled,
              onChanged: (value) => setState(() {
                _reminderEnabled = value;
                if (!value) _reminderAt = null;
              }),
            ),
            if (_reminderEnabled)
              OutlinedButton.icon(
                onPressed: _pickReminder,
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(_reminderAt == null
                  ? 'Reminder date aur time chunein'
                  : 'Reminder: ' + DateFormat('dd MMM yyyy, hh:mm a').format(_reminderAt!)),
              ),
          ],
          const SizedBox(height: 12),
          VoiceDictationField(
            controller: _note,
            label: 'Note',
          ),
          const SizedBox(height: 18),
          _photoButtons('Item Photos', false),
          const SizedBox(height: 12),
          _photoButtons('Bill Photos', true),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save ' + widget.type.replaceAll('_', ' ')),
          ),
        ],
      ),
    );
  }
}

class AddKuaHisabScreen extends StatefulWidget {
  const AddKuaHisabScreen({super.key});
  @override
  State<AddKuaHisabScreen> createState() => _AddKuaHisabScreenState();
}

class _AddKuaHisabScreenState extends State<AddKuaHisabScreen> {
  final _storage = StorageBackupService.instance;
  final _oneMinutes = TextEditingController();
  final _solar = TextEditingController();
  final _diesel = TextEditingController();
  final _exchange = TextEditingController(text: '0');
  final _cash = TextEditingController(text: '0');
  final _paid = TextEditingController(text: '0');
  final _note = TextEditingController();
  String _person = '';
  final _manualPerson = TextEditingController();
  List<String> _savedPeople = [];
  // Kua Hisab records only the water we gave from our own well.
  static const String _direction = 'Dusre ne hamara kua chalaya';
  String _well = 'Solar';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_oneMinutes, _solar, _diesel, _exchange, _cash, _paid, _note, _manualPerson]) { c.dispose(); }
    super.dispose();
  }


  Future<void> _loadPeople() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _savedPeople = prefs.getStringList('kua_saved_people') ?? []);
  }

  Future<void> _addSavedPerson({String? name}) async {
    final controller = TextEditingController(text: name ?? '');
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Kua chalane wale ka naam add karein'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Naam')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () { final n=controller.text.trim(); if(n.isNotEmpty) Navigator.pop(ctx,n); }, child: const Text('Add')),
      ],
    ));
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('kua_saved_people') ?? [];
    if (!list.any((n) => n.toLowerCase() == value.trim().toLowerCase())) list.add(value.trim());
    await prefs.setStringList('kua_saved_people', list);
    if (mounted) setState(() { _savedPeople=list; _person=value.trim(); _manualPerson.clear(); });
  }

  Future<void> _pickPerson() async {
    try {
      final p = await ContactPickerService.pickPhoneContact();
      if (p != null && mounted) await _addSavedPerson(name: (p['name'] ?? '').toString());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Contact select nahi hua: $e')));
    }
  }

  Map<String, int> get _minutes {
    if (_well == 'Solar') return {'Solar': int.tryParse(_oneMinutes.text) ?? 0};
    if (_well == 'Diesel') return {'Diesel': int.tryParse(_oneMinutes.text) ?? 0};
    if (_well == 'Both same') {
      final m = int.tryParse(_oneMinutes.text) ?? 0;
      return {'Solar': m, 'Diesel': m};
    }
    return {'Solar': int.tryParse(_solar.text) ?? 0, 'Diesel': int.tryParse(_diesel.text) ?? 0};
  }

  Future<void> _save() async {
    if (_saving) return;
    final mins = _minutes;
    if (mins.values.any((m) => m <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kua ke minutes sahi bharein')));
      return;
    }
    final cash = double.tryParse(_cash.text) ?? 0;
    final paid = double.tryParse(_paid.text) ?? 0;
    if (cash < 0 || paid < 0 || paid > cash) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cash aur paid amount sahi bharein')));
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await _storage.addRecord('khet', {
        'id': now.microsecondsSinceEpoch.toString(),
        'type': 'KUA',
        'contact': _manualPerson.text.trim().isNotEmpty ? _manualPerson.text.trim() : (_person.trim().isEmpty ? 'Samne wala' : _person.trim()),
        'direction': _direction,
        'wellSelection': _well,
        'wellMinutes': mins,
        'exchangeMinutes': int.tryParse(_exchange.text) ?? 0,
        'cashAmount': cash,
        'cashPaid': paid,
        'cashBalance': cash - paid,
        'note': _note.text.trim(),
        'date': now.toIso8601String(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() { super.initState(); _loadPeople(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kua Hisab')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          value: _savedPeople.contains(_person) ? _person : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Kua chalane wala (saved list)'),
          hint: const Text('Vyakti select karein'),
          items: _savedPeople.map((name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() { _person = v ?? ''; _manualPerson.clear(); }),
        )),
        IconButton(tooltip: 'Contact se add', onPressed: _pickPerson, icon: const Icon(Icons.contacts_outlined)),
        IconButton(tooltip: 'Naam manually add', onPressed: () => _addSavedPerson(), icon: const Icon(Icons.person_add_alt_1)),
      ]),
      const SizedBox(height: 8),
      TextField(controller: _manualPerson, decoration: const InputDecoration(labelText: 'Ya naam manually likhein (optional)'), onChanged: (_) => setState(() => _person = '')),
      const SizedBox(height: 12),
      Card(
        color: const Color(0xFFE8F5EF),
        child: const ListTile(
          dense: true,
          leading: Icon(Icons.water_drop_outlined, color: Color(0xFF176B52)),
          title: Text('Humne apne kuye se pani diya'),
          subtitle: Text('Yeh entry sirf tab hogi jab doosre vyakti ne hamara kua chalaya ho.'),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _well,
        decoration: const InputDecoration(labelText: 'Kaunsa kua?'),
        items: const [
          DropdownMenuItem(value: 'Solar', child: Text('☀️ Solar wala')),
          DropdownMenuItem(value: 'Diesel', child: Text('⛽ Diesel wala')),
          DropdownMenuItem(value: 'Both same', child: Text('🔄 Dono — barabar minutes')),
          DropdownMenuItem(value: 'Both different', child: Text('🔄 Dono — alag minutes')),
        ],
        onChanged: (v) => setState(() => _well = v ?? _well),
      ),
      const SizedBox(height: 12),
      if (_well == 'Both different') ...[
        TextField(controller: _solar, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Solar minutes')),
        const SizedBox(height: 8),
        TextField(controller: _diesel, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Diesel minutes')),
      ] else
        TextField(controller: _oneMinutes, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _well == 'Both same' ? 'Dono ke minutes (ek baar)' : 'Minutes')),
      const SizedBox(height: 12),
      TextField(controller: _exchange, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Badle mein pani ke minutes (optional)')),
      const SizedBox(height: 12),
      TextField(controller: _cash, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Cash/rent ka total (₹)')),
      const SizedBox(height: 12),
      TextField(controller: _paid, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Cash payment (₹)')),
      const SizedBox(height: 12),
      TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
      const SizedBox(height: 20),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save Kua Hisab')),
    ]),
  );
}

class AddTractorWorkScreen extends StatefulWidget {
  const AddTractorWorkScreen({super.key});

  @override
  State<AddTractorWorkScreen> createState() => _AddTractorWorkScreenState();
}

class _AddTractorWorkScreenState extends State<AddTractorWorkScreen> {
  final _storage = StorageBackupService.instance;
  final _work = TextEditingController();
  final _total = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _note = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _photos = <String>[];
  String? _customerName;
  String? _customerPhone;
  String? _plotId;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void dispose() {
    _work.dispose();
    _total.dispose();
    _paid.dispose();
    _note.dispose();
    _ownerNameController.dispose();
    super.dispose();
  }

  void _error(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickCustomer() async {
    try {
      final picked = await ContactPickerService.pickPhoneContact();
      if (picked != null && mounted) {
        setState(() {
          _customerName = picked['name'];
          _ownerNameController.text = picked['name'] ?? '';
          _customerPhone = picked['phone'];
        });
      }
    } catch (error) {
      _error('Could not pick customer: $error');
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final images = await _picker.pickMultiImage(imageQuality: 88);
      for (final image in images) {
        _photos.add(await _storage.keepFile(image.path, folder: 'KhetPhotos'));
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not add bill photos: $error');
    }
  }

  final ImagePicker _picker = ImagePicker();

  Future<void> _selectDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
      await FutureDateReminderPrompt.check(
        context,
        date: picked,
        taskTitle: 'Tractor payment follow-up',
        details: 'Tractor payment due date',
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final total = double.tryParse(_total.text.trim()) ?? 0;
    final paid = double.tryParse(_paid.text.trim()) ?? 0;
    _customerName = _ownerNameController.text.trim();
    if ((_customerName ?? '').isEmpty) {
      _error('Tractor malik ka naam likhein ya contact se select karein');
      return;
    }
    if (_work.text.trim().isEmpty || total <= 0 || paid < 0 || paid > total) {
      _error('Enter work and valid total/paid amount');
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final balance = total - paid;
      await _storage.addRecord('khet', {
        'id': now.microsecondsSinceEpoch.toString(),
        'type': 'TRACTOR',
        'customerName': _customerName,
        'ownerName': _customerName,
        'customerPhone': (_customerPhone ?? '').trim().isEmpty ? null : _customerPhone,
        'plotId': _plotId,
        'contact': _customerName,
        'work': _work.text.trim(),
        'title': _work.text.trim(),
        'totalAmount': total,
        'price': total.toString(),
        'paidAmount': paid,
        'balance': balance,
        'status': balance <= 0 ? 'PAID' : (paid > 0 ? 'PARTIAL' : 'PENDING'),
        'dueDate': _dueDate?.toIso8601String(),
        'itemPhoto': _photos.isEmpty ? null : _photos.first,
        'itemPhotos': _photos,
        'billPhoto': _photos.isEmpty ? null : _photos.first,
        'billPhotos': _photos,
        'note': _note.text.trim(),
        'payments': paid > 0 ? [{'amount': paid, 'direction': 'Diya', 'date': now.toIso8601String()}] : <Map<String, dynamic>>[],
        'date': now.toIso8601String(),
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _error('Could not save tractor work: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add Tractor Work')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _ownerNameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Tractor malik ka naam',
            hintText: 'Naam manually likhein',
            prefixIcon: Icon(Icons.person_outline),
          ),
          onChanged: (value) => _customerName = value.trim(),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickCustomer,
          icon: const Icon(Icons.contacts_outlined),
          label: Text(_customerPhone == null || _customerPhone!.isEmpty
              ? 'Contact se Tractor Malik select karein'
              : 'Contact: $_customerName · $_customerPhone'),
        ),
        const SizedBox(height: 12),
        KhetPlotDropdown(selectedId: _plotId, onChanged: (value) => setState(() => _plotId = value)),
        const SizedBox(height: 12),
        TextField(controller: _work, textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Work done (ploughing, rotavator, sowing...)')),
        const SizedBox(height: 12),
        TextField(controller: _total, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Total bill amount (₹)')),
        const SizedBox(height: 12),
        TextField(controller: _paid, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Already paid (₹)')),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _selectDueDate,
          icon: const Icon(Icons.event),
          label: Text(_dueDate == null ? 'Set payment due date (optional)' : 'Due: ${DateFormat('dd MMM yyyy').format(_dueDate!)}'),
        ),
        const SizedBox(height: 12),
        VoiceDictationField(
          controller: _note,
          label: 'Note (optional)',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _pickPhotos, icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Add bill / work photos')),
        if (_photos.isNotEmpty)
          Wrap(spacing: 6, children: _photos.map((path) => mediaThumbnail(path, size: 68)).toList()),
        const SizedBox(height: 22),
        FilledButton(onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save Tractor Work')),
      ],
    ),
  );
}
class KhetPurchaseScreen extends StatefulWidget {
  const KhetPurchaseScreen({super.key});
  @override
  State<KhetPurchaseScreen> createState() => _KhetPurchaseScreenState();
}

class _KhetPurchaseScreenState extends State<KhetPurchaseScreen> {
  final _storage = StorageBackupService.instance;
  final _picker = ImagePicker();
  final _item = TextEditingController();
  final _qty = TextEditingController();
  final _total = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _note = TextEditingController();
  String? _vendorId;
  String _category = 'Dawai';
  String _unit = 'Packet';
  DateTime _billDate = DateTime.now();
  DateTime? _due;
  String? _billPhoto, _itemPhoto;
  bool _saving = false;

  List<Map<String, dynamic>> get contacts => _storage.records('contacts');
  @override
  void dispose() {
    for (final c in [_item, _qty, _total, _paid, _note]) { c.dispose(); }
    super.dispose();
  }
  void _error(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }
  Future<void> _pickVendor() async {
    try {
      final picked = await ContactPickerService.pickPhoneContact();
      if (picked == null) return;
      final phone = KhataSharingService.normalizePhone((picked['phone'] ?? '').toString());
      final existing = contacts.where((c) =>
        KhataSharingService.normalizePhone((c['phone'] ?? '').toString()) == phone).toList();
      if (existing.isNotEmpty) {
        setState(() => _vendorId = existing.first['id'].toString());
        return;
      }
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await _storage.addRecord('contacts', {
        'id': id, 'name': picked['name'], 'phone': picked['phone'],
        'date': DateTime.now().toIso8601String(), 'contactType': 'FARM_VENDOR'
      });
      if (mounted) setState(() => _vendorId = id);
    } catch (e) { _error('Contact select nahi hua: $e'); }
  }
  Future<void> _manualVendor() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dukaan wale ka naam'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Naam')),
          TextField(controller: phone, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone optional')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, {
            'name': name.text.trim(), 'phone': phone.text.trim()
          }), child: const Text('Save')),
        ],
      ),
    );
    name.dispose(); phone.dispose();
    if (result == null || (result['name'] ?? '').isEmpty) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await _storage.addRecord('contacts', {
      'id': id, 'name': result['name'], 'phone': result['phone'],
      'date': DateTime.now().toIso8601String(), 'contactType': 'FARM_VENDOR'
    });
    if (mounted) setState(() => _vendorId = id);
  }
  Future<void> _date(bool due) async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context,
      initialDate: due ? (_due ?? now) : _billDate,
      firstDate: DateTime(now.year - 8), lastDate: DateTime(now.year + 8));
    if (picked != null && mounted) {
      setState(() { if (due) { _due = picked; } else { _billDate = picked; } });
    }
  }
  Future<void> _photo(bool bill, ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 88);
      if (picked == null) return;
      final saved = await _storage.keepFile(picked.path, folder: 'KhetPhotos');
      if (mounted) setState(() { if (bill) { _billPhoto = saved; } else { _itemPhoto = saved; } });
    } catch (e) { _error('Photo save nahi hui: $e'); }
  }
  Future<void> _save() async {
    if (_saving) return;
    final title = _item.text.trim();
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final total = double.tryParse(_total.text.trim()) ?? 0;
    final paid = double.tryParse(_paid.text.trim()) ?? 0;
    final vendor = contacts.where((c) => c['id'] == _vendorId).toList();
    if (title.isEmpty || _vendorId == null || vendor.isEmpty) {
      _error('Samaan aur dukaan wale ka naam zaroor bharein'); return;
    }
    if (total <= 0 || paid < 0 || paid > total || qty < 0) {
      _error('Bill, quantity aur paid amount sahi bharein'); return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final id = now.microsecondsSinceEpoch.toString();
      final v = vendor.first;
      await _storage.addRecord('khet', {
        'id': id, 'type': 'KHET_PURCHASE', 'purchaseCategory': _category,
        'title': title, 'quantity': qty, 'unit': _unit,
        'vendorId': _vendorId, 'vendorName': v['name'], 'vendorPhone': v['phone'],
        'totalAmount': total, 'price': total, 'paidAmount': paid,
        'balance': total - paid, 'status': paid >= total ? 'PAID' : (paid > 0 ? 'PARTIAL' : 'PENDING'),
        'invoiceDate': DateTime(_billDate.year, _billDate.month, _billDate.day).toIso8601String(),
        'date': DateTime(_billDate.year, _billDate.month, _billDate.day).toIso8601String(),
        'dueDate': _due?.toIso8601String(), 'billPhoto': _billPhoto,
        'billPhotos': _billPhoto == null ? [] : [_billPhoto],
        'itemPhoto': _itemPhoto, 'itemPhotos': _itemPhoto == null ? [] : [_itemPhoto],
        'note': _note.text.trim(),
        'payments': paid > 0 ? [{'amount': paid, 'direction': 'Diya', 'date': now.toIso8601String()}] : [],
        'createdAt': now.toIso8601String()
      });
      if (mounted) Navigator.pop(context);
    } catch (e) { _error('Purchase save nahi hui: $e'); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  Widget _photoRow(String label, bool bill, String? path) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      Wrap(spacing: 8, children: [
        TextButton.icon(onPressed: () => _photo(bill, ImageSource.camera),
          icon: const Icon(Icons.camera_alt), label: const Text('Camera')),
        TextButton.icon(onPressed: () => _photo(bill, ImageSource.gallery),
          icon: const Icon(Icons.photo), label: const Text('Gallery')),
      ]),
      if (path != null) Row(children: [
        mediaThumbnail(path, size: 80),
        IconButton(onPressed: () => setState(() {
          if (bill) { _billPhoto = null; } else { _itemPhoto = null; }
        }), icon: const Icon(Icons.delete_outline, color: Colors.red))
      ]),
    ]);
  @override
  Widget build(BuildContext context) {
    final selected = contacts.where((c) => c['id'] == _vendorId).toList();
    final total = double.tryParse(_total.text) ?? 0;
    final paid = double.tryParse(_paid.text) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Dawai / Khaad Purchase')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: ['Dawai', 'Fertilizer', 'Beej', 'Other'].map((v) =>
            DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => _category = v ?? _category)),
        const SizedBox(height: 8),
        TextField(controller: _item, decoration: const InputDecoration(labelText: 'Samaan ka naam (DAP, Urea, dawa etc.)')),
        Row(children: [
          Expanded(child: TextField(controller: _qty, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantity'))),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Unit'),
            items: ['Packet', 'Bottle', 'Bag', 'Kg', 'Litre', 'Piece', 'Other'].map((v) =>
              DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _unit = v ?? _unit))),
        ]),
        OutlinedButton.icon(onPressed: () => _date(false), icon: const Icon(Icons.calendar_month),
          label: Text('Bill date: ${dateLabel(_billDate)}')),
        OutlinedButton.icon(onPressed: _pickVendor, icon: const Icon(Icons.contacts),
          label: Text(selected.isEmpty ? 'Phone contact se shop/person' : 'Selected: ${selected.first['name']}')),
        if (contacts.isNotEmpty) DropdownButtonFormField<String>(initialValue: _vendorId,
          decoration: const InputDecoration(labelText: 'Saved person/shop'),
          items: contacts.map((c) => DropdownMenuItem(value: c['id'].toString(),
            child: Text((c['name'] ?? '').toString()))).toList(),
          onChanged: (v) => setState(() => _vendorId = v)),
        TextButton.icon(onPressed: _manualVendor, icon: const Icon(Icons.person_add),
          label: const Text('Naya dukaan wala save karein')),
        TextField(controller: _total, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Total bill ₹')),
        TextField(controller: _paid, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Abhi diya ₹')),
        Card(child: ListTile(title: Text('Pending: ₹${(total - paid).clamp(0, double.infinity).toStringAsFixed(0)}'),
          subtitle: Text(paid >= total ? 'Paid' : 'Udhar / pending'))),
        if (total > paid) OutlinedButton.icon(onPressed: () => _date(true),
          icon: const Icon(Icons.event), label: Text(_due == null ? 'Due date (optional)' : 'Due: ${dateLabel(_due!)}')),
        VoiceDictationField(controller: _note, label: 'Note optional'),
        const SizedBox(height: 10), _photoRow('Bill ki photo', true, _billPhoto),
        const SizedBox(height: 10), _photoRow('Dawai / samaan ki photo', false, _itemPhoto),
        const SizedBox(height: 16), FilledButton(onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save Purchase')),
      ]),
    );
  }
}

class KhetVendorLedgerScreen extends StatefulWidget {
  const KhetVendorLedgerScreen({required this.vendorId, required this.vendorName, super.key});
  final String vendorId, vendorName;
  @override
  State<KhetVendorLedgerScreen> createState() => _KhetVendorLedgerScreenState();
}
class _KhetVendorLedgerScreenState extends State<KhetVendorLedgerScreen> {
  final _storage = StorageBackupService.instance;
  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse((v ?? '').toString()) ?? 0;
  List<Map<String, dynamic>> get purchases => _storage.records('khet')
    .where((r) => r['type'] == 'KHET_PURCHASE' && r['vendorId'] == widget.vendorId).toList();
  List<Map<String, dynamic>> get payments => _storage.records('khet')
    .where((r) => r['type'] == 'KHET_PURCHASE_PAYMENT' && r['vendorId'] == widget.vendorId).toList();
  double get balance => purchases.fold<double>(0, (s, r) => s + _n(r['totalAmount']) - _n(r['paidAmount']))
    - payments.fold<double>(0, (s, r) => s + _n(r['amount']));
  Future<void> _addPayment() async {
    final amount = TextEditingController(), note = TextEditingController();
    DateTime date = DateTime.now();
    final result = await showDialog<Map<String, dynamic>>(context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text('Payment · ${widget.vendorName}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Current balance ₹${balance.toStringAsFixed(0)}'),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Payment amount ₹')),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
          OutlinedButton(onPressed: () async {
            final d = await showDatePicker(context: ctx, initialDate: date,
              firstDate: DateTime(DateTime.now().year - 8), lastDate: DateTime(DateTime.now().year + 8));
            if (d != null) setD(() => date = d);
          }, child: Text('Date: ${dateLabel(date)}')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final n = double.tryParse(amount.text);
            if (n != null && n > 0) Navigator.pop(ctx, {'amount': n, 'note': note.text, 'date': date});
          }, child: const Text('Save')),
        ],
      )));
    amount.dispose(); note.dispose();
    if (result == null) return;
    await _storage.addRecord('khet', {
      'id': DateTime.now().microsecondsSinceEpoch.toString(), 'type': 'KHET_PURCHASE_PAYMENT',
      'vendorId': widget.vendorId, 'vendorName': widget.vendorName, 'amount': result['amount'],
      'date': (result['date'] as DateTime).toIso8601String(), 'note': result['note'],
      'allocationMethod': 'OLDEST_BILL_FIRST'
    });
    if (mounted) setState(() {});
  }
  Widget _line(String label, double value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
      Text('₹${value.toStringAsFixed(0)}', style: TextStyle(
        fontWeight: bold ? FontWeight.w800 : null,
        color: bold ? (balance > 0 ? Colors.red : Colors.green) : null)),
    ]));
  @override
  Widget build(BuildContext context) {
    final rows = [...purchases, ...payments]..sort((a, b) =>
      (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
    final bought = purchases.fold<double>(0, (s, r) => s + _n(r['totalAmount']));
    final atPurchase = purchases.fold<double>(0, (s, r) => s + _n(r['paidAmount']));
    final later = payments.fold<double>(0, (s, r) => s + _n(r['amount']));
    return Scaffold(
      appBar: AppBar(title: Text('${widget.vendorName} · Khata')),
      body: Column(children: [
        Card(margin: const EdgeInsets.all(12), child: Padding(padding: const EdgeInsets.all(12),
          child: Column(children: [
            _line('Total purchase', bought), _line('Paid at purchase', atPurchase),
            _line('Later payments', later), const Divider(),
            _line(balance >= 0 ? 'Pending' : 'Advance', balance.abs(), bold: true),
            const Text('Payments adjust the oldest bill first.', style: TextStyle(fontSize: 12)),
          ]))),
        Expanded(child: rows.isEmpty ? const Center(child: Text('No purchase records')) :
          ListView.builder(itemCount: rows.length, itemBuilder: (ctx, i) {
            final r = rows[i];
            final isPurchase = r['type'] == 'KHET_PURCHASE';
            final date = DateTime.tryParse((r['date'] ?? '').toString()) ?? DateTime.now();
            final subtitle = '${dateLabel(date)}'
              '${isPurchase ? ' · Bill ₹${_n(r['totalAmount']).toStringAsFixed(0)} · Paid ₹${_n(r['paidAmount']).toStringAsFixed(0)}' : ''}'
              '${(r['note'] ?? '').toString().isEmpty ? '' : '\n${r['note']}'}';
            return ListTile(
              leading: Icon(isPurchase ? Icons.shopping_bag : Icons.payments),
              title: Text(isPurchase ? (r['title'] ?? 'Purchase').toString() : 'Payment ₹${_n(r['amount']).toStringAsFixed(0)}'),
              subtitle: Text(subtitle),
            );
          })),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addPayment,
        icon: const Icon(Icons.payments), label: const Text('Add Payment')),
    );
  }
}
