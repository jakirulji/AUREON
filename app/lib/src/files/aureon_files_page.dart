import 'package:aureon_local_files/aureon_local_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AureonFilesPage extends StatefulWidget {
  const AureonFilesPage({super.key});
  @override
  State<AureonFilesPage> createState() => _AureonFilesPageState();
}
class _Folder { const _Folder(this.name,this.id); final String name,id; }
class _AureonFilesPageState extends State<AureonFilesPage> {
  final _files=AureonLocalFiles();
  AureonLocalRoot? _root;
  final List<_Folder> _levels=[];
  List<AureonLocalEntry> _entries=[];
  bool _loading=false;
  String? _error;

  Future<void> _choose() async {
    setState(()=>_loading=true);
    try {
      final root=await _files.pickRoot();
      if(!mounted)return;
      if(root==null){setState(()=>_loading=false);return;}
      _root=root;
      _levels..clear()..add(_Folder(root.displayName,root.rootDocumentId));
      await _load();
    } on PlatformException catch(e){_fail(e.message??e.code);}
      catch(e){_fail(e.toString());}
  }
  Future<void> _load() async {
    final root=_root;if(root==null||_levels.isEmpty)return;
    setState(()=>_loading=true);
    try {
      final rows=await _files.listChildren(root:root,parentId:_levels.last.id);
      if(!mounted)return;setState(()=>_entries=rows);setState(()=>_loading=false);
    } on PlatformException catch(e){_fail(e.message??e.code);}
      catch(e){_fail(e.toString());}
  }
  Future<void> _open(AureonLocalEntry e) async {
    if(!e.isDirectory)return;
    setState(()=>_levels.add(_Folder(e.name,e.id)));await _load();
  }
  Future<void> _up() async {if(_levels.length<2)return;setState(()=>_levels.removeLast());await _load();}
  void _fail(String message){if(!mounted)return;setState(()=>_error=message);setState(()=>_loading=false);}
  String _size(int? n){if(n==null)return '—';if(n<1024)return '$n B';if(n<1048576)return '${(n/1024).toStringAsFixed(1)} KB';return '${(n/1048576).toStringAsFixed(1)} MB';}
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.all(22),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Expanded(child:Text('Files',style:TextStyle(fontSize:25,fontWeight:FontWeight.w700))),
        OutlinedButton.icon(onPressed:_loading?null:_choose,icon:const Icon(Icons.create_new_folder_outlined),label:const Text('Choose folder'))]),
      const SizedBox(height:8),
      const Text('Read-only browsing. AUREON will not change files in this folder.',style:TextStyle(color:Color(0xFF9AA8BD),fontSize:12)),
      if(_root!=null) Row(children:[
        IconButton(onPressed:_levels.length>1&&!_loading?_up:null,icon:const Icon(Icons.arrow_upward),tooltip:'Parent folder'),
        Expanded(child:Text(_levels.map((e)=>e.name).join(' / '),maxLines:1,overflow:TextOverflow.ellipsis)),
        IconButton(onPressed:_loading?null:_load,icon:const Icon(Icons.refresh),tooltip:'Refresh')]),
      if(_loading)const LinearProgressIndicator(minHeight:2),
      if(_error!=null)Padding(padding:const EdgeInsets.all(10),child:Text(_error!,style:const TextStyle(color:Color(0xFFFFA0A0)))),
      if(_root==null&&!_loading)Expanded(child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.folder_open_outlined,size:52,color:Color(0xFF8295B1)),
        const SizedBox(height:12),const Text('No folder selected'),
        const SizedBox(height:12),FilledButton.icon(onPressed:_choose,icon:const Icon(Icons.folder_open),label:const Text('Choose folder'))])))
      else Expanded(child:_entries.isEmpty&&!_loading?const Center(child:Text('This folder is empty.')):
        ListView.separated(itemCount:_entries.length,separatorBuilder:(_,_)=>const Divider(height:1),
          itemBuilder:(context,i){final e=_entries[i];return ListTile(
            leading:Icon(e.isDirectory?Icons.folder_outlined:Icons.insert_drive_file_outlined),
            title:Text(e.name,maxLines:1,overflow:TextOverflow.ellipsis),
            subtitle:Text(e.isDirectory?'Folder':'File'),
            trailing:e.isDirectory?const Icon(Icons.chevron_right):Text(_size(e.sizeBytes)),
            onTap:e.isDirectory?()=>_open(e):null);}))
    ]));
}
