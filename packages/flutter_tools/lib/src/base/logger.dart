// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';

import '../base/context.dart';
import '../globals.dart' as globals;
import 'io.dart' hide stderr, stdin, stdout;
import 'terminal.dart' show AnsiTerminal, TerminalColor, OutputPreferences;
import 'utils.dart';

const int kDefaultStatusPadding = 59;
const Duration _kFastOperation = Duration(seconds: 2);
const Duration _kSlowOperation = Duration(minutes: 2);

/// The [TimeoutConfiguration] instance.
///
/// If not provided via injection, a default instance is provided.
TimeoutConfiguration get timeoutConfiguration => context.get<TimeoutConfiguration>() ?? const TimeoutConfiguration();

class TimeoutConfiguration {
  const TimeoutConfiguration();

  /// The expected time that various "slow" operations take, such as running
  /// the analyzer.
  ///
  /// Defaults to 2 minutes.
  Duration get slowOperation => _kSlowOperation;

  /// The expected time that various "fast" operations take, such as a hot
  /// reload.
  ///
  /// Defaults to 2 seconds.
  Duration get fastOperation => _kFastOperation;
}

typedef VoidCallback = void Function();

abstract class Logger {
  bool get isVerbose => false;

  bool quiet = false;

  bool get supportsColor;

  bool get hasTerminal;

  AnsiTerminal get _terminal;

  OutputPreferences get _outputPreferences;

  TimeoutConfiguration get _timeoutConfiguration;

  /// Display an error `message` to the user. Commands should use this if they
  /// fail in some way.
  ///
  /// The `message` argument is printed to the stderr in red by default.
  ///
  /// The `stackTrace` argument is the stack trace that will be printed if
  /// supplied.
  ///
  /// The `emphasis` argument will cause the output message be printed in bold text.
  ///
  /// The `color` argument will print the message in the supplied color instead
  /// of the default of red. Colors will not be printed if the output terminal
  /// doesn't support them.
  ///
  /// The `indent` argument specifies the number of spaces to indent the overall
  /// message. If wrapping is enabled in [outputPreferences], then the wrapped
  /// lines will be indented as well.
  ///
  /// If `hangingIndent` is specified, then any wrapped lines will be indented
  /// by this much more than the first line, if wrapping is enabled in
  /// [outputPreferences].
  ///
  /// If `wrap` is specified, then it overrides the
  /// `outputPreferences.wrapText` setting.
  void printError(
    String message, {
    StackTrace stackTrace,
    bool emphasis,
    TerminalColor color,
    int indent,
    int hangingIndent,
    bool wrap,
  });

  /// Display normal output of the command. This should be used for things like
  /// progress messages, success messages, or just normal command output.
  ///
  /// The `message` argument is printed to the stderr in red by default.
  ///
  /// The `stackTrace` argument is the stack trace that will be printed if
  /// supplied.
  ///
  /// If the `emphasis` argument is true, it will cause the output message be
  /// printed in bold text. Defaults to false.
  ///
  /// The `color` argument will print the message in the supplied color instead
  /// of the default of red. Colors will not be printed if the output terminal
  /// doesn't support them.
  ///
  /// If `newline` is true, then a newline will be added after printing the
  /// status. Defaults to true.
  ///
  /// The `indent` argument specifies the number of spaces to indent the overall
  /// message. If wrapping is enabled in [outputPreferences], then the wrapped
  /// lines will be indented as well.
  ///
  /// If `hangingIndent` is specified, then any wrapped lines will be indented
  /// by this much more than the first line, if wrapping is enabled in
  /// [outputPreferences].
  ///
  /// If `wrap` is specified, then it overrides the
  /// `outputPreferences.wrapText` setting.
  void printStatus(
    String message, {
    bool emphasis,
    TerminalColor color,
    bool newline,
    int indent,
    int hangingIndent,
    bool wrap,
  });

  /// Use this for verbose tracing output. Users can turn this output on in order
  /// to help diagnose issues with the toolchain or with their setup.
  void printTrace(String message);

