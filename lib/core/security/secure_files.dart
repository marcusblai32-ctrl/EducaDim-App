import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as pth;
import 'package:path_provider/path_provider.dart';

/// Stockage chiffré des fichiers téléchargés.
///
/// * Chiffrement AES-256-GCM (confidentialité + détection de toute modification).
/// * La clé est générée sur le téléphone et gardée dans le coffre sécurisé du système (Android Keystore) :
///   ni dans le fichier, ni dans l'application, ni sur le serveur.
/// * Le nom du fichier sur le disque est un hash de (clé + identifiant) : aucun nom lisible, aucune extension.
/// * Les fichiers sont dans le dossier privé de l'application (jamais la galerie ni « Téléchargements ») ;
///   seul EducaDim peut les déchiffrer, même si quelqu'un copie le fichier.
class SecureFiles {
  SecureFiles({FlutterSecureStorage? storage, Future<Directory> Function()? dirProvider})
      : _storage = storage ?? const FlutterSecureStorage(),
        _dirProvider = dirProvider ?? getApplicationSupportDirectory;

  final FlutterSecureStorage _storage;
  final Future<Directory> Function() _dirProvider;
  static final AesGcm _algo = AesGcm.with256bits();
  static const _keyName = 'edu_files_key_v1';
  static const maxBytes = 60 * 1024 * 1024;

  List<int>? _keyBytes;

  Future<List<int>> _key() async {
    if (_keyBytes != null) return _keyBytes!;
    final stored = await _storage.read(key: _keyName);
    if (stored != null && stored.isNotEmpty) {
      _keyBytes = base64Decode(stored);
      return _keyBytes!;
    }
    final fresh = await (await _algo.newSecretKey()).extractBytes();
    await _storage.write(key: _keyName, value: base64Encode(fresh));
    _keyBytes = fresh;
    return fresh;
  }

  Future<Directory> _dir() async {
    final d = Directory(pth.join((await _dirProvider()).path, '.s'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Nom opaque du fichier pour cet identifiant (hex, sans extension).
  Future<String> nameFor(String id) async {
    final h = await Sha256().hash([...await _key(), ...utf8.encode('|$id')]);
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, 40);
  }

  Future<File> _file(String id) async => File(pth.join((await _dir()).path, await nameFor(id)));

  /// Chiffre et écrit. Retourne la taille du fichier chiffré.
  Future<int> write(String id, Uint8List clear) async {
    final box = await _algo.encrypt(clear, secretKey: SecretKey(await _key()), aad: utf8.encode(id));
    final f = await _file(id);
    final tmp = File('${f.path}.t');
    await tmp.writeAsBytes(box.concatenation(), flush: true);
    await tmp.rename(f.path); // jamais de fichier à moitié écrit
    return await f.length();
  }

  /// Lit et déchiffre en mémoire (rien n'est jamais écrit en clair). null si absent ou modifié.
  Future<Uint8List?> read(String id) async {
    try {
      final f = await _file(id);
      if (!await f.exists()) return null;
      final box = SecretBox.fromConcatenation(await f.readAsBytes(), nonceLength: 12, macLength: 16);
      final clear = await _algo.decrypt(box, secretKey: SecretKey(await _key()), aad: utf8.encode(id));
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String id) async {
    try {
      final f = await _file(id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Efface tous les fichiers chiffrés (changement de compte).
  Future<void> deleteAll() async {
    try {
      final d = await _dir();
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }
}
