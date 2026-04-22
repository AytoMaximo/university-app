import 'dart:ui';

import 'package:rtu_mirea_app/map/models/room_model.dart';

RoomModel? findRoomAtPoint({
  required List<RoomModel> rooms,
  required Offset point,
}) {
  final List<RoomModel> containingRooms = _roomsContainingPoint(
    rooms: rooms,
    point: point,
  );
  if (containingRooms.isEmpty) {
    return null;
  }

  return _nearestRoomToPoint(rooms: containingRooms, point: point);
}

List<RoomModel> _roomsContainingPoint({
  required List<RoomModel> rooms,
  required Offset point,
}) {
  final List<RoomModel> preciseRooms = rooms
      .where((RoomModel room) => room.path.contains(point))
      .toList(growable: false);
  if (preciseRooms.isNotEmpty) {
    return preciseRooms;
  }

  return rooms
      .where((RoomModel room) => room.path.getBounds().contains(point))
      .toList(growable: false);
}

RoomModel _nearestRoomToPoint({
  required List<RoomModel> rooms,
  required Offset point,
}) {
  RoomModel? selectedRoom;
  double minDistance = double.infinity;

  for (final RoomModel room in rooms) {
    final Offset center = room.path.getBounds().center;
    final double distance = (center - point).distance;
    if (distance >= minDistance) {
      continue;
    }

    minDistance = distance;
    selectedRoom = room;
  }

  final RoomModel? room = selectedRoom;
  if (room == null) {
    throw StateError('Не удалось выбрать аудиторию в точке $point.');
  }

  return room;
}