  /// Start an indeterminate progress display.
  ///
  /// The `message` argument is the message to display to the user.
  ///
  /// The `timeout` argument sets a duration after which an additional message
  /// may be shown saying that the operation is taking a long time. (Not all
  /// [Status] subclasses show such a message.) Set this to null if the
  /// operation can legitimately take an arbitrary amount of time (e.g. waiting
  /// for the user).
  ///
  /// The `progressId` argument provides an ID that can be used to identify
  /// this type of progress (e.g. `hot.reload`, `hot.restart`).
  ///
  /// The `progressIndicatorPadding` can optionally be used to specify spacing
  /// between the `message` and the progress indicator, if any.
  Status startProgress(
    String message, {
    @required Duration timeout,
    String progressId,
    bool multilineOutput = false,
    int progressIndicatorPadding = kDefaultStatusPadding,
  });

  /// Send an event to be emitted.
  ///
  /// Only surfaces a value in machine modes, Loggers may ignore this message in
  /// non-machine modes.
  void sendEvent(String name, [Map<String, dynamic> args]) { }
}

class StdoutLogger extends Logger {
  StdoutLogger({
    @required AnsiTerminal terminal,
    @required Stdio stdio,
    @required OutputPreferences outputPreferences,
    @required TimeoutConfiguration timeoutConfiguration,
  })
    : _stdio = stdio,
      _terminal = terminal,
      _timeoutConfiguration = timeoutConfiguration,
      _outputPreferences = outputPreferences;

  @override
  final AnsiTerminal _terminal;
  @override
  final OutputPreferences _outputPreferences;
  @override
  final TimeoutConfiguration _timeoutConfiguration;
  final Stdio _stdio;

  Status _status;

  @override
  bool get isVerbose => false;

  @override
  bool get supportsColor => _terminal.supportsColor;

  @override
  bool get hasTerminal => _stdio.stdinHasTerminal;

  @override
  void printError(
    String message, {
    StackTrace stackTrace,
    bool emphasis,
    TerminalColor color,
    int indent,
    int hangingIndent,
    bool wrap,
  }) {
    _status?.pause();
    message ??= '';
    message = wrapText(message,
      indent: indent,
      hangingIndent: hangingIndent,
      shouldWrap: wrap ?? _outputPreferences.wrapText,
      columnWidth: _outputPreferences.wrapColumn,
    );
    if (emphasis == true) {
      message = _terminal.bolden(message);
    }
    message = _terminal.color(message, color ?? TerminalColor.red);
    _stdio.stderr.writeln(message);
    if (stackTrace != null) {
      _stdio.stderr.writeln(stackTrace.toString());
    }
    _status?.resume();
  }

  @override
  void printStatus(
    String message, {
    bool emphasis,
    TerminalColor color,
    bool newline,
    int indent,
    int hangingIndent,
    bool wrap,
  }) {
    _status?.pause();
    message ??= '';
    message = wrapText(message,
      indent: indent,
      hangingIndent: hangingIndent,
      shouldWrap: wrap ?? _outputPreferences.wrapText,
      columnWidth: _outputPreferences.wrapColumn,
    );
    if (emphasis == true) {
      message = _terminal.bolden(message);
    }
    if (color != null) {
      message = _terminal.color(message, color);
    }
    if (newline != false) {
      message = '$message\n';
    }
    writeToStdOut(message);
    _status?.resume();
  }

  @protected
  void writeToStdOut(String message) {
    _stdio.stdout.write(message);
  }

  @override
  void printTrace(String message) { }

