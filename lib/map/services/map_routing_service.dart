import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:rtu_mirea_app/map/models/campus_model.dart';
import 'package:rtu_mirea_app/map/models/floor_model.dart';
import 'package:rtu_mirea_app/map/models/map_room_search_entry.dart';
import 'package:rtu_mirea_app/map/models/map_route_result.dart';
import 'package:rtu_mirea_app/map/models/map_route_segment.dart';
import 'package:rtu_mirea_app/map/services/svg_path_parser.dart';
import 'package:xml/xml.dart' as xml;

class MapRoutingService {
  final Map<String, List<_RouteFloorData>> _campusCache =
      <String, List<_RouteFloorData>>{};

  Future<MapRouteResult> buildRoute({
    required MapRoomSearchEntry start,
    required MapRoomSearchEntry destination,
    required List<CampusModel> availableCampuses,
  }) async {
    if (start.campus.id != 'v-78' || destination.campus.id != 'v-78') {
      throw UnsupportedError(
        'Маршруты сейчас доступны только для корпуса В-78.',
      );
    }
    if (start.roomId == destination.roomId &&
        start.floor.id == destination.floor.id) {
      throw ArgumentError('Выберите разные аудитории для маршрута.');
    }

    final CampusModel campus = _findCampus(
      availableCampuses: availableCampuses,
      campusId: start.campus.id,
    );
    final List<_RouteFloorData> floors = await _loadCampusFloors(campus);
    final _RouteGraph graph = _buildGraph(floors);
    final int startNode = _addEndpointNode(
      graph: graph,
      floors: floors,
      entry: start,
      label: 'начальной аудитории',
    );
    final int destinationNode = _addEndpointNode(
      graph: graph,
      floors: floors,
      entry: destination,
      label: 'конечной аудитории',
    );

    _addStairNodes(graph: graph, floors: floors);
    final List<int> path = _findShortestPath(
      graph: graph,
      startNode: startNode,
      destinationNode: destinationNode,
    );
    if (path.isEmpty) {
      throw StateError('Маршрут между выбранными аудиториями не найден.');
    }

    return MapRouteResult(
      start: start,
      destination: destination,
      segments: _buildSegments(graph: graph, path: path),
    );
  }

  CampusModel _findCampus({
    required List<CampusModel> availableCampuses,
    required String campusId,
  }) {
    for (final CampusModel campus in availableCampuses) {
      if (campus.id == campusId) {
        return campus;
      }
    }

    throw StateError('Корпус $campusId не найден в конфигурации карты.');
  }

  Future<List<_RouteFloorData>> _loadCampusFloors(CampusModel campus) async {
    final List<_RouteFloorData>? cachedFloors = _campusCache[campus.id];
    if (cachedFloors != null) {
      return cachedFloors;
    }

    final List<_RouteFloorData> floors = <_RouteFloorData>[];
    for (final FloorModel floor in campus.floors) {
      floors.add(await _parseFloor(floor));
    }
    floors.sort(
      (_RouteFloorData left, _RouteFloorData right) =>
          left.floor.number.compareTo(right.floor.number),
    );
    _campusCache[campus.id] = floors;
    return floors;
  }

  Future<_RouteFloorData> _parseFloor(FloorModel floor) async {
    final String svgString = await rootBundle.loadString(floor.svgPath);
    final xml.XmlDocument document = xml.XmlDocument.parse(svgString);
    final xml.XmlElement svgRoot = document.findElements('svg').first;
    final Map<String, xml.XmlElement> elementsById =
        SvgPathParser.collectElementsById(svgRoot);
    final HashSet<xml.XmlElement> dataObjectElements =
        _collectDataObjectElements(svgRoot);

    final List<_WalkableArea> walkableAreas = <_WalkableArea>[];
    for (final xml.XmlElement element
        in svgRoot.descendants.whereType<xml.XmlElement>()) {
      if (!_isWalkableElement(element, dataObjectElements)) {
        continue;
      }

      final Path? path = SvgPathParser.parseElementToPath(
        element: element,
        elementsById: elementsById,
      );
      if (path == null) {
        continue;
      }

      walkableAreas.add(_WalkableArea(path: path, bounds: path.getBounds()));
    }

    final Map<String, _RouteObject> rooms = <String, _RouteObject>{};
    final List<_RouteObject> stairs = <_RouteObject>[];
    for (final xml.XmlElement element
        in svgRoot.descendants.whereType<xml.XmlElement>()) {
      final String? dataObject = element.getAttribute('data-object');
      if (dataObject == null) {
        continue;
      }

      final _RouteObjectType? type = _parseDataObjectType(dataObject);
      if (type == null) {
        continue;
      }

      final Path? path = SvgPathParser.parseElementToPath(
        element: element,
        elementsById: elementsById,
      );
      if (path == null) {
        continue;
      }

      final _RouteObject routeObject = _RouteObject(bounds: path.getBounds());
      if (type == _RouteObjectType.room) {
        rooms[dataObject] = routeObject;
      } else if (type == _RouteObjectType.stairs) {
        stairs.add(routeObject);
      }
    }

    final Set<_GridKey> walkableKeys = _buildWalkableKeys(walkableAreas);
    if (walkableKeys.isEmpty) {
      throw StateError(
        'На этаже ${floor.number} корпуса В-78 не найден walkable-слой.',
      );
    }

    return _RouteFloorData(
      floor: floor,
      walkableKeys: walkableKeys,
      rooms: rooms,
      stairs: stairs,
    );
  }

