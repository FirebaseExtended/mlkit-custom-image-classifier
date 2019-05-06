// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';

/// A countdown timer
class CountdownTimer extends Stream<CountdownTimer> {
  static const Duration _ONE_SECOND = Duration(seconds: 1);
  static const _THRESHOLD_MS = 4;

  final Stopwatch _stopwatch;
  final StreamController<CountdownTimer> _controller;

  bool _paused = false;
  Function callBack;
  Duration totalDuration;
  Timer _timer;

  CountdownTimer(this.totalDuration, [this.callBack])
      : _stopwatch = Stopwatch(),
        _controller = StreamController<CountdownTimer>.broadcast(sync: true) {
    _timer = new Timer.periodic(_ONE_SECOND, _tick);
    _stopwatch.start();
  }

  StreamSubscription<CountdownTimer> listen(void onData(CountdownTimer event),
          {Function onError, void onDone(), bool cancelOnError}) =>
      _controller.stream.listen(onData, onError: onError, onDone: onDone);

  Duration get elapsed => _stopwatch.elapsed;

  Duration get remaining => totalDuration - _stopwatch.elapsed;

  bool get isRunning => _stopwatch.isRunning;

  cancel() {
    _stopwatch.stop();
    _timer.cancel();
    _controller.close();
  }

  togglePause() {
    if (_paused) {
      _stopwatch.start();
      _paused = false;
    } else {
      _stopwatch.stop();
      _paused = true;
    }
  }

  _tick(Timer timer) {
    var t = remaining;
    _controller.add(this);
    // timers may have a 4ms resolution
    if (t.inMilliseconds < _THRESHOLD_MS) {
      if (this.callBack != null) {
        this.callBack();
      }
      cancel();
    }
  }
}
