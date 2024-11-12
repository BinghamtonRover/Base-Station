import "package:burt_network/burt_network.dart";

import "collection.dart";

// TODO: Add AntennaCommand, AntennaData, and Device.ANTENNA to burt_network

class AntennaControl extends Service {
  static const port = "/dev/base-station-antenna";

  final firmware = BurtFirmwareSerial(port: port, logger: logger);

  @override
  Future<bool> init() async {
    final result = firmware.init();
    firmware.messages.listen(collection.server.sendWrapper);  // send AntennaData to the Dashboard
    // collection.server.messages.onMessage<AntennaCommand>(
    //   name: AntennaCommand().messageName,
    //   constructor: AntennaCommand.fromBuffer,
    //    callback: _handleAntennaCommand,
    // );
    return result;
  }

  @override
  Future<void> dispose() => firmware.dispose();

  // void _handleAntennaCommand(AntennaCommand command) => firmware.sendMessage(command);
}