  HashSet<xml.XmlElement> _collectDataObjectElements(xml.XmlElement svgRoot) {
    final HashSet<xml.XmlElement> elements = HashSet<xml.XmlElement>.identity();
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

  bool _isWalkableElement(
    xml.XmlElement element,
    HashSet<xml.XmlElement> dataObjectElements,
  ) {
    if (dataObjectElements.contains(element)) {
      return false;
    }
    if (!_isShapeElement(element)) {
      return false;
    }

    return SvgPathParser.fillValue(element) == '#262a34';
  }

  bool _isShapeElement(xml.XmlElement element) {
    final String tag = element.name.local.toLowerCase();
    return tag == 'path' ||
        tag == 'rect' ||
        tag == 'circle' ||
        tag == 'ellipse' ||
        tag == 'polygon' ||
        tag == 'polyline' ||
        tag == 'use';
  }

  _RouteObjectType? _parseDataObjectType(String dataObject) {
    if (dataObject.contains('__r__')) {
      return _RouteObjectType.room;
    }
    if (dataObject.contains('__s__')) {
      return _RouteObjectType.stairs;
    }

    return null;
  }

  Set<_GridKey> _buildWalkableKeys(List<_WalkableArea> walkableAreas) {
    final Set<_GridKey> keys = <_GridKey>{};
    for (final _WalkableArea area in walkableAreas) {
      final int left = (area.bounds.left / _gridStep).floor();
      final int right = (area.bounds.right / _gridStep).ceil();
      final int top = (area.bounds.top / _gridStep).floor();
      final int bottom = (area.bounds.bottom / _gridStep).ceil();
      for (int x = left; x <= right; x += 1) {
        for (int y = top; y <= bottom; y += 1) {
          final Offset point = _pointFromKey(_GridKey(x: x, y: y));
          if (area.path.contains(point)) {
            keys.add(_GridKey(x: x, y: y));
          }
        }
      }
    }

    return keys;
  }

  _RouteGraph _buildGraph(List<_RouteFloorData> floors) {
    final _RouteGraph graph = _RouteGraph();
    for (final _RouteFloorData floorData in floors) {
      final Map<_GridKey, int> floorNodes = <_GridKey, int>{};
      final List<int> nodeIndexes = <int>[];
      for (final _GridKey key in floorData.walkableKeys) {
        final int nodeIndex = graph.addNode(
          _RouteNode(
            floorId: floorData.floor.id,
            floorNumber: floorData.floor.number,
            point: _pointFromKey(key),
            gridKey: key,
          ),
        );
        floorNodes[key] = nodeIndex;
        nodeIndexes.add(nodeIndex);
      }
      graph.gridNodesByFloor[floorData.floor.id] = floorNodes;
      graph.nodeIndexesByFloor[floorData.floor.id] = nodeIndexes;
    }

    return graph;
  }

  int _addEndpointNode({
    required _RouteGraph graph,
    required List<_RouteFloorData> floors,
    required MapRoomSearchEntry entry,
    required String label,
  }) {
    final _RouteFloorData floorData = _findFloorData(
      floors: floors,
      floorId: entry.floor.id,
    );
    final _RouteObject? room = floorData.rooms[entry.roomId];
    if (room == null) {
      throw StateError('Контур $label ${entry.name} не найден на карте.');
    }

    final int nodeIndex = graph.addNode(
      _RouteNode(
        floorId: floorData.floor.id,
        floorNumber: floorData.floor.number,
        point: room.bounds.center,
        gridKey: null,
      ),
    );
    final int nearestGridNode = _findNearestGridNode(
      graph: graph,
      floorData: floorData,
      candidates: _connectionCandidates(room.bounds),
      maxDistance: _roomConnectionMaxDistance,
    );
    graph.addEdge(
      from: nodeIndex,
      to: nearestGridNode,
      weight:
          (graph.nodes[nodeIndex].point - graph.nodes[nearestGridNode].point)
              .distance,
    );

    return nodeIndex;
  }

  _RouteFloorData _findFloorData({
    required List<_RouteFloorData> floors,
    required String floorId,
  }) {
    for (final _RouteFloorData floor in floors) {
      if (floor.floor.id == floorId) {
        return floor;
      }
    }

    throw StateError('Этаж $floorId не найден в маршрутизации.');
  }

  void _addStairNodes({
    required _RouteGraph graph,
    required List<_RouteFloorData> floors,
  }) {
    final Map<String, List<_StairNode>> stairNodesByFloor =
        <String, List<_StairNode>>{};

    for (final _RouteFloorData floorData in floors) {
      final List<_StairNode> stairNodes = <_StairNode>[];
      for (final _RouteObject stair in floorData.stairs) {
        final int nodeIndex = graph.addNode(
          _RouteNode(
            floorId: floorData.floor.id,
            floorNumber: floorData.floor.number,
            point: stair.bounds.center,
            gridKey: null,
          ),
        );
        final int nearestGridNode = _findNearestGridNode(
          graph: graph,
          floorData: floorData,
          candidates: _connectionCandidates(stair.bounds),
          maxDistance: _stairConnectionMaxDistance,
        );
        graph.addEdge(
          from: nodeIndex,
          to: nearestGridNode,
          weight:
              (graph.nodes[nodeIndex].point -
                      graph.nodes[nearestGridNode].point)
                  .distance,
        );
        stairNodes.add(
          _StairNode(nodeIndex: nodeIndex, center: stair.bounds.center),
        );
      }
      stairNodesByFloor[floorData.floor.id] = stairNodes;
    }

    for (int index = 0; index < floors.length - 1; index += 1) {
      final _RouteFloorData lowerFloor = floors[index];
      final _RouteFloorData upperFloor = floors[index + 1];
      final List<_StairNode> lowerStairs =
          stairNodesByFloor[lowerFloor.floor.id] ?? <_StairNode>[];
      final List<_StairNode> upperStairs =
          stairNodesByFloor[upperFloor.floor.id] ?? <_StairNode>[];
      for (final _StairNode lower in lowerStairs) {
        for (final _StairNode upper in upperStairs) {
          final double distance = (lower.center - upper.center).distance;
          if (distance > _stairMatchingTolerance) {
            continue;
          }

          graph.addEdge(
            from: lower.nodeIndex,
            to: upper.nodeIndex,
            weight: _floorTransferWeight + distance,
          );
        }
      }
    }
  }

  int _findNearestGridNode({
    required _RouteGraph graph,
    required _RouteFloorData floorData,
    required List<Offset> candidates,
    required double maxDistance,
  }) {
    final List<int> nodeIndexes =
        graph.nodeIndexesByFloor[floorData.floor.id] ?? <int>[];
    int? nearestNode;
    double nearestDistance = double.infinity;

    for (final int nodeIndex in nodeIndexes) {
      final Offset point = graph.nodes[nodeIndex].point;
      for (final Offset candidate in candidates) {
        final double distance = (point - candidate).distance;
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestNode = nodeIndex;
        }
      }
    }

    final int? node = nearestNode;
    if (node == null || nearestDistance > maxDistance) {
      throw StateError(
        'Не найден ближайший коридор на этаже ${floorData.floor.number}.',
      );
    }

    return node;
  }

