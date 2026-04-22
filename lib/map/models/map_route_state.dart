import 'package:equatable/equatable.dart';
import 'package:rtu_mirea_app/map/models/map_room_search_entry.dart';
import 'package:rtu_mirea_app/map/models/map_route_result.dart';

class MapRouteState extends Equatable {
  const MapRouteState({
    required this.start,
    required this.destination,
    required this.result,
    required this.errorMessage,
    required this.isBuilding,
  });

  const MapRouteState.empty()
    : start = null,
      destination = null,
      result = null,
      errorMessage = null,
      isBuilding = false;

  final MapRoomSearchEntry? start;
  final MapRoomSearchEntry? destination;
  final MapRouteResult? result;
  final String? errorMessage;
  final bool isBuilding;

  bool get canBuild => start != null && destination != null;

  MapRouteState withStart(MapRoomSearchEntry entry) {
    return MapRouteState(
      start: entry,
      destination: destination,
      result: null,
      errorMessage: null,
      isBuilding: false,
    );
  }

  MapRouteState withDestination(MapRoomSearchEntry entry) {
    return MapRouteState(
      start: start,
      destination: entry,
      result: null,
      errorMessage: null,
      isBuilding: false,
    );
  }

  MapRouteState asBuilding() {
    return MapRouteState(
      start: start,
      destination: destination,
      result: null,
      errorMessage: null,
      isBuilding: true,
    );
  }

  MapRouteState withResult(MapRouteResult routeResult) {
    return MapRouteState(
      start: start,
      destination: destination,
      result: routeResult,
      errorMessage: null,
      isBuilding: false,
    );
  }

  MapRouteState withError(String message) {
    return MapRouteState(
      start: start,
      destination: destination,
      result: null,
      errorMessage: message,
      isBuilding: false,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    start,
    destination,
    result,
    errorMessage,
    isBuilding,
  ];
}
