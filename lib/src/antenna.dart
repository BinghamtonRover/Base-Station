import "package:burt_network/burt_network.dart";

import "collection.dart";

// TODO: Add AntennaCommand, AntennaData, and Device.ANTENNA to burt_network

class AntennaControl extends Service {
  /// Serial port for the firmware
  static const port = "/dev/base-station-antenna";

  /// Firmware for the antenna
  final firmware = BurtFirmwareSerial(port: port, logger: logger);

  final BaseStationCommand _currentCommand = BaseStationCommand();

  @override
  Future<bool> init() async {
    final result = firmware.init();
    firmware.messages.listen(collection.server.sendWrapper);  // send AntennaData to the Dashboard
    collection.server.messages.onMessage<BaseStationCommand>(
      name: BaseStationCommand().messageName,
      constructor: BaseStationCommand.fromBuffer,
       callback: _handleBaseStationCommand,
    );
    collection.server.messages.onMessage<GpsCoordinates>(
      name: GpsCoordinates().messageName,
      constructor: GpsCoordinates.fromBuffer,
      callback: _handleGpsData,
    );
    return result;
  }

  @override
  Future<void> dispose() => firmware.dispose();

  void _handleBaseStationCommand(BaseStationCommand command) {
    // handshake back to dashboard
    collection.server.sendMessage(command);

    _currentCommand.mergeFromMessage(command);

    // TODO: Implement logic and stuff
  }

  void _handleGpsData(GpsCoordinates coordinates) {
    if (_currentCommand.mode != AntennaControlMode.TRACK_ROVER) {
      return;
    }
  }
}