  @override
  Status startProgress(
    String message, {
    @required Duration timeout,
    String progressId,
    bool multilineOutput = false,
    int progressIndicatorPadding = kDefaultStatusPadding,
  }) {
    assert(progressIndicatorPadding != null);
    if (_status != null) {
      // Ignore nested progresses; return a no-op status object.
      return SilentStatus(
        timeout: timeout,
        onFinish: _clearStatus,
        timeoutConfiguration: _timeoutConfiguration
      )..start();
    }
    if (supportsColor) {
      _status = AnsiStatus(
        message: message,
        timeout: timeout,
        multilineOutput: multilineOutput,
        padding: progressIndicatorPadding,
        onFinish: _clearStatus,
        stdio: _stdio,
        timeoutConfiguration: _timeoutConfiguration,
      )..start();
    } else {
      _status = SummaryStatus(
        message: message,
        timeout: timeout,
        padding: progressIndicatorPadding,
        onFinish: _clearStatus,
        stdio: _stdio,
        timeoutConfiguration: _timeoutConfiguration,
      )..start();
    }
    return _status;
  }

  void _clearStatus() {
    _status = null;
  }

  @override
  void sendEvent(String name, [Map<String, dynamic> args]) { }
}

/// A [StdoutLogger] which replaces Unicode characters that cannot be printed to
/// the Windows console with alternative symbols.
///
/// By default, Windows uses either "Consolas" or "Lucida Console" as fonts to
/// render text in the console. Both fonts only have a limited character set.
/// Unicode characters, that are not available in either of the two default
/// fonts, should be replaced by this class with printable symbols. Otherwise,
/// they will show up as the unrepresentable character symbol '�'.
class WindowsStdoutLogger extends StdoutLogger {
  WindowsStdoutLogger({
    @required AnsiTerminal terminal,
    @required Stdio stdio,
    @required OutputPreferences outputPreferences,
    @required TimeoutConfiguration timeoutConfiguration,
  }) : super(
      terminal: terminal,
      stdio: stdio,
      outputPreferences: outputPreferences,
      timeoutConfiguration: timeoutConfiguration,
    );

  @override
  void writeToStdOut(String message) {
    // TODO(jcollins-g): wrong abstraction layer for this, move to [Stdio].
    _stdio.stdout.write(message
        .replaceAll('✗', 'X')
        .replaceAll('✓', '√')
    );
  }
}

class BufferLogger extends Logger {
  BufferLogger({
    @required AnsiTerminal terminal,
    @required OutputPreferences outputPreferences,
    TimeoutConfiguration timeoutConfiguration = const TimeoutConfiguration()
  }) : _outputPreferences = outputPreferences,
       _terminal = terminal,
       _timeoutConfiguration = timeoutConfiguration;

  @override
  final OutputPreferences _outputPreferences;

  @override
  final AnsiTerminal _terminal;

  @override
  final TimeoutConfiguration _timeoutConfiguration;

  @override
  bool get isVerbose => false;

  @override
  bool get supportsColor => _terminal.supportsColor;

  final StringBuffer _error = StringBuffer();
  final StringBuffer _status = StringBuffer();
  final StringBuffer _trace = StringBuffer();

  String get errorText => _error.toString();
  String get statusText => _status.toString();
  String get traceText => _trace.toString();

  @override
  bool get hasTerminal => false;

  @override
  void printError(
    String message, {
    StackTrace stackTrace,
    bool emphasis,
    TerminalColor color,
    int indent,
    int hangingIndent,
    bool wrap,
  }) {
    _error.writeln(_terminal.color(
      wrapText(message,
        indent: indent,
        hangingIndent: hangingIndent,
        shouldWrap: wrap ?? _outputPreferences.wrapText,
        columnWidth: _outputPreferences.wrapColumn,
      ),
      color ?? TerminalColor.red,
    ));
  }

  @override
  void printStatus(
    String message, {
    bool emphasis,
    TerminalColor color,
    bool newline,
    int indent,
    int hangingIndent,
    bool wrap,
  }) {
    if (newline != false) {
      _status.writeln(wrapText(message,
        indent: indent,
        hangingIndent: hangingIndent,
        shouldWrap: wrap ?? _outputPreferences.wrapText,
        columnWidth: _outputPreferences.wrapColumn,
      ));
    } else {
      _status.write(wrapText(message,
        indent: indent,
        hangingIndent: hangingIndent,
        shouldWrap: wrap ?? _outputPreferences.wrapText,
        columnWidth: _outputPreferences.wrapColumn,
      ));
    }
  }

