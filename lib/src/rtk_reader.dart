import "dart:async";
import "dart:io";

import "package:base_station/base_station.dart";
import "package:burt_network/burt_network.dart";

final subsystemsSocket = SocketInfo(address: InternetAddress("192.168.1.20"), port: 8001);

class RTKReader extends Service {
  static const rtkPort = "COM11";

  static const _first = 0xD3;

  final logger = BurtLogger();

  late final SerialDevice serial = SerialDevice(
    portName: rtkPort,
    readInterval: const Duration(milliseconds: 10),
    logger: logger,
  );

  final List<int> _buffer = [];

  StreamSubscription<List<int>>? _subscription;

  void _handlePacket(List<int> bytes) {
    _buffer.addAll(bytes);

    if (!_buffer.contains(_first)) {
      _buffer.clear();
      return;
    }
    _buffer.removeRange(0, _buffer.indexOf(_first));
    if (_buffer.length < 2) {
      // Wait for more bytes to come in
      return;
    }

    // buffer[1] != 0b000000
    if (_buffer[1] & ~0x03 != 0) {
      _buffer.removeRange(0, 2);
      return;
    }

    if (_buffer.length < 4) {
      // wait for more bytes to come in
      return;
    }

    final size = (_buffer[1] << 8) | _buffer[2];

    if (_buffer.length < size + 3) {
      // wait for the payload to come in
      return;
    }

    if (_buffer.length < 3 + size + 3 + 1) {
      // wait for the crc
      return;
    }

    final endIndex = 3 + size + 3;

    final List<int> fullPacket = _buffer.sublist(0, endIndex + 1);

    _buffer.removeRange(0, endIndex + 1);

    logger.info("Got RTK Message!");

    final message = RoverPosition(rtkMessage: fullPacket);

    collection.server.sendMessage(message, destination: subsystemsSocket);
  }

  @override
  Future<bool> init() async {
    if (!await serial.init()) {
      logger.warning("could not open RTK on $rtkPort");
      return false;
    }

    serial.startListening();
    _subscription = serial.stream.listen(_handlePacket);
    return true;
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await serial.dispose();
  }
}
