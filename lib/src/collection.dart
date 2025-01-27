import "dart:math";

import "package:burt_network/burt_network.dart";

import "antenna.dart";
import "gps.dart";

final logger = BurtLogger();

class BaseStationCollection extends Service {
  late final server = RoverSocket(port: 8005, device: Device.BASE_STATION, collection: this);

  // Manually input these when setting up the base station, look into having this be done from an external source?
  static final GpsCoordinates stationCoordinates = GpsCoordinates(
    latitude: 0,
    longitude: 0,
  );

  static const double angleTolerance = 5 * (pi / 180);

  final gps = GpsReader();
  final antenna = AntennaControl();

  @override
  Future<bool> init() async {
    bool result = true;
    result &= await server.init();
    result &= await gps.init();
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
    await gps.dispose();
    await antenna.dispose();
  }
}

final collection = BaseStationCollection();