  List<Offset> _connectionCandidates(Rect bounds) {
    return <Offset>[
      bounds.center,
      bounds.centerLeft,
      bounds.centerRight,
      bounds.topCenter,
      bounds.bottomCenter,
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ];
  }

  List<int> _findShortestPath({
    required _RouteGraph graph,
    required int startNode,
    required int destinationNode,
  }) {
    final List<double> distances = List<double>.filled(
      graph.nodes.length,
      double.infinity,
      growable: false,
    );
    final List<int?> previous = List<int?>.filled(
      graph.nodes.length,
      null,
      growable: false,
    );
    final _RoutePriorityQueue queue = _RoutePriorityQueue();
    distances[startNode] = 0;
    queue.add(_QueueEntry(nodeIndex: startNode, priority: 0));

    while (queue.isNotEmpty) {
      final _QueueEntry current = queue.removeFirst();
      if (current.priority > distances[current.nodeIndex]) {
        continue;
      }
      if (current.nodeIndex == destinationNode) {
        break;
      }

      for (final _RouteEdge edge in _edgesForNode(
        graph: graph,
        nodeIndex: current.nodeIndex,
      )) {
        final double newDistance = distances[current.nodeIndex] + edge.weight;
        if (newDistance >= distances[edge.to]) {
          continue;
        }

        distances[edge.to] = newDistance;
        previous[edge.to] = current.nodeIndex;
        queue.add(_QueueEntry(nodeIndex: edge.to, priority: newDistance));
      }
    }

    if (distances[destinationNode].isInfinite) {
      return <int>[];
    }

    final List<int> path = <int>[];
    int? currentNode = destinationNode;
    while (currentNode != null) {
      path.add(currentNode);
      currentNode = previous[currentNode];
    }

    return path.reversed.toList(growable: false);
  }

