import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link outside the app. Abstracted so widget tests can assert that a
/// tapped chat link reaches the launcher without touching platform channels.
abstract class LinkLauncher {
  const LinkLauncher();

  Future<bool> open(Uri uri);
}

/// System-browser launcher (Android/iOS/web/desktop).
class SystemLinkLauncher extends LinkLauncher {
  const SystemLinkLauncher();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final linkLauncherProvider = Provider<LinkLauncher>(
  (ref) => const SystemLinkLauncher(),
);
