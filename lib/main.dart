import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const sbUrl = String.fromEnvironment('SUPABASE_URL');
const sbKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(minutes: 10)));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (sbUrl.startsWith('https://') && sbKey.isNotEmpty) {
    try { await Supabase.initialize(url: sbUrl, anonKey: sbKey); } catch (_) {}
  }
  runApp(const VideoDownloaderApp());
}

class VideoDownloaderApp extends StatelessWidget {
  const VideoDownloaderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Video Downloader',
    theme: ThemeData(
      brightness: Brightness.dark, useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF090D18),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF756BFF), brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF090D18)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFF171F31),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    ),
    home: const DownloaderHome(),
  );
}

class VideoItem {
  final String name, path, url, date;
  final int bytes;
  const VideoItem(this.name, this.path, this.url, this.date, this.bytes);
  Map<String,dynamic> toMap() => {'name':name,'path':path,'url':url,'date':date,'bytes':bytes};
  factory VideoItem.fromMap(Map<String,dynamic> m) => VideoItem(m['name']??'video',m['path']??'',m['url']??'',m['date']??'',m['bytes']??0);
}

class DownloaderHome extends StatefulWidget {
  const DownloaderHome({super.key});
  @override
  State<DownloaderHome> createState() => _DownloaderHomeState();
}

class _DownloaderHomeState extends State<DownloaderHome> {
  final controller = TextEditingController();
  final items = <VideoItem>[];
  bool busy = false;
  double progress = 0;
  String message = 'Paste a direct video file link to begin.';
  CancelToken? cancel;
  int page = 0;

