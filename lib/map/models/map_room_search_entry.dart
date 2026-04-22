import 'package:equatable/equatable.dart';
import 'package:rtu_mirea_app/map/models/campus_model.dart';
import 'package:rtu_mirea_app/map/models/floor_model.dart';

class MapRoomSearchEntry extends Equatable {
  const MapRoomSearchEntry({
    required this.roomId,
    required this.name,
    required this.campus,
    required this.floor,
  });

  final String roomId;
  final String name;
  final CampusModel campus;
  final FloorModel floor;

  @override
  List<Object?> get props => <Object?>[roomId, name, campus, floor];
}