  Iterable<_RouteEdge> _edgesForNode({
    required _RouteGraph graph,
    required int nodeIndex,
  }) sync* {
    final List<_RouteEdge>? explicitEdges = graph.edges[nodeIndex];
    if (explicitEdges != null) {
      yield* explicitEdges;
    }

    final _RouteNode node = graph.nodes[nodeIndex];
    final _GridKey? key = node.gridKey;
    if (key == null) {
      return;
    }

    final Map<_GridKey, int>? floorGridNodes =
        graph.gridNodesByFloor[node.floorId];
    if (floorGridNodes == null) {
      return;
    }

    for (final _GridDirection direction in _gridDirections) {
      final _GridKey neighborKey = _GridKey(
        x: key.x + direction.dx,
        y: key.y + direction.dy,
      );
      final int? neighborIndex = floorGridNodes[neighborKey];
      if (neighborIndex == null) {
        continue;
      }

      yield _RouteEdge(to: neighborIndex, weight: direction.weight * _gridStep);
    }
  }

  List<MapRouteSegment> _buildSegments({
    required _RouteGraph graph,
    required List<int> path,
  }) {
    final List<MapRouteSegment> segments = <MapRouteSegment>[];
    String? currentFloorId;
    int? currentFloorNumber;
    List<Offset> currentPoints = <Offset>[];

    for (final int nodeIndex in path) {
      final _RouteNode node = graph.nodes[nodeIndex];
      if (currentFloorId != node.floorId) {
        _addSegment(
          segments: segments,
          floorId: currentFloorId,
          floorNumber: currentFloorNumber,
          points: currentPoints,
        );
        currentFloorId = node.floorId;
        currentFloorNumber = node.floorNumber;
        currentPoints = <Offset>[node.point];
        continue;
      }

      if (currentPoints.isEmpty || currentPoints.last != node.point) {
        currentPoints.add(node.point);
      }
    }

    _addSegment(
      segments: segments,
      floorId: currentFloorId,
      floorNumber: currentFloorNumber,
      points: currentPoints,
    );

    return segments;
  }

  void _addSegment({
    required List<MapRouteSegment> segments,
    required String? floorId,
    required int? floorNumber,
    required List<Offset> points,
  }) {
    if (floorId == null || floorNumber == null || points.length < 2) {
      return;
    }

    segments.add(
      MapRouteSegment(
        floorId: floorId,
        floorNumber: floorNumber,
        points: _simplifyPoints(points),
      ),
    );
  }

  List<Offset> _simplifyPoints(List<Offset> points) {
    if (points.length < 3) {
      return points;
    }

    final List<Offset> simplified = <Offset>[points.first];
    for (int index = 1; index < points.length - 1; index += 1) {
      final Offset previous = simplified.last;
      final Offset current = points[index];
      final Offset next = points[index + 1];
      final Offset firstVector = current - previous;
      final Offset secondVector = next - current;
      final double cross =
          firstVector.dx * secondVector.dy - firstVector.dy * secondVector.dx;
      if (cross.abs() > 0.1) {
        simplified.add(current);
      }
    }
    simplified.add(points.last);

    return simplified;
  }

  Offset _pointFromKey(_GridKey key) {
    return Offset(key.x * _gridStep, key.y * _gridStep);
  }

  static const double _gridStep = 24;
  static const double _stairMatchingTolerance = 80;
  static const double _roomConnectionMaxDistance = 360;
  static const double _stairConnectionMaxDistance = 240;
  static const double _floorTransferWeight = 420;
  static final List<_GridDirection> _gridDirections = <_GridDirection>[
    _GridDirection(dx: -1, dy: -1, weight: math.sqrt2),
    _GridDirection(dx: 0, dy: -1, weight: 1),
    _GridDirection(dx: 1, dy: -1, weight: math.sqrt2),
    _GridDirection(dx: -1, dy: 0, weight: 1),
    _GridDirection(dx: 1, dy: 0, weight: 1),
    _GridDirection(dx: -1, dy: 1, weight: math.sqrt2),
    _GridDirection(dx: 0, dy: 1, weight: 1),
    _GridDirection(dx: 1, dy: 1, weight: math.sqrt2),
  ];
}