  @override
  void printTrace(String message) => _trace.writeln(message);

  @override
  Status startProgress(
    String message, {
    @required Duration timeout,
    String progressId,
    bool multilineOutput = false,
    int progressIndicatorPadding = kDefaultStatusPadding,
  }) {
    assert(progressIndicatorPadding != null);
    printStatus(message);
    return SilentStatus(
      timeout: timeout,
      timeoutConfiguration: _timeoutConfiguration,

    )..start();
  }

  /// Clears all buffers.
  void clear() {
    _error.clear();
    _status.clear();
    _trace.clear();
  }

  @override
  void sendEvent(String name, [Map<String, dynamic> args]) { }
}

class VerboseLogger extends Logger {
  VerboseLogger(this.parent,  { @required Stopwatch stopwatch }) :
    _stopwatch = stopwatch ?? context.get<Stopwatch>() ??  Stopwatch() {
    _stopwatch.start();
  }

  final Logger parent;

  final Stopwatch _stopwatch;

  @override
  AnsiTerminal get _terminal => parent._terminal;

  @override
  OutputPreferences get _outputPreferences => parent._outputPreferences;

  @override
  TimeoutConfiguration get _timeoutConfiguration => parent._timeoutConfiguration;

  @override
  bool get isVerbose => true;

  @override
  void printError(
    String message, {
    StackTrace stackTrace,
    bool emphasis,
    TerminalColor color,
    int indent,
    int hangingIndent,
    bool wrap,
  }) {
    _emit(
      _LogType.error,
      wrapText(message,
        indent: indent,
        hangingIndent: hangingIndent,
        shouldWrap: wrap ?? _outputPreferences.wrapText,
        columnWidth: _outputPreferences.wrapColumn,
      ),
      stackTrace,
    );
  }

  @override
  void printStatus(
    String message, {
    bool emphasis,
    TerminalColor color,
    bool newline,
    int indent,
    int hangingIndent,
    bool wrap,
  }) {
    _emit(_LogType.status, wrapText(message,
      indent: indent,
      hangingIndent: hangingIndent,
      shouldWrap: wrap ?? _outputPreferences.wrapText,
      columnWidth: _outputPreferences.wrapColumn,
    ));
  }

  @override
  void printTrace(String message) {
    _emit(_LogType.trace, message);
  }

  @override
  Status startProgress(
    String message, {
    @required Duration timeout,
    String progressId,
    bool multilineOutput = false,
    int progressIndicatorPadding = kDefaultStatusPadding,
  }) {
    assert(progressIndicatorPadding != null);
    printStatus(message);
    final Stopwatch timer = Stopwatch()..start();
    return SilentStatus(
      timeout: timeout,
      timeoutConfiguration: _timeoutConfiguration,
      onFinish: () {
        String time;
        if (timeout == null || timeout > _timeoutConfiguration.fastOperation) {
          time = getElapsedAsSeconds(timer.elapsed);
        } else {
          time = getElapsedAsMilliseconds(timer.elapsed);
        }
        if (timeout != null && timer.elapsed > timeout) {
          printTrace('$message (completed in $time, longer than expected)');
        } else {
          printTrace('$message (completed in $time)');
        }
      },
    )..start();
  }

