import 'package:equatable/equatable.dart';
import 'package:rtu_mirea_app/map/models/map_room_search_entry.dart';
import 'package:rtu_mirea_app/map/models/map_route_segment.dart';

class MapRouteResult extends Equatable {
  const MapRouteResult({
    required this.start,
    required this.destination,
    required this.segments,
  });

  final MapRoomSearchEntry start;
  final MapRoomSearchEntry destination;
  final List<MapRouteSegment> segments;

  @override
  List<Object?> get props => <Object?>[start, destination, segments];
}
