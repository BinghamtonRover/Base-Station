import "dart:io";
import "dart:typed_data";

import "package:burt_network/burt_network.dart";

import "collection.dart";

final subsystemsSocket = SocketInfo(address: InternetAddress("192.168.1.20"), port: 8001);

class GpsReader extends Service {
  static const portName = "/dev/base-station-gps";
  static const readInterval = Duration(seconds: 1);

  late final serial = SerialDevice(portName: portName, readInterval: readInterval, logger: logger);

  @override
  Future<bool> init() async {
    final result = await serial.init();
    serial.stream.listen(_handlePacket);
    serial.startListening();
    return result;
  }

  @override
  Future<void> dispose() async {
    await serial.dispose();
  }

  void _handlePacket(Uint8List packet) {
    // TODO: Parse RTCM packet and send to the Subsystems
    final message = GpsCoordinates(/* TODO: Add rtcm to this packet */);
    collection.server.sendMessage(message, destination: subsystemsSocket);
  }
}
