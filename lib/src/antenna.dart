import "dart:math";

import "package:burt_network/burt_network.dart";

import "collection.dart";

class AntennaControl extends Service {
  /// Serial port for the firmware
  static const port = "/dev/base-station-antenna";

  /// Firmware for the antenna
  final firmware = BurtFirmwareSerial(port: port, logger: logger);

  BaseStationCommand _currentCommand = BaseStationCommand();

  final AntennaFirmwareData _firmwareData = AntennaFirmwareData();

  @override
  Future<bool> init() async {
    final result = firmware.init();
    firmware.messages.listen((message) {
      collection.server.sendWrapper(message);
      if (message.name == AntennaFirmwareData().messageName) {
        _firmwareData.mergeFromBuffer(message.data);
      }
    });
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

    _currentCommand = command;

    switch (command.mode) {
      case AntennaControlMode.ANTENNA_CONTROL_MODE_UNDEFINED:
        firmware.sendMessage(AntennaFirmwareCommand(stop: true));
      case AntennaControlMode.MANUAL_CONTROL:
        firmware.sendMessage(command.manualCommand);
      case AntennaControlMode.TRACK_ROVER:
        break;
    }

    if (command.hasRoverCoordinatesOverrideOverride()) {
      _handleGpsData(command.roverCoordinatesOverrideOverride, true);
    }
  }

  void _handleGpsData(GpsCoordinates coordinates, [bool isRoverOverride = false]) {
    if (_currentCommand.mode != AntennaControlMode.TRACK_ROVER) {
      return;
    }

    if (_currentCommand.hasRoverCoordinatesOverrideOverride() &&
        !isRoverOverride) {
      return;
    }

    final stationCoordinates =
        _currentCommand.hasBaseStationCoordinatesOverride()
            ? _currentCommand.baseStationCoordinatesOverride
            : BaseStationCollection.stationCoordinates;
    final baseStationMeters = stationCoordinates.inMeters;
    final roverMeters = coordinates.inMeters;

    final (deltaX, deltaY) = (
      baseStationMeters.lat - roverMeters.lat,
      baseStationMeters.long - roverMeters.long,
    );

    final angle = atan2(deltaY, deltaX) - pi;

    var targetDiff = angle - _firmwareData.swivel.targetAngle;

    if (targetDiff < -pi) {
      targetDiff += 2 * pi;
    } else if (targetDiff > pi) {
      targetDiff -= 2 * pi;
    }

    if (targetDiff.abs() < BaseStationCollection.angleTolerance * pi / 180) {
      logger.debug(
        "Ignoring GPS Data",
        body: "Antenna is already within the angle tolerance",
      );
      return;
    }

    firmware.sendMessage(
      AntennaFirmwareCommand(
        swivel: MotorCommand(angle: angle),
      ),
    );
  }
}
