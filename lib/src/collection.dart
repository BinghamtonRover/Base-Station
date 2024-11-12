import "package:burt_network/burt_network.dart";

import "gps.dart";

final logger = BurtLogger();

class BaseStationCollection extends Service {
  // TODO: Add Device.BASE_STATION
  late final server = RoverSocket(port: 8005, device: Device.ARM, collection: this);

  final gps = GpsReader();

  @override
  Future<bool> init() async {
    bool result = true;
    result &= await server.init();
    result &= await gps.init();

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
  }
}

final collection = BaseStationCollection();