  void _emit(_LogType type, String message, [ StackTrace stackTrace ]) {
    if (message.trim().isEmpty) {
      return;
    }

    final int millis = _stopwatch.elapsedMilliseconds;
    _stopwatch.reset();

    String prefix;
    const int prefixWidth = 8;
    if (millis == 0) {
      prefix = ''.padLeft(prefixWidth);
    } else {
      prefix = '+$millis ms'.padLeft(prefixWidth);
      if (millis >= 100) {
        prefix = _terminal.bolden(prefix);
      }
    }
    prefix = '[$prefix] ';

    final String indent = ''.padLeft(prefix.length);
    final String indentMessage = message.replaceAll('\n', '\n$indent');

    if (type == _LogType.error) {
      parent.printError(prefix + _terminal.bolden(indentMessage));
      if (stackTrace != null) {
        parent.printError(indent + stackTrace.toString().replaceAll('\n', '\n$indent'));
      }
    } else if (type == _LogType.status) {
      parent.printStatus(prefix + _terminal.bolden(indentMessage));
    } else {
      parent.printStatus(prefix + indentMessage);
    }
  }

  @override
  void sendEvent(String name, [Map<String, dynamic> args]) { }

  @override
  bool get supportsColor => parent.supportsColor;

  @override
  bool get hasTerminal => parent.hasTerminal;
}

enum _LogType { error, status, trace }

typedef SlowWarningCallback = String Function();

/// A [Status] class begins when start is called, and may produce progress
/// information asynchronously.
///
/// Some subclasses change output once [timeout] has expired, to indicate that
/// something is taking longer than expected.
///
/// The [SilentStatus] class never has any output.
///
/// The [AnsiSpinner] subclass shows a spinner, and replaces it with a single
/// space character when stopped or canceled.
///
/// The [AnsiStatus] subclass shows a spinner, and replaces it with timing
/// information when stopped. When canceled, the information isn't shown. In
/// either case, a newline is printed.
///
/// The [SummaryStatus] subclass shows only a static message (without an
/// indicator), then updates it when the operation ends.
///
/// Generally, consider `logger.startProgress` instead of directly creating
/// a [Status] or one of its subclasses.
abstract class Status {
  Status({
    @required this.timeout,
    @required TimeoutConfiguration timeoutConfiguration,
    this.onFinish,
  }) : _timeoutConfiguration = timeoutConfiguration;

  /// A [SilentStatus] or an [AnsiSpinner] (depending on whether the
  /// terminal is fancy enough), already started.
  factory Status.withSpinner({
    @required Duration timeout,
    @required TimeoutConfiguration timeoutConfiguration,
    VoidCallback onFinish,
    SlowWarningCallback slowWarningCallback,
  }) {
    if (globals.terminal.supportsColor) {
      return AnsiSpinner(
        timeout: timeout,
        onFinish: onFinish,
        slowWarningCallback: slowWarningCallback,
        timeoutConfiguration: timeoutConfiguration,
      )..start();
    }
    return SilentStatus(
      timeout: timeout,
      onFinish: onFinish,
      timeoutConfiguration: timeoutConfiguration,
    )..start();
  }

  final Duration timeout;
  final VoidCallback onFinish;
  final TimeoutConfiguration _timeoutConfiguration;

  @protected
  final Stopwatch _stopwatch = context.get<Stopwatch>() ?? Stopwatch();

  @protected
  @visibleForTesting
  bool get seemsSlow => timeout != null && _stopwatch.elapsed > timeout;

  @protected
  String get elapsedTime {
    if (timeout == null || timeout > _timeoutConfiguration.fastOperation) {
      return getElapsedAsSeconds(_stopwatch.elapsed);
    }
    return getElapsedAsMilliseconds(_stopwatch.elapsed);
  }

  /// Call to start spinning.
  void start() {
    assert(!_stopwatch.isRunning);
    _stopwatch.start();
  }

  /// Call to stop spinning after success.
  void stop() {
    finish();
  }

  /// Call to cancel the spinner after failure or cancellation.
  void cancel() {
    finish();
  }

  /// Call to clear the current line but not end the progress.
  void pause() { }

  /// Call to resume after a pause.
  void resume() { }

  @protected
  void finish() {
    assert(_stopwatch.isRunning);
    _stopwatch.stop();
    if (onFinish != null) {
      onFinish();
    }
  }
}

