import "dart:async";
import "dart:io";
import "dart:math";

import "package:base_station/base_station.dart";
import "package:burt_network/burt_network.dart";

/// Receives base station commands and translate it into appropriate commands for
/// the antenna firmware
///
/// This also handles the logic for "auto tracking" the antenna to point towards the rover.
class AntennaControl extends Service {
  /// Firmware for the antenna
  BurtFirmwareSerial? firmware;

  BaseStationCommand _currentCommand = BaseStationCommand();

  final AntennaFirmwareData _firmwareData = AntennaFirmwareData();

  /// The last data received from the firmware
  AntennaFirmwareData get firmwareData => _firmwareData;

  /// The control mode of the antenna
  AntennaControlMode get controlMode => _currentCommand.mode;

  StreamSubscription<AntennaFirmwareData>? _firmwareSubscription;
  StreamSubscription<BaseStationCommand>? _commandSubscription;
  StreamSubscription<RoverPosition>? _coordinatesSubscription;

  @override
  Future<bool> init() async {
    final rtkPort =
        (Platform.isWindows)
            ? ""
            : (await Process.run("realpath", ["/dev/rover_gps"])).stdout.trim();
    final validPorts = DelegateSerialPort.allPorts.toSet().difference({
      rtkPort,
    });

    for (final port in validPorts) {
      final firmwareCandidate = BurtFirmwareSerial(port: port, logger: logger);
      if (await firmwareCandidate.init() &&
          firmwareCandidate.isReady &&
          firmwareCandidate.device == Device.ANTENNA) {
        firmware = firmwareCandidate;
        break;
      } else {
        await firmwareCandidate.dispose();
      }
    }
    if (firmware == null) {
      return false;
    }
    _firmwareSubscription = firmware?.messages.onMessage(
      name: AntennaFirmwareData().messageName,
      constructor: AntennaFirmwareData.fromBuffer,
      callback: (message) {
        collection.server.sendMessage(message);
        _firmwareData.mergeFromMessage(message);
      },
    );
    _commandSubscription = collection.server.messages.onMessage(
      name: BaseStationCommand().messageName,
      constructor: BaseStationCommand.fromBuffer,
      callback: _handleBaseStationCommand,
    );
    _coordinatesSubscription = collection.server.messages.onMessage(
      name: RoverPosition().messageName,
      constructor: RoverPosition.fromBuffer,
      callback: (position) {
        if (!position.hasGps()) {
          return;
        }
        _handleGpsData(position.gps);
      },
    );
    return true;
  }

  @override
  Future<void> dispose() async {
    await _firmwareSubscription?.cancel();
    await _commandSubscription?.cancel();
    await _coordinatesSubscription?.cancel();
    await firmware?.dispose();
    // prevent possible "false success" if init() is called again
    firmware = null;
  }

  void _handleBaseStationCommand(BaseStationCommand command) {
    // handshake back to dashboard
    collection.server.sendMessage(command);

    _currentCommand = command;

    if (command.hasManualCommand() &&
        command.mode == AntennaControlMode.MANUAL_CONTROL) {
      firmware?.sendMessage(command.manualCommand);
    } else if (command.hasRoverCoordinatesOverride() &&
        command.mode == AntennaControlMode.TRACK_ROVER) {
      _handleGpsData(command.roverCoordinatesOverride, true);
    }
  }

  void _handleGpsData(
    GpsCoordinates coordinates, [
    bool isRoverOverride = false,
  ]) {
    if (_currentCommand.mode != AntennaControlMode.TRACK_ROVER) {
      return;
    }

    if (!_currentCommand.hasBaseStationCoordinates()) {
      logger.warning(
        "Insufficient data for auto tracking",
        body: "No base station coordinates were provided",
      );
      return;
    } else if (!_currentCommand.hasAngleTolerance()) {
      logger.warning(
        "Insufficient data for auto tracking",
        body: "No angle tolerance was provided",
      );
      return;
    }

    if (_currentCommand.hasRoverCoordinatesOverride() && !isRoverOverride) {
      return;
    }

    final stationCoordinates = _currentCommand.baseStationCoordinates;
    final baseStationMeters = stationCoordinates.toUTM();
    final roverMeters = coordinates.toUTM();

    final delta = roverMeters - baseStationMeters;

    final angle = atan2(delta.y, delta.x);

    var targetDiff = angle - _firmwareData.swivel.currentAngle;

    if (targetDiff < -pi) {
      targetDiff += 2 * pi;
    } else if (targetDiff > pi) {
      targetDiff -= 2 * pi;
    }

    if (targetDiff.abs() < _currentCommand.angleTolerance) {
      logger.debug(
        "Ignoring GPS Data",
        body: "Antenna is already within the angle tolerance",
      );
      return;
    }

    firmware?.sendMessage(
      AntennaFirmwareCommand(
        swivel: MotorCommand(angle: angle),
        version: _currentCommand.version,
      ),
    );
  }
}
