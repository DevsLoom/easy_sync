import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/core.dart';

/// Callback used to add or remove a [WidgetsBindingObserver].
typedef ObserverCallback = void Function(WidgetsBindingObserver observer);

/// Scheduler that triggers app-open sync on start and resume.
class AppOpenSyncScheduler with WidgetsBindingObserver {
  /// Creates an app-open sync scheduler.
  AppOpenSyncScheduler(
    this._engine, {
    ObserverCallback? addObserver,
    ObserverCallback? removeObserver,
  }) : _addObserver = addObserver ?? WidgetsBinding.instance.addObserver,
       _removeObserver =
           removeObserver ?? WidgetsBinding.instance.removeObserver;

  final SyncEngine _engine;
  final ObserverCallback _addObserver;
  final ObserverCallback _removeObserver;
  bool _started = false;

  /// Starts observing lifecycle changes and triggers an initial app-open sync.
  Future<void> start({Map<String, Object?> metadata = const {}}) async {
    if (_started) {
      return;
    }

    _started = true;
    _addObserver(this);

    await trigger(
      metadata: <String, Object?>{...metadata, 'event': 'app_start'},
    );
  }

  /// Stops lifecycle observation.
  void stop() {
    if (!_started) {
      return;
    }

    _removeObserver(this);
    _started = false;
  }

  /// Triggers app-open sync immediately.
  Future<void> trigger({Map<String, Object?> metadata = const {}}) {
    return _engine.runAll(SyncPolicyType.appOpen, metadata: metadata);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || state != AppLifecycleState.resumed) {
      return;
    }

    unawaited(
      trigger(metadata: const <String, Object?>{'event': 'app_resume'}),
    );
  }
}
