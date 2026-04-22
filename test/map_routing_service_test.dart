import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtu_mirea_app/map/config/map_campuses.dart';
import 'package:rtu_mirea_app/map/models/campus_model.dart';
import 'package:rtu_mirea_app/map/models/floor_model.dart';
import 'package:rtu_mirea_app/map/models/map_room_search_entry.dart';
import 'package:rtu_mirea_app/map/models/map_route_result.dart';
import 'package:rtu_mirea_app/map/models/map_route_segment.dart';
import 'package:rtu_mirea_app/map/models/room_model.dart';
import 'package:rtu_mirea_app/map/services/map_room_hit_test_service.dart';
import 'package:rtu_mirea_app/map/services/map_routing_service.dart';
import 'package:rtu_mirea_app/map/services/objects_service.dart';
import 'package:rtu_mirea_app/map/services/svg_path_parser.dart';
import 'package:rtu_mirea_app/map/services/svg_room_parser.dart';
import 'package:xml/xml.dart' as xml;

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

    expect(floor3Segment.points, isNotEmpty);
  });

  test('builds route between search entries for A-214-2 and A-421', () async {
    final List<MapRoomSearchEntry> entries = await _buildSearchEntries();
    final MapRoutingService routingService = MapRoutingService();

    final MapRouteResult route = await routingService.buildRoute(
      start: _singleEntryByName(entries: entries, name: 'А-214-2'),
      destination: _singleEntryByName(entries: entries, name: 'А-421'),
      availableCampuses: universityMapCampuses,
    );

    final List<int> floorNumbers = _routeFloorNumbers(route);

    expect(floorNumbers.first, 2);
    expect(floorNumbers, contains(3));
    expect(floorNumbers.last, 4);
  });

  test('builds route between A-214-2 and Cyberzone', () async {
    final List<MapRoomSearchEntry> entries = await _buildSearchEntries();
    final MapRoutingService routingService = MapRoutingService();

    final MapRouteResult route = await routingService.buildRoute(
      start: _singleEntryByName(entries: entries, name: 'А-214-2'),
      destination: _singleEntryByName(entries: entries, name: 'Киберзона'),
      availableCampuses: universityMapCampuses,
    );

    final List<int> floorNumbers = _routeFloorNumbers(route);

    expect(floorNumbers.first, 2);
    expect(floorNumbers.last, 1);

    final MapRouteSegment floor2Segment = route.segments.firstWhere(
      (MapRouteSegment segment) => segment.floorNumber == 2,
    );
    final MapRouteSegment floor1Segment = route.segments.firstWhere(
      (MapRouteSegment segment) => segment.floorNumber == 1,
    );

    _expectPointNear(
      point: floor2Segment.points.last,
      expected: const Offset(5567.2, 4282.8),
      maxDistance: 140,
    );
    _expectPointNear(
      point: floor1Segment.points.first,
      expected: const Offset(4902.9, 4471.7),
      maxDistance: 140,
    );
  });

  test('includes Cyberzone in local room search data', () async {
    final List<MapRoomSearchEntry> entries = await _buildSearchEntries();
    final MapRoomSearchEntry cyberzone = _singleEntryByName(
      entries: entries,
      name: 'Киберзона',
    );

    expect(cyberzone.roomId, 'В-78__r__2367:8867');
    expect(cyberzone.floor.id, 'v-78-floor1');
  });

  test('parses clickable room centers for G and D buildings', () async {
    const List<String> roomIdSuffixes = <String>[
      '__r__2318:5038',
      '__r__2318:5039',
      '__r__2318:5427',
      '__r__2318:5428',
      '__r__2318:5439',
      '__r__2318:5441',
    ];

    final List<MapRoomSearchEntry> entries = await _buildSearchEntries();
    final Map<String, List<RoomModel>> roomsByFloor =
        <String, List<RoomModel>>{};
    for (final String roomIdSuffix in roomIdSuffixes) {
      final MapRoomSearchEntry sample = entries.singleWhere(
        (MapRoomSearchEntry entry) => entry.roomId.endsWith(roomIdSuffix),
      );
      final List<RoomModel> floorRooms = await _roomsForFloor(
        roomsByFloor: roomsByFloor,
        floor: sample.floor,
      );
      final RoomModel room = floorRooms.singleWhere(
        (RoomModel room) => room.roomId == sample.roomId,
      );

      final RoomModel? selectedRoom = findRoomAtPoint(
        rooms: floorRooms,
        point: room.path.getBounds().center,
      );

      expect(selectedRoom?.roomId, sample.roomId);
    }
  });

  test('applies ancestor transforms when parsing room paths', () {
    final xml.XmlDocument document = xml.XmlDocument.parse('''
<svg viewBox="0 0 200 200">
  <g transform="translate(100 50)">
    <g data-object="В-78__r__test">
      <rect x="10" y="20" width="30" height="40" />
    </g>
  </g>
</svg>
''');
    final xml.XmlElement svgRoot = document.findElements('svg').first;
    final xml.XmlElement roomElement = svgRoot.descendants
        .whereType<xml.XmlElement>()
        .firstWhere(
          (xml.XmlElement element) =>
              element.getAttribute('data-object') == 'В-78__r__test',
        );
    final Path? path = SvgPathParser.parseElementToPath(
      element: roomElement,
      elementsById: SvgPathParser.collectElementsById(svgRoot),
    );

    expect(path, isNotNull);
    expect(path!.getBounds(), const Rect.fromLTWH(110, 70, 30, 40));
    expect(path.contains(const Offset(125, 90)), isTrue);
  });

  test('applies matrix transforms when parsing room paths', () {
    final xml.XmlDocument document = xml.XmlDocument.parse('''
<svg viewBox="0 0 200 200">
  <g data-object="В-78__r__test">
    <rect width="30" height="40" transform="matrix(1 0 0 1 100 50)" />
  </g>
</svg>
''');
    final xml.XmlElement svgRoot = document.findElements('svg').first;
    final xml.XmlElement roomElement = svgRoot.descendants
        .whereType<xml.XmlElement>()
        .firstWhere(
          (xml.XmlElement element) =>
              element.getAttribute('data-object') == 'В-78__r__test',
        );
    final Path? path = SvgPathParser.parseElementToPath(
      element: roomElement,
      elementsById: SvgPathParser.collectElementsById(svgRoot),
    );

    expect(path, isNotNull);
    expect(path!.getBounds(), const Rect.fromLTWH(100, 50, 30, 40));
    expect(path.contains(const Offset(115, 70)), isTrue);
  });
}

