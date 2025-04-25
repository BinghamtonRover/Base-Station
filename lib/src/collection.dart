import "dart:async";

import "package:burt_network/burt_network.dart";

import "antenna.dart";
import "rtk_reader.dart";

/// Logger for the base station program
final logger = BurtLogger();

/// All resources necessary to run the Base Station program
class BaseStationCollection extends Service {
  /// The server for the Base Station program
  late final server = RoverSocket(
    port: 8005,
    device: Device.BASE_STATION,
    collection: this,
  );

  /// The RTK GPS reader for the Base Station
  final rtk = RTKReader();

  /// The antenna control service to handle incoming commands
  /// and outgoing firmware messages
  final antenna = AntennaControl();

  /// Timer to periodically send the base station data
  Timer? dataSendTimer;

  /// Getter for the current [BaseStationData] to send over the network
  BaseStationData get dataMessage => BaseStationData(
    antenna: antenna.firmwareData,
    mode: antenna.controlMode,
    rtkConnected: rtk.isConnected ? BoolState.YES : BoolState.NO,
    version: Version(major: 1, minor: 0),
  );

  @override
  Future<bool> init() async {
    bool result = true;
    logger.socket = server;

    result &= await server.init();
    result &= await rtk.init();
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
    await rtk.dispose();
    await antenna.dispose();
    dataSendTimer?.cancel();
  }

  /// Sends the state of the base station over the network
  void sendData([_]) => server.sendMessage(dataMessage);
}

/// The collection of all the Base Station's resources
final collection = BaseStationCollection();
