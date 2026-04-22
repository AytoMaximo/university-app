import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:rtu_mirea_app/map/map.dart';

abstract class MapState extends Equatable {
  const MapState();

  @override
  List<Object?> get props => [];
}

class MapInitial extends MapState {
  const MapInitial();

  MapInitial copyWith() {
    return const MapInitial();
  }
}

class MapLoading extends MapState {
  const MapLoading();

  MapLoading copyWith() {
    return const MapLoading();
  }
}

class MapLoaded extends MapState {
  final CampusModel selectedCampus;
  final FloorModel selectedFloor;
  final List<RoomModel> rooms;
  final List<MapRoomSearchEntry> searchEntries;
  final Rect? boundingRect;
  final String? selectedRoomId;
  final MapRouteState routeState;

  const MapLoaded({
    required this.selectedCampus,
    required this.selectedFloor,
    required this.rooms,
    required this.searchEntries,
    required this.routeState,
    this.boundingRect,
    this.selectedRoomId,
  });

  MapLoaded copyWith({
    CampusModel? selectedCampus,
    FloorModel? selectedFloor,
    List<RoomModel>? rooms,
    List<MapRoomSearchEntry>? searchEntries,
    MapRouteState? routeState,
    Rect? boundingRect,
    String? selectedRoomId,
  }) {
    return MapLoaded(
      selectedCampus: selectedCampus ?? this.selectedCampus,
      selectedFloor: selectedFloor ?? this.selectedFloor,
      rooms: rooms ?? this.rooms,
      searchEntries: searchEntries ?? this.searchEntries,
      routeState: routeState ?? this.routeState,
      boundingRect: boundingRect ?? this.boundingRect,
      selectedRoomId: selectedRoomId ?? this.selectedRoomId,
    );
  }

  MapLoaded withoutSelectedRoom() {
    return MapLoaded(
      selectedCampus: selectedCampus,
      selectedFloor: selectedFloor,
      rooms: _roomsWithoutSelection(rooms),
      searchEntries: searchEntries,
      routeState: routeState,
      boundingRect: boundingRect,
    );
  }

  static List<RoomModel> _roomsWithoutSelection(List<RoomModel> rooms) {
    return rooms
        .map((RoomModel room) => room.copyWith(isSelected: false))
        .toList(growable: false);
  }

  @override
  List<Object?> get props => <Object?>[
    selectedCampus,
    selectedFloor,
    rooms,
    searchEntries,
    routeState,
    boundingRect,
    selectedRoomId,
  ];
}

class MapError extends MapState {
  final String message;

  const MapError(this.message);

  MapError copyWith({String? message}) {
    return MapError(message ?? this.message);
  }

  @override
  List<Object?> get props => [message];
}
