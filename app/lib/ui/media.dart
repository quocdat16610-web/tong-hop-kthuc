// Hiển thị Markdown (kèm ảnh lưu trong app) và phát video ngay trong ứng dụng.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/storage.dart';
import '../core/templates.dart';
import 'theme.dart';

Widget assetImage(String src, {BoxFit fit = BoxFit.contain, double? width}) {
  if (src.startsWith('asset:')) {
    final f = Storage.I.assetFile(src);
    if (f == null) return const Text('(không tìm thấy ảnh trên máy này)');
    return Image.file(f, fit: fit, width: width);
  }
  if (src.startsWith('http')) return Image.network(src, fit: fit, width: width, errorBuilder: (_, __, ___) => const Text('(không tải được ảnh)'));
  return const SizedBox();
}

class MarkdownView extends StatelessWidget {
  final String text;
  final List<GlobalKey>? headingKeys;
  const MarkdownView(this.text, {super.key, this.headingKeys});

  @override
  Widget build(BuildContext context) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: base.copyWith(
        p: context.tt.bodyLarge?.copyWith(height: 1.6),
        code: TextStyle(fontFamily: monoFont, fontSize: 13.5, backgroundColor: context.cs.surfaceContainer),
        codeblockDecoration: BoxDecoration(color: context.cs.surfaceContainer, borderRadius: BorderRadius.circular(4)),
        h1: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        h2: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        h3: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: context.cs.outline, width: 3))),
      ),
      imageBuilder: (uri, title, alt) => assetImage(uri.toString()),
      onTapLink: (text, href, title) {
        if (href != null && href.startsWith('http')) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
    );
  }
}

/// Lấy các tiêu đề # / ## / ### trong Markdown (bỏ qua khối ```code```).
List<({int level, String text})> markdownHeadings(String? text) {
  final out = <({int level, String text})>[];
  var fence = false;
  for (final line in (text ?? '').split('\n')) {
    if (RegExp(r'^\s*```').hasMatch(line)) fence = !fence;
    if (fence) continue;
    final m = RegExp(r'^(#{1,3})\s+(.+?)\s*#*\s*$').firstMatch(line);
    if (m != null) out.add((level: m.group(1)!.length, text: m.group(2)!.replaceAll(RegExp(r'[*_`]'), '')));
  }
  return out;
}

// ---------- Video ----------
class VideoView extends StatefulWidget {
  final String url;
  final String timestamps;
  const VideoView({super.key, required this.url, this.timestamps = ''});
  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  VideoPlayerController? ctl;
  String? error;
  bool loading = false;
  bool started = false;

  VideoSource? get src => parseVideo(widget.url);