/// A [SilentStatus] shows nothing.
class SilentStatus extends Status {
  SilentStatus({
    @required Duration timeout,
    @required TimeoutConfiguration timeoutConfiguration,
    VoidCallback onFinish,
  }) : super(
    timeout: timeout,
    onFinish: onFinish,
    timeoutConfiguration: timeoutConfiguration,
  );
}

/// Constructor writes [message] to [stdout].  On [cancel] or [stop], will call
/// [onFinish]. On [stop], will additionally print out summary information.
class SummaryStatus extends Status {
  SummaryStatus({
    this.message = '',
    @required Duration timeout,
    this.padding = kDefaultStatusPadding,
    VoidCallback onFinish,
    Stdio stdio,
    @required TimeoutConfiguration timeoutConfiguration,
  }) : assert(message != null),
       assert(padding != null),
       _stdio = stdio ?? globals.stdio,
       super(timeout: timeout, onFinish: onFinish, timeoutConfiguration: timeoutConfiguration);

  final String message;
  final int padding;
  final Stdio _stdio;

  bool _messageShowingOnCurrentLine = false;

  @override
  void start() {
    _printMessage();
    super.start();
  }

  void _printMessage() {
    assert(!_messageShowingOnCurrentLine);
    _stdio.stdout.write('${message.padRight(padding)}     ');
    _messageShowingOnCurrentLine = true;
  }

  @override
  void stop() {
    if (!_messageShowingOnCurrentLine) {
      _printMessage();
    }
    super.stop();
    writeSummaryInformation();
    _stdio.stdout.write('\n');
  }

  @override
  void cancel() {
    super.cancel();
    if (_messageShowingOnCurrentLine) {
      _stdio.stdout.write('\n');
    }
  }

  /// Prints a (minimum) 8 character padded time.
  ///
  /// If [timeout] is less than or equal to [kFastOperation], the time is in
  /// seconds; otherwise, milliseconds. If the time is longer than [timeout],
  /// appends "(!)" to the time.
  ///
  /// Examples: `    0.5s`, `   150ms`, ` 1,600ms`, `    3.1s (!)`
  void writeSummaryInformation() {
    assert(_messageShowingOnCurrentLine);
    _stdio.stdout.write(elapsedTime.padLeft(_kTimePadding));
    if (seemsSlow) {
      _stdio.stdout.write(' (!)');
    }
  }

  @override
  void pause() {
    super.pause();
    _stdio.stdout.write('\n');
    _messageShowingOnCurrentLine = false;
  }
}

/// An [AnsiSpinner] is a simple animation that does nothing but implement a
/// terminal spinner. When stopped or canceled, the animation erases itself.
///
/// If the timeout expires, a customizable warning is shown (but the spinner
/// continues otherwise unabated).
class AnsiSpinner extends Status {
  AnsiSpinner({
    @required Duration timeout,
    VoidCallback onFinish,
    this.slowWarningCallback,
    Stdio stdio,
    @required TimeoutConfiguration timeoutConfiguration,
  }) : _stdio = stdio ?? globals.stdio,
       super(timeout: timeout, onFinish: onFinish, timeoutConfiguration: timeoutConfiguration);

  final String _backspaceChar = '\b';
  final String _clearChar = ' ';
  final Stdio _stdio;

  bool timedOut = false;

  int ticks = 0;
  Timer timer;

