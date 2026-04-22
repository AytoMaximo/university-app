import 'package:flutter_test/flutter_test.dart';
import 'package:rtu_mirea_app/map/config/map_campuses.dart';
import 'package:rtu_mirea_app/map/models/campus_model.dart';
import 'package:rtu_mirea_app/map/models/floor_model.dart';
import 'package:rtu_mirea_app/map/models/map_room_search_entry.dart';
import 'package:rtu_mirea_app/map/models/map_route_result.dart';
import 'package:rtu_mirea_app/map/models/map_route_segment.dart';
import 'package:rtu_mirea_app/map/services/map_routing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds route between A-214-2 and A-421', () async {
    final CampusModel campus = universityMapCampuses.firstWhere(
      (CampusModel campus) => campus.id == 'v-78',
    );
    final FloorModel floor2 = campus.floors.firstWhere(
      (FloorModel floor) => floor.id == 'v-78-floor2',
    );
    final FloorModel floor4 = campus.floors.firstWhere(
      (FloorModel floor) => floor.id == 'v-78-floor4',
    );
    final MapRoutingService routingService = MapRoutingService();

    final MapRouteResult route = await routingService.buildRoute(
      start: MapRoomSearchEntry(
        roomId: 'В-78__r__2318:5274',
        name: 'А-214-2',
        campus: campus,
        floor: floor2,
      ),
      destination: MapRoomSearchEntry(
        roomId: 'В-78__r__2318:4339',
        name: 'А-421',
        campus: campus,
        floor: floor4,
      ),
      availableCampuses: universityMapCampuses,
    );

    final List<int> floorNumbers = route.segments
        .map((MapRouteSegment segment) => segment.floorNumber)
        .toList(growable: false);

    expect(floorNumbers.first, 2);
    expect(floorNumbers, contains(3));
    expect(floorNumbers.last, 4);

    final MapRouteSegment floor3Segment = route.segments.firstWhere(
      (MapRouteSegment segment) => segment.floorNumber == 3,
    );

    expect(floor3Segment.points.length, greaterThan(1));
  });
}
