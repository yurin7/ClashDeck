import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/update/update_check.dart';

class AndroidUpdateInstaller {
  const AndroidUpdateInstaller();

  static const _channel = MethodChannel('dev.clashdeck/update');
  static const _timeout = Duration(seconds: 20);

  Future<UpdateApk?> selectApk(UpdateInfo info) async {
    final abis = await _channel.invokeListMethod<String>('supportedAbis') ?? [];
    for (final abi in abis) {
      if (info.androidApks[abi] case final apk?) return apk;
    }
    return null;
  }

  Future<File> download(
    UpdateApk apk, {
    required HttpClient client,
    required void Function(double progress) onProgress,
  }) async {
    final cache = await getTemporaryDirectory();
    final directory = await Directory('${cache.path}/updates').create();
    final apkFile = File('${directory.path}/${apk.name}');
    final temp = await directory.createTemp('download-');
    final partial = File('${temp.path}/package.part');
    try {
      final request = await client.getUrl(apk.url).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('下载失败（HTTP ${response.statusCode}）');
      }
      var bytes = 0;
      final sink = partial.openWrite();
      try {
        await sink.addStream(
          response.timeout(_timeout).map((chunk) {
            bytes += chunk.length;
            if (bytes > apk.size) throw const FormatException('安装包大小不匹配');
            onProgress(bytes / apk.size);
            return chunk;
          }),
        );
      } finally {
        await sink.close();
      }
      if (bytes != apk.size) throw const FormatException('安装包下载不完整');
      return await partial.rename(apkFile.path);
    } finally {
      if (await partial.exists()) await partial.delete();
      await temp.delete();
    }
  }

  /// 返回 false 时，需要先打开 Android 的安装来源授权。
  Future<bool> openInstaller(File apk) async =>
      await _channel.invokeMethod<bool>('installApk', apk.path) ?? false;

  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');
}
