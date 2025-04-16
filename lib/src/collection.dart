import "dart:async";

import "package:burt_network/burt_network.dart";

import "antenna.dart";
import "gps.dart";

final logger = BurtLogger();

class BaseStationCollection extends Service {
  late final server = RoverSocket(port: 8005, device: Device.BASE_STATION, collection: this);

  final gps = GpsReader();
  final antenna = AntennaControl();

  /// Timer to periodically send the base station data
  Timer? dataSendTimer;

  /// Getter for the current [BaseStationData] to send over the network
  BaseStationData get dataMessage => BaseStationData(
    antenna: antenna.firmwareData,
    mode: antenna.controlMode,
    version: Version(major: 1, minor: 0),
  );

  @override
  Future<bool> init() async {
    bool result = true;
    result &= await server.init();
    result &= await gps.init();
    result &= await antenna.init();

    dataSendTimer = Timer.periodic(const Duration(milliseconds: 100), sendData);

    if (result) {
      logger.info("Base Station ready");
    } else {
      logger.warning("Could not start base station");
    }

    return result;
  }

  @override
  Future<void> dispose() async {
    await server.dispose();
    await gps.dispose();
    await antenna.dispose();
    dataSendTimer?.cancel();
  }

  /// Sends the state of the base station over the network
  void sendData([_]) => server.sendMessage(dataMessage);
}

final collection = BaseStationCollection();
