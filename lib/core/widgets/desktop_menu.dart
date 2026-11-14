import 'dart:io' show exit;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../i18n/lang.dart';
import '../sync/sync_service.dart';
import '../theme/theme_controller.dart';
import 'text_size.dart';

/// Barre de menus (Fichier, Affichage, Options, Aide) pour la version ordinateur.
/// Sur téléphone elle n'apparaît pas : le widget rend simplement l'écran enfant.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

class DesktopMenuFrame extends StatefulWidget {
  const DesktopMenuFrame({super.key, required this.router, required this.child});
  final GoRouter router;
  final Widget child;

  @override
  State<DesktopMenuFrame> createState() => _DesktopMenuFrameState();
}

class _DesktopMenuFrameState extends State<DesktopMenuFrame> {
  late final OverlayEntry _entry = OverlayEntry(builder: _buildContent);

  @override
  void didUpdateWidget(covariant DesktopMenuFrame old) {
    super.didUpdateWidget(old);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    if (isDesktopPlatform) {
      _entry.remove();
      _entry.dispose();
    }
    super.dispose();
  }

  void _go(String path) => widget.router.go(path);

  Widget _buildContent(BuildContext context) {
    final themeCtrl = Provider.of<ThemeController>(context, listen: false);
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([Lang.instance, themeCtrl]),
      builder: (context, _) => Column(
        children: [
          Material(
            color: cs.surface,
            child: Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant))),
              alignment: Alignment.centerLeft,
              child: MenuBar(
                style: const MenuStyle(
                  elevation: WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                ),
                children: [
                  SubmenuButton(
                    menuChildren: [
                      _item('Accueil', () => _go('/home'), icon: Icons.home_outlined),
                      _item('Mes cours', () => _go('/courses'), icon: Icons.menu_book_outlined),
                      _item('Explorer', () => _go('/explore'), icon: Icons.explore_outlined),
                      _item('Téléchargements', () => _go('/downloads'), icon: Icons.download_outlined),
                      _item('Notifications', () => _go('/notifications'), icon: Icons.notifications_none),
                      _item('Synchroniser maintenant', () {
                        Provider.of<SyncService>(context, listen: false).flush();
                      }, icon: Icons.sync),
                      const Divider(height: 1),
                      MenuItemButton(
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyQ, control: true),
                        leadingIcon: const Icon(Icons.exit_to_app, size: 18),
                        onPressed: () => exit(0),
                        child: Text(tr('Quitter')),
                      ),
                    ],
                    child: Text(tr('Fichier')),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      _item('Système', () => themeCtrl.setMode(ThemeMode.system),
                          checked: themeCtrl.mode == ThemeMode.system),
                      _item('Clair', () => themeCtrl.setMode(ThemeMode.light),
                          checked: themeCtrl.mode == ThemeMode.light),
                      _item('Sombre', () => themeCtrl.setMode(ThemeMode.dark),
                          checked: themeCtrl.mode == ThemeMode.dark),
                      const Divider(height: 1),
                      _item('Agrandir le texte', () => TextSizePref.change(TextSizePref.step), icon: Icons.add),
                      _item('Réduire le texte', () => TextSizePref.change(-TextSizePref.step), icon: Icons.remove),
                      _item('Taille normale du texte', () => TextSizePref.change(1.0 - TextSizePref.scale.value),
                          icon: Icons.text_fields),
                    ],
                    child: Text(tr('Affichage')),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      _item('Français', () => Lang.instance.set('fr'), checked: Lang.instance.code == 'fr'),
                      _item('Kreyòl', () => Lang.instance.set('ht'), checked: Lang.instance.code == 'ht'),
                      const Divider(height: 1),
                      _item('Profil', () => _go('/profile'), icon: Icons.person_outline),
                      _item('Plan d’étude', () => _go('/study/plan'), icon: Icons.event_note_outlined),
                    ],
                    child: Text(tr('Options')),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      _item('Site web EducaDim', () {
                        launchUrl(Uri.parse('https://educadim.onrender.com'), mode: LaunchMode.externalApplication);
                      }, icon: Icons.public),
                      _item('À propos', _about, icon: Icons.info_outline),
                    ],
                    child: Text(tr('Aide')),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  MenuItemButton _item(String label, VoidCallback onTap, {bool checked = false, IconData? icon}) {
    return MenuItemButton(
      onPressed: onTap,
      leadingIcon: checked
          ? const Icon(Icons.check, size: 18)
          : (icon != null ? Icon(icon, size: 18) : const SizedBox(width: 18)),
      child: Text(tr(label)),
    );
  }

  void _about() {
    final nav = widget.router.routerDelegate.navigatorKey.currentContext;
    if (nav == null) return;
    showAboutDialog(
      context: nav,
      applicationName: 'EducaDim',
      applicationVersion: '1.0.0',
      applicationLegalese: '© Dimension Production',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return widget.child;
    return Overlay(initialEntries: [_entry]);
  }
}
