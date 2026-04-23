import 'package:equatable/equatable.dart';
import 'package:rtu_mirea_app/map/models/campus_model.dart';
import 'package:rtu_mirea_app/map/models/floor_model.dart';

enum MapObjectType { room, canteen, toilet, entranceExit }

MapObjectType? mapObjectTypeFromRawValue(String value) {
  return switch (value) {
    'room' => MapObjectType.room,
    'canteen' => MapObjectType.canteen,
    'toilet' => MapObjectType.toilet,
    'entrance' || 'exit' || 'entrance_exit' => MapObjectType.entranceExit,
    _ => null,
  };
}

class MapRoomSearchEntry extends Equatable {
  const MapRoomSearchEntry({
    required this.roomId,
    required this.name,
    required this.objectType,
    required this.campus,
    required this.floor,
  });

  final String roomId;
  final String name;
  final MapObjectType objectType;
  final CampusModel campus;
  final FloorModel floor;

  @override
  List<Object?> get props => <Object?>[roomId, name, objectType, campus, floor];
}