Future<List<MapRoomSearchEntry>> _buildSearchEntries() async {
  final ObjectsService objectsService = ObjectsService();
  await objectsService.loadObjects();

  final List<MapRoomSearchEntry> entries = <MapRoomSearchEntry>[];
  for (final CampusModel campus in universityMapCampuses) {
    for (final FloorModel floor in campus.floors) {
      final (List<RoomModel>, Rect) floorData = await SvgRoomsParser.parseSvg(
        floor.svgPath,
      );
      for (final RoomModel room in floorData.$1) {
        final String objectId = _objectIdFromDataObject(room.roomId);
        final String name = objectsService.getNameById(objectId) ?? '';
        if (name.isEmpty || !objectsService.isRoom(objectId)) {
          continue;
        }

        entries.add(
          MapRoomSearchEntry(
            roomId: room.roomId,
            name: name,
            campus: campus,
            floor: floor,
          ),
        );
      }
    }
  }

  return entries;
}

Future<List<RoomModel>> _roomsForFloor({
  required Map<String, List<RoomModel>> roomsByFloor,
  required FloorModel floor,
}) async {
  final List<RoomModel>? cachedRooms = roomsByFloor[floor.id];
  if (cachedRooms != null) {
    return cachedRooms;
  }

  final (List<RoomModel>, Rect) floorData = await SvgRoomsParser.parseSvg(
    floor.svgPath,
  );
  roomsByFloor[floor.id] = floorData.$1;
  return floorData.$1;
}

MapRoomSearchEntry _singleEntryByName({
  required List<MapRoomSearchEntry> entries,
  required String name,
}) {
  final List<MapRoomSearchEntry> matches = entries
      .where((MapRoomSearchEntry entry) => entry.name == name)
      .toList(growable: false);

  expect(matches, hasLength(1), reason: 'Expected one search entry for $name');

  return matches.single;
}

List<int> _routeFloorNumbers(MapRouteResult route) {
  return route.segments
      .map((MapRouteSegment segment) => segment.floorNumber)
      .toList(growable: false);
}

void _expectPointNear({
  required Offset point,
  required Offset expected,
  required double maxDistance,
}) {
  expect((point - expected).distance, lessThanOrEqualTo(maxDistance));
}

String _objectIdFromDataObject(String dataObject) {
  final RegExpMatch? match = RegExp(
    r'__(?:r|c|s|t)__([^_]+)$',
  ).firstMatch(dataObject);
  if (match == null) {
    return '';
  }

  return match.group(1)!;
}
