import "package:base_station/src/rtk_reader.dart";

void main() async {
  final reader = RTKReader();
  await reader.init();
}