  // Windows console font has a limited set of Unicode characters.
  List<String> get _animation => globals.platform.isWindows
      ? <String>[r'-', r'\', r'|', r'/']
      : <String>['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'];

  static const String _defaultSlowWarning = '(This is taking an unexpectedly long time.)';
  final SlowWarningCallback slowWarningCallback;

  String _slowWarning = '';

  String get _currentAnimationFrame => _animation[ticks % _animation.length];
  int get _currentLength => _currentAnimationFrame.length + _slowWarning.length;
  String get _backspace => _backspaceChar * (spinnerIndent + _currentLength);
  String get _clear => _clearChar *  (spinnerIndent + _currentLength);

  @protected
  int get spinnerIndent => 0;

  @override
  void start() {
    super.start();
    assert(timer == null);
    _startSpinner();
  }

  void _startSpinner() {
    _stdio.stdout.write(_clear); // for _callback to backspace over
    timer = Timer.periodic(const Duration(milliseconds: 100), _callback);
    _callback(timer);
  }

  void _callback(Timer timer) {
    assert(this.timer == timer);
    assert(timer != null);
    assert(timer.isActive);
    _stdio.stdout.write(_backspace);
    ticks += 1;
    if (seemsSlow) {
      if (!timedOut) {
        timedOut = true;
        _stdio.stdout.write('$_clear\n');
      }
      if (slowWarningCallback != null) {
        _slowWarning = slowWarningCallback();
      } else {
        _slowWarning = _defaultSlowWarning;
      }
      _stdio.stdout.write(_slowWarning);
    }
    _stdio.stdout.write('${_clearChar * spinnerIndent}$_currentAnimationFrame');
  }

  @override
  void finish() {
    assert(timer != null);
    assert(timer.isActive);
    timer.cancel();
    timer = null;
    _clearSpinner();
    super.finish();
  }

  void _clearSpinner() {
    _stdio.stdout.write('$_backspace$_clear$_backspace');
  }

  @override
  void pause() {
    assert(timer != null);
    assert(timer.isActive);
    _clearSpinner();
    timer.cancel();
  }

  @override
  void resume() {
    assert(timer != null);
    assert(!timer.isActive);
    _startSpinner();
  }
}

const int _kTimePadding = 8; // should fit "99,999ms"

/// Constructor writes [message] to [stdout] with padding, then starts an
/// indeterminate progress indicator animation (it's a subclass of
/// [AnsiSpinner]).
///
/// On [cancel] or [stop], will call [onFinish]. On [stop], will
/// additionally print out summary information.
class AnsiStatus extends AnsiSpinner {
  AnsiStatus({
    this.message = '',
    @required Duration timeout,
    this.multilineOutput = false,
    this.padding = kDefaultStatusPadding,
    VoidCallback onFinish,
    Stdio stdio,
    TimeoutConfiguration timeoutConfiguration,
  }) : assert(message != null),
       assert(multilineOutput != null),
       assert(padding != null),
       super(timeout: timeout, onFinish: onFinish, stdio: stdio, timeoutConfiguration: timeoutConfiguration);

  final String message;
  final bool multilineOutput;
  final int padding;

  static const String _margin = '     ';

  @override
  int get spinnerIndent => _kTimePadding - 1;

  int _totalMessageLength;

  @override
  void start() {
    _startStatus();
    super.start();
  }

  void _startStatus() {
    final String line = '${message.padRight(padding)}$_margin';
    _totalMessageLength = line.length;
    _stdio.stdout.write(line);
  }

  @override
  void stop() {
    super.stop();
    writeSummaryInformation();
    _stdio.stdout.write('\n');
  }

  @override
  void cancel() {
    super.cancel();
    _stdio.stdout.write('\n');
  }

  /// Print summary information when a task is done.
  ///
  /// If [multilineOutput] is false, replaces the spinner with the summary message.
  ///
  /// If [multilineOutput] is true, then it prints the message again on a new
  /// line before writing the elapsed time.
  void writeSummaryInformation() {
    if (multilineOutput) {
      _stdio.stdout.write('\n${'$message Done'.padRight(padding)}$_margin');
    }
    _stdio.stdout.write(elapsedTime.padLeft(_kTimePadding));
    if (seemsSlow) {
      _stdio.stdout.write(' (!)');
    }
  }

  void _clearStatus() {
    _stdio.stdout.write('${_backspaceChar * _totalMessageLength}${_clearChar * _totalMessageLength}${_backspaceChar * _totalMessageLength}');
  }

  @override
  void pause() {
    super.pause();
    _clearStatus();
  }

  @override
  void resume() {
    _startStatus();
    super.resume();
  }
}
