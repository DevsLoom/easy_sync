import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/core.dart';

typedef ObserverCallback = void Function(WidgetsBindingObserver observer);

class AppOpenSyncScheduler with WidgetsBindingObserver {
  AppOpenSyncScheduler(
    this._orchestrator, {
    ObserverCallback? addObserver,
    ObserverCallback? removeObserver,
  })  : _addObserver = addObserver ?? WidgetsBinding.instance.addObserver,
        _removeObserver =
            removeObserver ?? WidgetsBinding.instance.removeObserver;

  final SyncOrchestrator _orchestrator;
  final ObserverCallback _addObserver;
  final ObserverCallback _removeObserver;
  bool _started = false;

  Future<void> start({Map<String, Object?> metadata = const {}}) async {
    if (_started) {
      return;
    }

    _started = true;
    _addObserver(this);

    await trigger(
      metadata: <String, Object?>{
        ...metadata,
        'event': 'app_start',
      },
    );
  }

  void stop() {
    if (!_started) {
      return;
    }

    _removeObserver(this);
    _started = false;
  }

  Future<void> trigger({Map<String, Object?> metadata = const {}}) {
    return _orchestrator.syncOnAppOpen(metadata: metadata);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || state != AppLifecycleState.resumed) {
      return;
    }

    unawaited(
      trigger(
        metadata: const <String, Object?>{
          'event': 'app_resume',
        },
      ),
    );
  }
}
