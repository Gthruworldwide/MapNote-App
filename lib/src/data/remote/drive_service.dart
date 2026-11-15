import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import 'auth_service.dart';

/// Contract for storing/reading the single JSON backup file in the user's
/// hidden Google Drive `appDataFolder`.
abstract class DriveService {
  Future<bool> backupExists();

  Future<DateTime?> remoteModifiedTime();

  /// Returns the raw backup JSON, or null when no backup exists.
  Future<String?> downloadBackup();

  /// Overwrites the backup with [jsonContent].
  Future<void> uploadBackup(String jsonContent);
}

/// [DriveService] implemented with `googleapis` Drive API v3 against the
/// hidden app-data folder. Only the OAuth scope `drive.appdata` is requested,
/// so the user's normal Drive files are never touched.
class GoogleDriveService implements DriveService {
  GoogleDriveService(
    this._auth, {
    this.backupFileName = AppConfig.backupFileName,
  });

  final AuthService _auth;
  final String backupFileName;

  late final http.Client _client = _AuthenticatedClient(http.Client(), _auth);
  late final drive.DriveApi _api = drive.DriveApi(_client);

  @override
  Future<bool> backupExists() async => (await _findFile()) != null;

  @override
  Future<DateTime?> remoteModifiedTime() async {
    final drive.File? file = await _findFile();
    return file?.modifiedTime?.toUtc();
  }

  @override
  Future<String?> downloadBackup() async {
    final String? fileId = (await _findFile())?.id;
    if (fileId == null) return null;

    final Object response = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (response is! drive.Media) return null;

    final List<int> bytes = <int>[];
    await for (final List<int> chunk in response.stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  @override
  Future<void> uploadBackup(String jsonContent) async {
    final List<int> bytes = utf8.encode(jsonContent);
    final drive.Media media = drive.Media(
      Stream<List<int>>.value(bytes),
      bytes.length,
      contentType: AppConfig.backupMimeType,
    );

    final String? existingId = (await _findFile())?.id;
    if (existingId == null) {
      final drive.File metadata = drive.File(
        name: backupFileName,
        parents: const <String>['appDataFolder'],
        mimeType: AppConfig.backupMimeType,
      );
      await _api.files.create(metadata, uploadMedia: media, $fields: 'id');
    } else {
      await _api.files.update(
        drive.File(),
        existingId,
        uploadMedia: media,
        $fields: 'id',
      );
    }
  }

  Future<drive.File?> _findFile() async {
    final drive.FileList result = await _api.files.list(
      q: "name = '$backupFileName' and trashed = false",
      spaces: 'appDataFolder',
      $fields: 'files(id, name, modifiedTime)',
    );
    final List<drive.File>? files = result.files;
    if (files == null || files.isEmpty) return null;
    return files.first;
  }
}

/// An [http.Client] that injects a fresh Google authorization header on every
/// request, obtained through [AuthService]. This lets the Drive API reuse the
/// token cache managed by `google_sign_in`.
class _AuthenticatedClient extends http.BaseClient {
  _AuthenticatedClient(this._inner, this._auth);

  final http.Client _inner;
  final AuthService _auth;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final Map<String, String>? headers = await _auth.authorizationHeaders();
    if (headers == null) {
      throw const AuthRequiredException();
    }
    request.headers.addAll(headers);
    final http.StreamedResponse response = await _inner.send(request);
    if (response.statusCode == 401) {
      throw const AuthRequiredException(
        'Google Drive rejected the access token',
      );
    }
    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
