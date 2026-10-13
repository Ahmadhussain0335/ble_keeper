import 'dart:typed_data';

/// Reads the ESP32 test counter: uint32 little-endian in the first 4 bytes.
/// Returns null when the payload is shorter.
int? parseCounter(Uint8List bytes) {
  if (bytes.length < 4) return null;
  return ByteData.sublistView(bytes).getUint32(0, Endian.little);
}

/// Counts missed values of a counter that increments by one per message.
///
/// The test device keeps counting while disconnected, so after a reconnect
/// the jump shows how many values were missed. A lower value means the
/// device rebooted (the counter lives in RAM) and is counted as a reset, not
/// a gap. Wrap-around at 2^32 is handled.
class GapDetector {
  static const int _range = 0x100000000;

  /// Values above this followed by small values are treated as a wrap.
  static const int _wrapWindow = 1000;

  int? _last;
  int _missed = 0;
  int _received = 0;
  int _resets = 0;

  int? get last => _last;
  int get missed => _missed;
  int get received => _received;
  int get resets => _resets;

  /// Records [value] and returns how many values were missed before it.
  int add(int value) {
    _received++;
    final last = _last;
    _last = value;
    if (last == null || value == last) return 0;
    int gap;
    if (value > last) {
      gap = value - last - 1;
    } else if (last >= _range - _wrapWindow && value < _wrapWindow) {
      gap = value + _range - last - 1;
    } else {
      _resets++;
      return 0;
    }
    _missed += gap;
    return gap;
  }

  void reset() {
    _last = null;
    _missed = 0;
    _received = 0;
    _resets = 0;
  }
}
