import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
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
import 'package:rtu_mirea_app/map/services/map_synthetic_object_service.dart';
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
        objectType: MapObjectType.room,
        campus: campus,
        floor: floor2,
      ),
      destination: MapRoomSearchEntry(
        roomId: 'В-78__r__2318:4339',
        name: 'А-421',
        objectType: MapObjectType.room,
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

    final FloorModel floor1 = route.destination.campus.floors.firstWhere(
      (FloorModel floor) => floor.id == 'v-78-floor1',
    );
    final List<Path> unusedNearbyStairs = <Path>[
      await _pathByDataObjectSuffix(floor: floor1, suffix: '__s__2318:6543'),
      await _pathByDataObjectSuffix(floor: floor1, suffix: '__s__2318:6544'),
    ];
    for (final Path unusedStair in unusedNearbyStairs) {
      _expectSegmentAvoidsPath(
        segment: floor1Segment,
        blockedPath: unusedStair,
      );
    }
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

  test('includes V-78 entrance exits in local route search data', () async {
    final List<MapRoomSearchEntry> entries = _v78RouteableEntries(
      await _buildSearchEntries(),
    );
    final List<MapRoomSearchEntry> entranceExits = entries
        .where(
          (MapRoomSearchEntry entry) =>
              entry.objectType == MapObjectType.entranceExit,
        )
        .toList(growable: false);

    expect(entranceExits, hasLength(2));
    for (final MapRoomSearchEntry entry in entranceExits) {
      expect(entry.name, mapEntranceExitName);
      expect(entry.floor.id, 'v-78-floor2');
      expect(isSyntheticEntranceExitId(entry.roomId), isTrue);
    }
  });

  test(
    'builds route from main entrance to E-8 through outdoor paths',
    () async {
      final List<MapRoomSearchEntry> entries = _v78RouteableEntries(
        await _buildSearchEntries(),
      );
      final MapRoomSearchEntry mainEntrance = await _rightmostEntranceExitEntry(
        entries: entries,
      );
      final MapRoomSearchEntry e8 = _singleEntryByRoomId(
        entries: entries,
        roomId: 'В-78__r__2318:5524',
      );
      final MapRoutingService routingService = MapRoutingService();

      final MapRouteResult route = await routingService.buildRoute(
        start: mainEntrance,
        destination: e8,
        availableCampuses: universityMapCampuses,
      );

      expect(_routeFloorNumbers(route), <int>[2]);

      final MapRouteSegment floor2Segment = route.segments.single;
      final List<Path> blockedPaths = await _blockedPathsForFloor(
        floor: e8.floor,
        excludedDataObjects: <String>{e8.roomId},
      );
      _expectSegmentAvoidsPaths(
        segment: floor2Segment,
        blockedPaths: blockedPaths,
      );
    },
  );

  test('parses clickable centers for all V-78 routeable objects', () async {
    final List<MapRoomSearchEntry> entries = _v78RouteableEntries(
      await _buildSearchEntries(),
    );
    final Map<String, List<RoomModel>> roomsByFloor =
        <String, List<RoomModel>>{};
    final List<String> failures = <String>[];

    for (final MapRoomSearchEntry sample in entries) {
      final List<RoomModel> floorRooms = await _roomsForFloor(
        roomsByFloor: roomsByFloor,
        floor: sample.floor,
      );
      final RoomModel? room = _roomById(
        rooms: floorRooms,
        roomId: sample.roomId,
      );
      if (room == null) {
        failures.add('${_entryDebugLabel(sample)}: контур не найден');
        continue;
      }

      final Rect bounds = room.path.getBounds();
      if (bounds.isEmpty || !_rectIsFinite(bounds)) {
        failures.add('${_entryDebugLabel(sample)}: некорректные bounds');
        continue;
      }

      final RoomModel? selectedObject = findRoomAtPoint(
        rooms: floorRooms,
        point: bounds.center,
      );
      if (selectedObject?.roomId != sample.roomId &&
          !_isKnownOverlappingRouteTarget(sample.roomId)) {
        failures.add(
          '${_entryDebugLabel(sample)}: центр выбирает ${selectedObject?.roomId}',
        );
      }
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test(
    'builds routes from anchor to V-78 canteens, entrances and smoke route targets',
    () async {
      final List<MapRoomSearchEntry> entries = _v78RouteableEntries(
        await _buildSearchEntries(),
      );
      final MapRoomSearchEntry anchor = _singleEntryByRoomId(
        entries: entries,
        roomId: 'В-78__r__2318:5274',
      );
      final MapRoutingService routingService = MapRoutingService();
      await routingService.preloadCampus(campus: anchor.campus);
      final List<MapRoomSearchEntry> destinations = _routeConnectivityEntries(
        entries: entries,
        anchor: anchor,
      );

      expect(
        destinations.any(
          (MapRoomSearchEntry entry) =>
              entry.objectType == MapObjectType.canteen,
        ),
        isTrue,
      );
      expect(
        destinations.any(
          (MapRoomSearchEntry entry) =>
              entry.objectType == MapObjectType.toilet,
        ),
        isTrue,
      );
      expect(
        destinations.any(
          (MapRoomSearchEntry entry) =>
              entry.objectType == MapObjectType.entranceExit,
        ),
        isTrue,
      );
      expect(
        destinations.any(
          (MapRoomSearchEntry entry) => entry.objectType == MapObjectType.room,
        ),
        isTrue,
      );

      final List<String> failures = <String>[];
      for (final MapRoomSearchEntry destination in destinations) {
        try {
          final MapRouteResult route = await routingService.buildRoute(
            start: anchor,
            destination: destination,
            availableCampuses: universityMapCampuses,
          );
          if (route.segments.isEmpty) {
            failures.add('${_entryDebugLabel(destination)}: пустой маршрут');
          }
        } catch (error) {
          failures.add('${_entryDebugLabel(destination)}: $error');
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

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

  test('applies rotate transforms around explicit center', () {
    final xml.XmlDocument document = xml.XmlDocument.parse('''
<svg viewBox="-50 0 100 100">
  <g data-object="В-78__r__test">
    <rect x="10" y="20" width="30" height="40" transform="rotate(90 10 20)" />
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
    final Rect bounds = path!.getBounds();
    expect(bounds.left, moreOrLessEquals(-30));
    expect(bounds.top, moreOrLessEquals(20));
    expect(bounds.right, moreOrLessEquals(10));
    expect(bounds.bottom, moreOrLessEquals(50));
    expect(path.contains(const Offset(-10, 35)), isTrue);
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
        final String name =
            room.name.isNotEmpty
                ? room.name
                : objectsService.getNameById(objectId) ?? '';
        final MapObjectType? objectType = _routeableTypeFromDataObject(
          objectsService: objectsService,
          dataObject: room.roomId,
        );
        if (name.isEmpty || objectType == null) {
          continue;
        }

        entries.add(
          MapRoomSearchEntry(
            roomId: room.roomId,
            name: name,
            objectType: objectType,
            campus: campus,
            floor: floor,
          ),
        );
      }
    }
  }

  return entries;
}

List<MapRoomSearchEntry> _v78RouteableEntries(
  List<MapRoomSearchEntry> entries,
) {
  return entries
      .where((MapRoomSearchEntry entry) => entry.campus.id == 'v-78')
      .toList(growable: false);
}

List<MapRoomSearchEntry> _routeConnectivityEntries({
  required List<MapRoomSearchEntry> entries,
  required MapRoomSearchEntry anchor,
}) {
  const Set<String> smokeTargetIds = <String>{
    'В-78__r__2318:4339',
    'В-78__r__2367:8867',
    'В-78__t__2318:5687',
    'В-78__t__2318:5688',
  };

  return entries
      .where(
        (MapRoomSearchEntry entry) =>
            entry.objectType == MapObjectType.canteen ||
            entry.objectType == MapObjectType.entranceExit ||
            smokeTargetIds.contains(entry.roomId),
      )
      .where(
        (MapRoomSearchEntry entry) =>
            entry.roomId != anchor.roomId || entry.floor.id != anchor.floor.id,
      )
      .toList(growable: false);
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

MapRoomSearchEntry _singleEntryByRoomId({
  required List<MapRoomSearchEntry> entries,
  required String roomId,
}) {
  final List<MapRoomSearchEntry> matches = entries
      .where((MapRoomSearchEntry entry) => entry.roomId == roomId)
      .toList(growable: false);

  expect(
    matches,
    hasLength(1),
    reason: 'Expected one search entry for $roomId',
  );

  return matches.single;
}

Future<MapRoomSearchEntry> _rightmostEntranceExitEntry({
  required List<MapRoomSearchEntry> entries,
}) async {
  final List<MapRoomSearchEntry> entranceExits = entries
      .where(
        (MapRoomSearchEntry entry) =>
            entry.objectType == MapObjectType.entranceExit,
      )
      .toList(growable: false);
  expect(entranceExits, hasLength(2));

  final Map<String, List<RoomModel>> roomsByFloor = <String, List<RoomModel>>{};
  MapRoomSearchEntry? result;
  double resultCenterX = -double.infinity;
  for (final MapRoomSearchEntry entry in entranceExits) {
    final List<RoomModel> floorRooms = await _roomsForFloor(
      roomsByFloor: roomsByFloor,
      floor: entry.floor,
    );
    final RoomModel? room = _roomById(rooms: floorRooms, roomId: entry.roomId);
    expect(room, isNotNull);

    final double centerX = room!.path.getBounds().center.dx;
    if (centerX <= resultCenterX) {
      continue;
    }

    result = entry;
    resultCenterX = centerX;
  }

  expect(result, isNotNull);
  return result!;
}

RoomModel? _roomById({required List<RoomModel> rooms, required String roomId}) {
  for (final RoomModel room in rooms) {
    if (room.roomId == roomId) {
      return room;
    }
  }

  return null;
}

bool _rectIsFinite(Rect rect) {
  return rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite;
}

bool _isKnownOverlappingRouteTarget(String roomId) {
  const Set<String> knownOverlappingRouteTargetIds = <String>{
    'В-78__r__2367:8876',
    'В-78__r__2367:8874',
    'В-78__r__2367:8881',
  };

  return knownOverlappingRouteTargetIds.contains(roomId);
}

String _entryDebugLabel(MapRoomSearchEntry entry) {
  return '${entry.name} ${entry.roomId} ${entry.floor.id}';
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

Future<Path> _pathByDataObjectSuffix({
  required FloorModel floor,
  required String suffix,
}) async {
  final String svgString = await rootBundle.loadString(floor.svgPath);
  final xml.XmlDocument document = xml.XmlDocument.parse(svgString);
  final xml.XmlElement svgRoot = document.findElements('svg').first;
  final xml.XmlElement element = svgRoot.descendants
      .whereType<xml.XmlElement>()
      .firstWhere(
        (xml.XmlElement element) =>
            element.getAttribute('data-object')?.endsWith(suffix) ?? false,
      );
  final Path? path = SvgPathParser.parseElementToPath(
    element: element,
    elementsById: SvgPathParser.collectElementsById(svgRoot),
  );

  expect(path, isNotNull);
  return path!;
}

Future<List<Path>> _blockedPathsForFloor({
  required FloorModel floor,
  required Set<String> excludedDataObjects,
}) async {
  final String svgString = await rootBundle.loadString(floor.svgPath);
  final xml.XmlDocument document = xml.XmlDocument.parse(svgString);
  final xml.XmlElement svgRoot = document.findElements('svg').first;
  final Map<String, xml.XmlElement> elementsById =
      SvgPathParser.collectElementsById(svgRoot);
  final List<xml.XmlElement> svgElements = svgRoot.descendants
      .whereType<xml.XmlElement>()
      .toList(growable: false);
  final Set<xml.XmlElement> dataObjectElements = _collectDataObjectElements(
    svgRoot,
  );
  final List<Path> paths = <Path>[];

  for (final xml.XmlElement element in svgElements) {
    final String? dataObject = element.getAttribute('data-object');
    if (dataObject == null ||
        excludedDataObjects.contains(dataObject) ||
        !_isRouteObstacleDataObject(dataObject)) {
      continue;
    }

    final Path? path = SvgPathParser.parseElementToPath(
      element: element,
      elementsById: elementsById,
    );
    if (path != null) {
      paths.add(path);
    }
  }

  for (int index = 0; index < svgElements.length; index += 1) {
    final xml.XmlElement element = svgElements[index];
    if (!_isStandaloneBlockedRectangleElement(element, dataObjectElements)) {
      continue;
    }

    final Path? path = SvgPathParser.parseElementToPath(
      element: element,
      elementsById: elementsById,
    );
    if (path == null) {
      continue;
    }
    final Rect bounds = path.getBounds();
    if (bounds.isEmpty ||
        _hasLaterWalkableElementAtPoint(
          elements: svgElements,
          startIndex: index + 1,
          point: bounds.center,
          dataObjectElements: dataObjectElements,
          elementsById: elementsById,
        )) {
      continue;
    }

    paths.add(path);
  }

  return paths;
}

Set<xml.XmlElement> _collectDataObjectElements(xml.XmlElement svgRoot) {
  final Set<xml.XmlElement> elements = Set<xml.XmlElement>.identity();
  for (final xml.XmlElement element
      in svgRoot.descendants.whereType<xml.XmlElement>()) {
    if (element.getAttribute('data-object') == null) {
      continue;
    }

    elements.add(element);
    elements.addAll(element.descendants.whereType<xml.XmlElement>());
  }

  return elements;
}

bool _isRouteObstacleDataObject(String dataObject) {
  return dataObject.contains('__r__') ||
      dataObject.contains('__c__') ||
      dataObject.contains('__t__') ||
      dataObject.contains('__s__');
}

bool _isStandaloneBlockedRectangleElement(
  xml.XmlElement element,
  Set<xml.XmlElement> dataObjectElements,
) {
  if (dataObjectElements.contains(element)) {
    return false;
  }
  if (_isInsideSvgDefinitionElement(element)) {
    return false;
  }
  if (element.name.local.toLowerCase() != 'rect') {
    return false;
  }

  final String? fill = SvgPathParser.fillValue(element);
  if (fill == null) {
    return false;
  }

  return !_isTestWalkableFill(fill);
}

bool _isInsideSvgDefinitionElement(xml.XmlElement element) {
  xml.XmlNode? parent = element.parent;
  while (parent is xml.XmlElement) {
    final String tag = parent.name.local.toLowerCase();
    if (tag == 'defs' ||
        tag == 'clippath' ||
        tag == 'mask' ||
        tag == 'pattern' ||
        tag == 'symbol' ||
        tag == 'filter' ||
        tag == 'lineargradient' ||
        tag == 'radialgradient') {
      return true;
    }

    parent = parent.parent;
  }

  return false;
}

bool _hasLaterWalkableElementAtPoint({
  required List<xml.XmlElement> elements,
  required int startIndex,
  required Offset point,
  required Set<xml.XmlElement> dataObjectElements,
  required Map<String, xml.XmlElement> elementsById,
}) {
  for (int index = startIndex; index < elements.length; index += 1) {
    final xml.XmlElement element = elements[index];
    if (!_isTestWalkableElement(element, dataObjectElements)) {
      continue;
    }

    final Path? path = SvgPathParser.parseElementToPath(
      element: element,
      elementsById: elementsById,
    );
    if (path == null) {
      continue;
    }
    if (path.getBounds().contains(point) && path.contains(point)) {
      return true;
    }
  }

  return false;
}

bool _isTestWalkableElement(
  xml.XmlElement element,
  Set<xml.XmlElement> dataObjectElements,
) {
  if (dataObjectElements.contains(element)) {
    return false;
  }
  if (!_isTestShapeElement(element)) {
    return false;
  }

  return _isTestWalkableFill(SvgPathParser.fillValue(element));
}

bool _isTestShapeElement(xml.XmlElement element) {
  final String tag = element.name.local.toLowerCase();
  return tag == 'path' ||
      tag == 'rect' ||
      tag == 'circle' ||
      tag == 'ellipse' ||
      tag == 'polygon' ||
      tag == 'polyline' ||
      tag == 'use';
}

bool _isTestWalkableFill(String? fill) {
  return fill == '#262a34' || fill == '#f8f8f8' || fill == '#22c55e';
}

void _expectSegmentAvoidsPaths({
  required MapRouteSegment segment,
  required List<Path> blockedPaths,
}) {
  for (final Path blockedPath in blockedPaths) {
    _expectSegmentAvoidsPath(segment: segment, blockedPath: blockedPath);
  }
}

void _expectSegmentAvoidsPath({
  required MapRouteSegment segment,
  required Path blockedPath,
}) {
  for (int index = 0; index < segment.points.length - 1; index += 1) {
    final Offset start = segment.points[index];
    final Offset end = segment.points[index + 1];
    final double distance = (end - start).distance;
    final int steps = math.max(2, (distance / 8).ceil());
    for (int step = 1; step < steps; step += 1) {
      final Offset point = Offset.lerp(start, end, step / steps)!;
      expect(
        blockedPath.contains(point),
        isFalse,
        reason:
            'Route segment ${segment.floorNumber} crosses blocker at $point',
      );
    }
  }
}

String _objectIdFromDataObject(String dataObject) {
  final RegExpMatch? match = RegExp(
    r'__(?:r|c|s|t|e)__([^_]+)$',
  ).firstMatch(dataObject);
  if (match == null) {
    return '';
  }

  return match.group(1)!;
}

MapObjectType? _routeableTypeFromDataObject({
  required ObjectsService objectsService,
  required String dataObject,
}) {
  final MapObjectType? syntheticType = syntheticMapObjectTypeFromDataObject(
    dataObject,
  );
  if (syntheticType != null) {
    return syntheticType;
  }

  return objectsService.getRouteableTypeById(
    _objectIdFromDataObject(dataObject),
  );
}
