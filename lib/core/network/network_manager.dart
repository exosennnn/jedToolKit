import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Port of NetworkManager.swift.
///
/// Holds the app-wide offline mode switch. Same key as iOS
/// ("isOfflineModeEnabled"). Unlike iOS (default online), Android defaults to
/// offline mode ON until the user turns it off.
///
/// iOS posts `offlineModeChanged`; here this is a [ChangeNotifier], so listen
/// with `ListenableBuilder` / `addListener`.
///
/// While offline mode is on, [install] makes every outgoing connection made
/// from Dart fail with a [SocketException] (HttpClient, package:http, dio,
/// Image.network, raw sockets). Loopback (localhost) is still allowed so
/// debugging tools keep working. Turning it off lets traffic through again.
class NetworkManager extends ChangeNotifier {
  NetworkManager._();

  /// Shared singleton instance for global access.
  static final NetworkManager shared = NetworkManager._();

  static const _offlineModeKey = 'isOfflineModeEnabled';

  /// Offline (true) by default.
  bool _offline = true;

  bool get isOfflineModeEnabled => _offline;

  /// Call once in main() before runApp.
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _offline = p.getBool(_offlineModeKey) ?? true;
    install();
  }

  /// Hooks Dart's networking so the switch is enforced, not just stored.
  void install() {
    IOOverrides.global = _OfflineIOOverrides(this);
  }

  /// Throws if offline mode is on. Also usable directly before a request.
  void ensureOnline([Object? host]) {
    if (_offline && !_isLoopback(host)) {
      throw const SocketException(
        'Offline mode is on. Turn it off in Settings to use the network.',
      );
    }
  }

  static bool _isLoopback(Object? host) {
    if (host is InternetAddress) return host.isLoopback;
    if (host is String) {
      return host == 'localhost' || (InternetAddress.tryParse(host)?.isLoopback ?? false);
    }
    return false;
  }

  /// Saves the new value and notifies listeners.
  Future<void> setOfflineMode(bool value) async {
    if (value == _offline) return;
    _offline = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_offlineModeKey, value);
  }
}

final class _OfflineIOOverrides extends IOOverrides {
  final NetworkManager _net;
  _OfflineIOOverrides(this._net);

  @override
  Future<Socket> socketConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    try {
      _net.ensureOnline(host);
    } catch (e) {
      return Future.error(e);
    }
    return super.socketConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    );
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) {
    try {
      _net.ensureOnline(host);
    } catch (e) {
      return Future.error(e);
    }
    return super.socketStartConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
    );
  }
}
