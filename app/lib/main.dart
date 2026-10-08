import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'core/runner.dart';
import 'core/storage.dart';
import 'core/templates.dart';
import 'core/vcs.dart';
import 'ui/ide.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/vcs_dialogs.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  if (desktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      Platform.environment['SOTAY_PHONE'] != null
          ? const WindowOptions(title: 'Sổ tay DSA C++', size: Size(400, 820), minimumSize: Size(360, 480))
          : const WindowOptions(title: 'Sổ tay DSA C++', size: Size(1280, 800), minimumSize: Size(720, 480), center: true),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  await Storage.init(override: Platform.environment['SOTAY_DATA_DIR'] != null ? Directory(Platform.environment['SOTAY_DATA_DIR']!) : null);
  await loadTemplates();
  LocalBackend.cleanupAll();

  final app = AppState();
  final last = app.setting<String?>('lastRepo', null);
  final repo = last == null ? null : Storage.I.getRepo(last);
  if (repo != null) app.openRepo(repo);
  // Dùng khi kiểm thử tự động: SOTAY_OPEN=guide mở sổ hướng dẫn, SOTAY_OPEN=ide mở IDE.
  final open = Platform.environment['SOTAY_OPEN'];
  if (open == 'guide' && app.repo == null) {
    final r = Repo.create(title: 'Hướng dẫn sử dụng', author: 'Sổ tay DSA', snapshot: guideSnapshot());
    Storage.I.putRepo(r);
    app.openRepo(r);
  }
  if (open == 'ide' || open == 'notes') app.mode = open!;

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => IdeModel()),
    ],
    child: const SoTayApp(),
  ));

  // Mở file .dsanote.json / .cpp truyền qua dòng lệnh (bấm đúp file trên Windows).
  final link = args.where((a) => a.startsWith('sotaydsa://')).firstOrNull;
  if (link != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navKey.currentContext;
      if (ctx != null) handleIncoming(ctx, link, onOpen: app.openRepo);
    });
  }
  final file = args.where((a) => !a.startsWith('sotaydsa://') && File(a).existsSync()).firstOrNull;
  if (file != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = navKey.currentContext;
      if (ctx == null) return;
      final text = await File(file).readAsString();
      if (!ctx.mounted) return;
      if (file.endsWith('.json')) {
        await handleIncoming(ctx, text, onOpen: app.openRepo);
      } else {
        ctx.read<IdeModel>().openPath(file);
        app.mode = 'ide';
      }
    });
  }
}

class SoTayApp extends StatelessWidget {
  const SoTayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, ThemeMode>((a) => a.themeMode);
    return MaterialApp(
      title: 'Sổ tay DSA C++',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: Builder(builder: (c) {
        // dùng navigatorKey qua Builder để lấy context có Navigator
        return const Shell();
      }),
      navigatorKey: navKey,
    );
  }
}