  @override
  void didUpdateWidget(covariant VideoView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      ctl?.dispose();
      ctl = null;
      started = false;
      error = null;
    }
  }

  @override
  void dispose() {
    ctl?.dispose();
    super.dispose();
  }

  Future<void> _start([int seek = 0]) async {
    final s = src;
    if (s == null) return;
    setState(() {
      loading = true;
      started = true;
      error = null;
    });
    try {
      VideoPlayerController c;
      if (s.kind == 'asset') {
        final f = Storage.I.assetFile(s.value);
        if (f == null) throw Exception('Không tìm thấy file video trên máy này.');
        c = VideoPlayerController.file(File(f.path));
      } else if (s.kind == 'youtube') {
        // Lấy luồng video trực tiếp từ YouTube rồi phát bằng trình phát của hệ thống (không qua trình duyệt).
        final yt = YoutubeExplode();
        try {
          final manifest = await yt.videos.streams.getManifest(s.value, ytClients: [YoutubeApiClient.androidVr]);
          if (manifest.muxed.isEmpty) throw Exception('Video không có luồng phát phù hợp.');
          c = VideoPlayerController.networkUrl(manifest.muxed.bestQuality.url);
        } finally {
          yt.close();
        }
        seek = seek == 0 ? s.start : seek;
      } else if (s.kind == 'drive') {
        // File video công khai trên Google Drive: tải luồng trực tiếp.
        c = VideoPlayerController.networkUrl(Uri.parse('https://drive.usercontent.google.com/download?id=${s.value}&export=download&confirm=t'));
      } else {
        c = VideoPlayerController.networkUrl(Uri.parse(s.value));
      }
      await c.initialize();
      if (seek > 0) await c.seekTo(Duration(seconds: seek));
      await c.play();
      c.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        ctl = c;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> seekTo(int sec) async {
    if (ctl == null) return _start(sec);
    await ctl!.seekTo(Duration(seconds: sec));
    await ctl!.play();
  }

  String _fmt(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = src;
    final ts = parseTimestamps(widget.timestamps);
    Widget player;
    if (s == null) {
      player = _placeholder(context, widget.url.isEmpty ? 'Chưa có video.' : 'Link video không hợp lệ.');
    } else if (s.kind == 'link') {
      player = _placeholder(context, 'Trang video này (${Uri.tryParse(s.value)?.host ?? 'web'}) không cho phát trong app — bấm để mở.',
          action: OutlinedButton.icon(icon: const Icon(Icons.open_in_new), label: const Text('Mở video'), onPressed: () => launchUrl(Uri.parse(s.value), mode: LaunchMode.externalApplication)));
    } else if (ctl != null && ctl!.value.isInitialized) {
      final v = ctl!.value;
      player = Column(children: [
        AspectRatio(aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio, child: Container(color: Colors.black, child: VideoPlayer(ctl!))),
        Row(children: [
          IconButton(icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow), onPressed: () => v.isPlaying ? ctl!.pause() : ctl!.play()),
          Text(_fmt(v.position), style: TextStyle(fontFamily: monoFont, fontSize: 12)),
          Expanded(
            child: Slider(
              value: v.position.inMilliseconds.clamp(0, v.duration.inMilliseconds).toDouble(),
              max: v.duration.inMilliseconds <= 0 ? 1 : v.duration.inMilliseconds.toDouble(),
              onChanged: (x) => ctl!.seekTo(Duration(milliseconds: x.round())),
            ),
          ),
          Text(_fmt(v.duration), style: TextStyle(fontFamily: monoFont, fontSize: 12)),
          IconButton(icon: Icon(v.volume == 0 ? Icons.volume_off : Icons.volume_up), onPressed: () => ctl!.setVolume(v.volume == 0 ? 1 : 0)),
        ]),
      ]);
    } else {
      player = AspectRatio(
        aspectRatio: 16 / 9,
        child: Material(
          color: Colors.black,
          child: Ink(
            decoration: s.kind == 'youtube' && error == null && !loading
                ? BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage('https://i.ytimg.com/vi/${s.value}/hqdefault.jpg'),
                      fit: BoxFit.cover,
                      colorFilter: const ColorFilter.mode(Colors.black45, BlendMode.darken),
                      onError: (_, _) {},
                    ),
                  )
                : null,
            child: InkWell(
            onTap: loading ? null : () => _start(),
            child: Center(
              child: loading
                  ? const CircularProgressIndicator()
                  : error != null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('Không phát được: $error', style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, children: [
                              OutlinedButton(onPressed: () => _start(), child: const Text('Thử lại')),
                              if (s.kind == 'youtube' || s.kind == 'drive')
                                OutlinedButton(
                                  onPressed: () => launchUrl(
                                      Uri.parse(s.kind == 'youtube' ? 'https://www.youtube.com/watch?v=${s.value}' : 'https://drive.google.com/file/d/${s.value}/view'),
                                      mode: LaunchMode.externalApplication),
                                  child: Text(s.kind == 'youtube' ? 'Mở bằng YouTube' : 'Mở Google Drive'),
                                ),
                            ]),
                          ]),
                        )
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.play_circle_outline, color: Colors.white, size: 56),
                          Text(s.kind == 'youtube' ? 'Bấm để phát video YouTube' : s.kind == 'drive' ? 'Bấm để phát video Google Drive' : 'Bấm để phát', style: const TextStyle(color: Colors.white)),
                        ]),
            ),
          ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(borderRadius: BorderRadius.circular(4), child: player),
      if (ts.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 4, runSpacing: 2, children: [
            for (final t in ts)
              TextButton(
                onPressed: s == null || s.kind == 'link' ? null : () => seekTo(t.sec),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${t.time}  ', style: TextStyle(fontFamily: monoFont, fontWeight: FontWeight.w600)),
                  TextSpan(text: t.label, style: TextStyle(color: context.cs.onSurface)),
                ])),
              ),
          ]),
        ),
    ]);
  }

  Widget _placeholder(BuildContext context, String text, {Widget? action}) => Container(
        height: 120,
        alignment: Alignment.center,
        color: context.cs.surfaceContainer,
        child: Column(mainAxisSize: MainAxisSize.min, children: [Text(text, style: TextStyle(color: context.cs.onSurfaceVariant)), if (action != null) ...[const SizedBox(height: 8), action]]),
      );
}