  @override
  void initState() { super.initState(); loadHistory(); }
  Future<void> loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('videos') ?? [];
    if (!mounted) return;
    setState(() { items..clear()..addAll(list.map((s) => VideoItem.fromMap(Map<String,dynamic>.from(Uri.splitQueryString(s))))); });
  }
  Future<void> saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('videos', items.map((v) => Uri(queryParameters:v.toMap().map((k,v)=>MapEntry(k,'$v'))).query).toList());
  }
  String platform(String value) {
    final h = Uri.tryParse(value)?.host.toLowerCase() ?? '';
    if (h.contains('tiktok')) return 'TikTok';
    if (h.contains('facebook') || h == 'fb.watch') return 'Facebook';
    if (h.contains('instagram')) return 'Instagram';
    return 'Direct link';
  }
  bool direct(String value) {
    final u = Uri.tryParse(value);
    if (u == null || !u.hasScheme || !['http','https'].contains(u.scheme)) return false;
    return ['.mp4','.mov','.m4v','.webm','.mkv','.3gp'].any(u.path.toLowerCase().endsWith);
  }
  String filename(String value) {
    final u = Uri.parse(value);
    var n = u.pathSegments.isEmpty ? 'video.mp4' : Uri.decodeComponent(u.pathSegments.last);
    n = n.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
    if (!n.contains('.')) n += '.mp4';
    return n.length > 90 ? n.substring(n.length-90) : n;
  }
  Future<void> download() async {
    final value = controller.text.trim();
    final u = Uri.tryParse(value);
    if (u == null || !u.hasScheme || !['http','https'].contains(u.scheme)) {
      setState(()=>message='Enter a valid http:// or https:// link.'); return;
    }
    if (!direct(value)) {
      setState(()=>message='This looks like a ${platform(value)} page link, not a direct video file. Use the platform’s official Save/Download option when available. This app does not bypass logins or platform restrictions.'); return;
    }
    if (busy) return;
    setState(()=>{busy=true,progress=0,message='Starting download…'});
    cancel = CancelToken();
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/Videos');
      await dir.create(recursive:true);
      final name = filename(value);
      var path = '${dir.path}/$name';
      var i=1;
      while(await File(path).exists()) {
        final dot=name.lastIndexOf('.');
        path='${dir.path}/${dot>0?name.substring(0,dot):name}_$i${dot>0?name.substring(dot):'.mp4'}'; i++;
      }
      await dio.download(value,path,cancelToken:cancel,onReceiveProgress:(r,t) {
        if (mounted) setState(()=>{progress:t>0?r/t:0,message:t>0?'Downloading ${(r/t*100).toStringAsFixed(0)}%':'Downloading…'});
      });
      final f=File(path); final bytes=await f.length();
      items.insert(0,VideoItem(path.split('/').last,path,value,DateTime.now().toIso8601String(),bytes));
      await saveHistory(); await logEvent(platform(value),bytes);
      if(mounted) setState(()=>message='Download complete. Saved in My Videos.');
    } on DioException catch(e) {
      if(mounted) setState(()=>message=CancelToken.isCancel(e)?'Download cancelled.':'Download failed. The server may block direct downloads or require access.');
    } catch(_) {
      if(mounted) setState(()=>message='Could not save the file. Check storage and try again.');
    } finally { if(mounted) setState(()=>{busy=false,progress=0}); }
  }
  Future<void> logEvent(String p,int b) async {
    if(sbUrl.isEmpty||sbKey.isEmpty) return;
    try { await Supabase.instance.client.from('download_events').insert({'platform':p,'bytes':b}); } catch (_) {}
  }
  Future<void> remove(VideoItem v) async {
    try { final f=File(v.path); if(await f.exists()) await f.delete(); } catch (_) {}
    items.remove(v); await saveHistory(); if(mounted)setState(()=>{});
  }
  String size(int b)=>b<1048576?'${(b/1024).toStringAsFixed(0)} KB':'${(b/1048576).toStringAsFixed(1)} MB';
  @override
  void dispose(){controller.dispose();cancel?.cancel();super.dispose();}

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Row(children:[Icon(Icons.play_circle_fill_rounded,color:Color(0xFF9B93FF),size:30),SizedBox(width:9),Text('Video Downloader',style:TextStyle(fontWeight:FontWeight.w800))]),),
    body:SafeArea(child:page==0?home():history()),
    bottomNavigationBar:NavigationBar(backgroundColor:const Color(0xFF131B2A),selectedIndex:page,onDestinationSelected:(v)=>setState(()=>page=v),destinations:const [
      NavigationDestination(icon:Icon(Icons.download_outlined),selectedIcon:Icon(Icons.download),label:'Downloader'),
      NavigationDestination(icon:Icon(Icons.video_library_outlined),selectedIcon:Icon(Icons.video_library),label:'My Videos'),
    ]),
  );
  Widget home()=>ListView(padding:const EdgeInsets.all(20),children:[
    Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF29245F),Color(0xFF17283F)]),borderRadius:BorderRadius.circular(24)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(Icons.cloud_download_rounded,size:44,color:Color(0xFFC4BFFF)),SizedBox(height:15),
      Text('Save videos with ease',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
      SizedBox(height:8),Text('Download video files from links you are allowed to save.',style:TextStyle(color:Colors.white70,height:1.4)),
    ])),
    const SizedBox(height:24),const Text('Paste video link',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),const SizedBox(height:10),
    TextField(controller:controller,keyboardType:TextInputType.url,decoration:InputDecoration(hintText:'https://example.com/video.mp4',prefixIcon:const Icon(Icons.link),suffixIcon:IconButton(onPressed:controller.clear,icon:const Icon(Icons.close)))),
    const SizedBox(height:14),SizedBox(height:54,child:FilledButton.icon(onPressed:busy?null:download,icon:const Icon(Icons.download_rounded),label:Text(busy?'Downloading…':'Download video',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)))),
    if(busy)...[const SizedBox(height:16),LinearProgressIndicator(value:progress>0?progress:null,minHeight:7),Align(alignment:Alignment.centerRight,child:Text('${(progress*100).toStringAsFixed(0)}%')),TextButton.icon(onPressed:()=>cancel?.cancel(),icon:const Icon(Icons.cancel_outlined),label:const Text('Cancel'))],
    const SizedBox(height:14),Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF171F31),borderRadius:BorderRadius.circular(16)),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.info_outline,color:Color(0xFF9B93FF)),const SizedBox(width:10),Expanded(child:Text(message,style:const TextStyle(color:Colors.white70,height:1.45)))])),
    const SizedBox(height:25),const Text('Supported sources',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),const SizedBox(height:10),
    Wrap(spacing:8,children:['TikTok','Facebook','Instagram','Direct links'].map((s)=>Chip(avatar:const Icon(Icons.link,size:16),label:Text(s),backgroundColor:const Color(0xFF171F31))).toList()),
    const SizedBox(height:12),const Text('Social page URLs are not direct video files. Use official download/save options where offered. No login, DRM, or platform restrictions are bypassed.',style:TextStyle(color:Colors.white54,fontSize:12,height:1.5)),
  ]);
  Widget history()=>items.isEmpty?const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.video_library_outlined,size:58,color:Colors.white30),SizedBox(height:12),Text('No downloads yet',style:TextStyle(color:Colors.white70,fontSize:17)),Text('Your videos will appear here',style:TextStyle(color:Colors.white38))])):ListView.builder(padding:const EdgeInsets.all(14),itemCount:items.length,itemBuilder:(c,i){
    final v=items[i]; return Card(color:const Color(0xFF171F31),child:ListTile(
      leading:const CircleAvatar(backgroundColor:Color(0xFF29245F),child:Icon(Icons.movie,color:Color(0xFFC4BFFF))),
      title:Text(v.name,maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text('${size(v.bytes)} • ${v.date.split('T').first}'),
      onTap:()async{if(await File(v.path).exists()){await OpenFilex.open(v.path);}else if(mounted)setState(()=>message='File no longer exists on this device.');},
      trailing:PopupMenuButton<String>(onSelected:(a)async{if(a=='share')await Share.shareXFiles([XFile(v.path)]);if(a=='delete')await remove(v);},itemBuilder:(_)=>const[PopupMenuItem(value:'share',child:Text('Share')),PopupMenuItem(value:'delete',child:Text('Delete'))]),
    ));
  });
}
