import "package:burt_network/burt_network.dart";

import "antenna.dart";
import "rtk_reader.dart";

final logger = BurtLogger();

class BaseStationCollection extends Service {
  // TODO: Add Device.BASE_STATION
  late final server = RoverSocket(port: 8005, device: Device.ARM, collection: this);

  final rtk = RTKReader();
  final antenna = AntennaControl();

  @override
  Future<bool> init() async {
    bool result = true;
    result &= await server.init();
    result &= await rtk.init();
    result &= await antenna.init();

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
    await rtk.dispose();
    await antenna.dispose();
  }
}

final collection = BaseStationCollection();
