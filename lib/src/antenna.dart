import "dart:async";
import "dart:io";
import "dart:math";

import "package:burt_network/burt_network.dart";

import "collection.dart";

/// Receives base station commands and translate it into appropriate commands for
/// the antenna firmware
/// 
/// This also handles the logic for "auto tracking" the antenna to point towards the rover.
class AntennaControl extends Service {
  /// Firmware for the antenna
  BurtFirmwareSerial? firmware;

  BaseStationCommand _currentCommand = BaseStationCommand();

  final AntennaFirmwareData _firmwareData = AntennaFirmwareData();

  StreamSubscription<AntennaFirmwareData>? _firmwareSubscription;
  StreamSubscription<BaseStationCommand>? _commandSubscription;
  StreamSubscription<GpsCoordinates>? _coordinatesSubscription;

  @override
  Future<bool> init() async {
    final rtkPort = (await Process.run("realpath", ["/dev/rtk_gps"])).stdout.trim();
    final validPorts = DelegateSerialPort.allPorts.toSet().difference({rtkPort});

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
    _commandSubscription = collection.server.messages.onMessage<BaseStationCommand>(
      name: BaseStationCommand().messageName,
      constructor: BaseStationCommand.fromBuffer,
      callback: _handleBaseStationCommand,
    );
    _coordinatesSubscription = collection.server.messages.onMessage<GpsCoordinates>(
      name: GpsCoordinates().messageName,
      constructor: GpsCoordinates.fromBuffer,
      callback: _handleGpsData,
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
    } else if (command.hasRoverCoordinatesOverrideOverride() &&
        command.mode == AntennaControlMode.TRACK_ROVER) {
      _handleGpsData(command.roverCoordinatesOverrideOverride, true);
    }
  }

  void _handleGpsData(GpsCoordinates coordinates, [bool isRoverOverride = false]) {
    if (_currentCommand.mode != AntennaControlMode.TRACK_ROVER) {
      return;
    }

    if (_currentCommand.hasRoverCoordinatesOverrideOverride() && !isRoverOverride) {
      return;
    }

    final stationCoordinates =
        _currentCommand.hasBaseStationCoordinatesOverride()
            ? _currentCommand.baseStationCoordinatesOverride
            : BaseStationCollection.stationCoordinates;
    final baseStationMeters = stationCoordinates.inMeters;
    final roverMeters = coordinates.inMeters;

    final (deltaX, deltaY) = (
      roverMeters.lat - baseStationMeters.lat,
      roverMeters.long - baseStationMeters.long,
    );

    final angle = atan2(deltaY, deltaX);

    var targetDiff = angle - _firmwareData.swivel.targetAngle;

    if (targetDiff < -pi) {
      targetDiff += 2 * pi;
    } else if (targetDiff > pi) {
      targetDiff -= 2 * pi;
    }

    if (targetDiff.abs() < BaseStationCollection.angleTolerance) {
      logger.debug(
        "Ignoring GPS Data",
        body: "Antenna is already within the angle tolerance",
      );
      return;
    }

    firmware?.sendMessage(
      AntennaFirmwareCommand(
        swivel: MotorCommand(angle: angle),
      ),
    );
  }
}