enum _RouteObjectType { room, stairs }

class _WalkableArea {
  const _WalkableArea({required this.path, required this.bounds});

  final Path path;
  final Rect bounds;
}

class _RouteObject {
  const _RouteObject({required this.bounds});

  final Rect bounds;
}

class _RouteFloorData {
  const _RouteFloorData({
    required this.floor,
    required this.walkableKeys,
    required this.rooms,
    required this.stairs,
  });

  final FloorModel floor;
  final Set<_GridKey> walkableKeys;
  final Map<String, _RouteObject> rooms;
  final List<_RouteObject> stairs;
}

class _GridKey {
  const _GridKey({required this.x, required this.y});

  final int x;
  final int y;

  @override
  bool operator ==(Object other) {
    return other is _GridKey && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);
}

class _GridDirection {
  const _GridDirection({
    required this.dx,
    required this.dy,
    required this.weight,
  });

  final int dx;
  final int dy;
  final double weight;
}

class _RouteNode {
  const _RouteNode({
    required this.floorId,
    required this.floorNumber,
    required this.point,
    required this.gridKey,
  });

  final String floorId;
  final int floorNumber;
  final Offset point;
  final _GridKey? gridKey;
}

class _RouteEdge {
  const _RouteEdge({required this.to, required this.weight});

  final int to;
  final double weight;
}

class _RouteGraph {
  final List<_RouteNode> nodes = <_RouteNode>[];
  final Map<int, List<_RouteEdge>> edges = <int, List<_RouteEdge>>{};
  final Map<String, Map<_GridKey, int>> gridNodesByFloor =
      <String, Map<_GridKey, int>>{};
  final Map<String, List<int>> nodeIndexesByFloor = <String, List<int>>{};

  int addNode(_RouteNode node) {
    nodes.add(node);
    return nodes.length - 1;
  }

  void addEdge({required int from, required int to, required double weight}) {
    edges
        .putIfAbsent(from, () => <_RouteEdge>[])
        .add(_RouteEdge(to: to, weight: weight));
    edges
        .putIfAbsent(to, () => <_RouteEdge>[])
        .add(_RouteEdge(to: from, weight: weight));
  }
}

class _StairNode {
  const _StairNode({required this.nodeIndex, required this.center});

  final int nodeIndex;
  final Offset center;
}

class _QueueEntry {
  const _QueueEntry({required this.nodeIndex, required this.priority});

  final int nodeIndex;
  final double priority;
}

class _RoutePriorityQueue {
  final List<_QueueEntry> _entries = <_QueueEntry>[];

  bool get isNotEmpty => _entries.isNotEmpty;

  void add(_QueueEntry entry) {
    _entries.add(entry);
    _bubbleUp(_entries.length - 1);
  }

  _QueueEntry removeFirst() {
    final _QueueEntry first = _entries.first;
    final _QueueEntry last = _entries.removeLast();
    if (_entries.isNotEmpty) {
      _entries[0] = last;
      _bubbleDown(0);
    }

    return first;
  }

  void _bubbleUp(int index) {
    int currentIndex = index;
    while (currentIndex > 0) {
      final int parentIndex = (currentIndex - 1) >> 1;
      if (_entries[parentIndex].priority <= _entries[currentIndex].priority) {
        return;
      }

      _swap(parentIndex, currentIndex);
      currentIndex = parentIndex;
    }
  }

  void _bubbleDown(int index) {
    int currentIndex = index;
    while (true) {
      final int leftIndex = currentIndex * 2 + 1;
      final int rightIndex = leftIndex + 1;
      int smallestIndex = currentIndex;

      if (leftIndex < _entries.length &&
          _entries[leftIndex].priority < _entries[smallestIndex].priority) {
        smallestIndex = leftIndex;
      }
      if (rightIndex < _entries.length &&
          _entries[rightIndex].priority < _entries[smallestIndex].priority) {
        smallestIndex = rightIndex;
      }
      if (smallestIndex == currentIndex) {
        return;
      }

      _swap(currentIndex, smallestIndex);
      currentIndex = smallestIndex;
    }
  }

  void _swap(int leftIndex, int rightIndex) {
    final _QueueEntry left = _entries[leftIndex];
    _entries[leftIndex] = _entries[rightIndex];
    _entries[rightIndex] = left;
  }
}
