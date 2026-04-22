import 'dart:ui';

import 'package:equatable/equatable.dart';

class MapRouteSegment extends Equatable {
  const MapRouteSegment({
    required this.floorId,
    required this.floorNumber,
    required this.points,
  });

  final String floorId;
  final int floorNumber;
  final List<Offset> points;

  @override
  List<Object?> get props => <Object?>[floorId, floorNumber, points];
}
