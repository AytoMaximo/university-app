import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:rtu_mirea_app/map/models/campus_model.dart';
import 'package:rtu_mirea_app/map/models/floor_model.dart';
import 'package:rtu_mirea_app/map/models/map_room_search_entry.dart';
import 'package:rtu_mirea_app/map/models/map_route_result.dart';
import 'package:rtu_mirea_app/map/models/map_route_segment.dart';
import 'package:rtu_mirea_app/map/services/map_synthetic_object_service.dart';
import 'package:rtu_mirea_app/map/services/svg_path_parser.dart';
import 'package:xml/xml.dart' as xml;

class MapRoutingService {
  final Map<String, List<_RouteFloorData>> _campusCache =
      <String, List<_RouteFloorData>>{};
  final Map<String, Future<List<_RouteFloorData>>> _campusLoadFutures =
      <String, Future<List<_RouteFloorData>>>{};
  final Map<String, _RouteGraph> _baseGraphCache = <String, _RouteGraph>{};
  final Map<String, Future<_RouteGraph>> _baseGraphBuildFutures =
      <String, Future<_RouteGraph>>{};

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
      throw ArgumentError('Выберите разные объекты для маршрута.');
    }

    final CampusModel campus = _findCampus(
      availableCampuses: availableCampuses,
      campusId: start.campus.id,
    );
    final List<_RouteFloorData> floors = await _loadCampusFloors(campus);
    final _RouteGraph graph =
        (await _baseGraphForCampus(campusId: campus.id, floors: floors)).copy();
    final int startNode = _addEndpointNode(
      graph: graph,
      floors: floors,
      entry: start,
      label: 'начального объекта',
    );
    final int destinationNode = _addEndpointNode(
      graph: graph,
      floors: floors,
      entry: destination,
      label: 'конечного объекта',
    );
    final List<int> path = _findShortestPath(
      graph: graph,
      startNode: startNode,
      destinationNode: destinationNode,
    );
    if (path.isEmpty) {
      throw StateError('Маршрут между выбранными объектами не найден.');
    }

    return MapRouteResult(
      start: start,
      destination: destination,
      segments: _buildSegments(graph: graph, path: path, floors: floors),
    );
  }

  Future<void> preloadCampus({required CampusModel campus}) async {
    final List<_RouteFloorData> floors = await _loadCampusFloors(campus);
    await _baseGraphForCampus(campusId: campus.id, floors: floors);
  }

  Future<_RouteGraph> _baseGraphForCampus({
    required String campusId,
    required List<_RouteFloorData> floors,
  }) {
    final _RouteGraph? cachedGraph = _baseGraphCache[campusId];
    if (cachedGraph != null) {
      return Future<_RouteGraph>.value(cachedGraph);
    }

    final Future<_RouteGraph>? buildingGraph = _baseGraphBuildFutures[campusId];
    if (buildingGraph != null) {
      return buildingGraph;
    }

    final Future<_RouteGraph> graphFuture = Future<_RouteGraph>(() {
      final _RouteGraph graph = _buildGraph(floors);
      _addStairNodes(graph: graph, floors: floors);
      _baseGraphCache[campusId] = graph;
      return graph;
    }).whenComplete(() {
      _baseGraphBuildFutures.remove(campusId);
    });
    _baseGraphBuildFutures[campusId] = graphFuture;
    return graphFuture;
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

    final Future<List<_RouteFloorData>>? loadingFloors =
        _campusLoadFutures[campus.id];
    if (loadingFloors != null) {
      return loadingFloors;
    }

    final Future<List<_RouteFloorData>> floorsFuture = _loadCampusFloorsFresh(
      campus,
    ).whenComplete(() {
      _campusLoadFutures.remove(campus.id);
    });
    _campusLoadFutures[campus.id] = floorsFuture;
    return floorsFuture;
  }

  Future<List<_RouteFloorData>> _loadCampusFloorsFresh(
    CampusModel campus,
  ) async {
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
    final List<xml.XmlElement> svgElements = svgRoot.descendants
        .whereType<xml.XmlElement>()
        .toList(growable: false);

    final List<_WalkableArea> walkableAreas = <_WalkableArea>[];
    for (final xml.XmlElement element in svgElements) {
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

    final Map<String, _RouteObject> routeTargets = <String, _RouteObject>{};
    final List<_RouteObject> stairs = <_RouteObject>[];
    final List<_BlockedArea> blockedAreas = <_BlockedArea>[];
    for (final xml.XmlElement element in svgElements) {
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

      final _RouteObject routeObject = _RouteObject(
        dataObject: dataObject,
        bounds: path.getBounds(),
      );
      if (type == _RouteObjectType.routeTarget) {
        routeTargets[dataObject] = routeObject;
        if (!_isWalkableRouteTarget(dataObject)) {
          blockedAreas.add(
            _BlockedArea(
              path: path,
              bounds: path.getBounds(),
              label: dataObject,
            ),
          );
        }
      } else if (type == _RouteObjectType.stairs) {
        stairs.add(routeObject);
        blockedAreas.add(
          _BlockedArea(path: path, bounds: path.getBounds(), label: dataObject),
        );
      }
    }

    for (final xml.XmlElement element in svgRoot.descendants
        .whereType<xml.XmlElement>()
        .where(isSyntheticEntranceExitElement)) {
      if (dataObjectElements.contains(element)) {
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
      if (bounds.isEmpty) {
        continue;
      }

      final String dataObject = syntheticEntranceExitDataObject(
        assetPath: floor.svgPath,
        bounds: bounds,
      );
      routeTargets[dataObject] = _RouteObject(
        dataObject: dataObject,
        bounds: bounds,
      );
    }

    for (int index = 0; index < svgElements.length; index += 1) {
      final xml.XmlElement element = svgElements[index];
      if (!_isBlockedRectangleElement(element, dataObjectElements)) {
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

      blockedAreas.add(
        _BlockedArea(
          path: path,
          bounds: bounds,
          label: _blockedRectangleLabel(bounds),
        ),
      );
    }

    final Set<_GridKey> walkableKeys = _buildWalkableKeys(
      walkableAreas: walkableAreas,
      blockedAreas: blockedAreas,
    );
    if (walkableKeys.isEmpty) {
      throw StateError(
        'На этаже ${floor.number} корпуса В-78 не найден walkable-слой.',
      );
    }

    return _RouteFloorData(
      floor: floor,
      walkableAreas: walkableAreas,
      blockedAreas: blockedAreas,
      walkableKeys: walkableKeys,
      routeTargets: routeTargets,
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

    final String? fill = SvgPathParser.fillValue(element);
    return _isWalkableFill(fill);
  }

  bool _isWalkableFill(String? fill) {
    return fill == '#262a34' || fill == '#f8f8f8' || fill == '#22c55e';
  }

  bool _isWalkableRouteTarget(String dataObject) {
    return syntheticMapObjectTypeFromDataObject(dataObject) ==
        MapObjectType.entranceExit;
  }

  bool _isBlockedRectangleElement(
    xml.XmlElement element,
    HashSet<xml.XmlElement> dataObjectElements,
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

    return !_isWalkableFill(fill);
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
    required HashSet<xml.XmlElement> dataObjectElements,
    required Map<String, xml.XmlElement> elementsById,
  }) {
    for (int index = startIndex; index < elements.length; index += 1) {
      final xml.XmlElement element = elements[index];
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
      if (path.getBounds().contains(point) && path.contains(point)) {
        return true;
      }
    }

    return false;
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
    if (dataObject.contains('__r__') ||
        dataObject.contains('__c__') ||
        dataObject.contains('__t__') ||
        dataObject.contains('__e__')) {
      return _RouteObjectType.routeTarget;
    }
    if (dataObject.contains('__s__')) {
      return _RouteObjectType.stairs;
    }

    return null;
  }

  Set<_GridKey> _buildWalkableKeys({
    required List<_WalkableArea> walkableAreas,
    required List<_BlockedArea> blockedAreas,
  }) {
    final Set<_GridKey> keys = <_GridKey>{};
    for (final _WalkableArea area in walkableAreas) {
      final int left = (area.bounds.left / _gridStep).floor();
      final int right = (area.bounds.right / _gridStep).ceil();
      final int top = (area.bounds.top / _gridStep).floor();
      final int bottom = (area.bounds.bottom / _gridStep).ceil();
      for (int x = left; x <= right; x += 1) {
        for (int y = top; y <= bottom; y += 1) {
          final Offset point = _pointFromKey(_GridKey(x: x, y: y));
          if (area.path.contains(point) &&
              _pointHasRouteClearance(
                point: point,
                walkableAreas: walkableAreas,
                blockedAreas: blockedAreas,
                allowedStart: null,
                allowedEnd: null,
              )) {
            keys.add(_GridKey(x: x, y: y));
          }
        }
      }
    }

    return _removeSmallWalkableComponents(keys);
  }

  Set<_GridKey> _removeSmallWalkableComponents(Set<_GridKey> keys) {
    final Set<_GridKey> retainedKeys = <_GridKey>{};

    for (final Set<_GridKey> component in _walkableComponents(keys)) {
      if (component.length < _minimumWalkableComponentSize) {
        continue;
      }

      retainedKeys.addAll(component);
    }

    return retainedKeys;
  }

  List<Set<_GridKey>> _walkableComponents(Set<_GridKey> keys) {
    final List<Set<_GridKey>> components = <Set<_GridKey>>[];
    final Set<_GridKey> visitedKeys = <_GridKey>{};

    for (final _GridKey key in keys) {
      if (visitedKeys.contains(key)) {
        continue;
      }

      components.add(
        _collectWalkableComponent(
          start: key,
          keys: keys,
          visitedKeys: visitedKeys,
        ),
      );
    }

    return components;
  }

  Set<_GridKey> _collectWalkableComponent({
    required _GridKey start,
    required Set<_GridKey> keys,
    required Set<_GridKey> visitedKeys,
  }) {
    final Queue<_GridKey> queue = Queue<_GridKey>()..add(start);
    final Set<_GridKey> component = <_GridKey>{};
    visitedKeys.add(start);

    while (queue.isNotEmpty) {
      final _GridKey current = queue.removeFirst();
      component.add(current);

      for (final _GridDirection direction in _gridDirections) {
        final _GridKey neighbor = _GridKey(
          x: current.x + direction.dx,
          y: current.y + direction.dy,
        );
        if (!keys.contains(neighbor) || visitedKeys.contains(neighbor)) {
          continue;
        }

        visitedKeys.add(neighbor);
        queue.add(neighbor);
      }
    }

    return component;
  }

  _RouteGraph _buildGraph(List<_RouteFloorData> floors) {
    final _RouteGraph graph = _RouteGraph();
    for (final _RouteFloorData floorData in floors) {
      final Map<_GridKey, int> floorNodes = <_GridKey, int>{};
      graph.floorDataById[floorData.floor.id] = floorData;
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
      }
      graph.gridNodesByFloor[floorData.floor.id] = floorNodes;
      _addWalkableComponentBridges(
        graph: graph,
        floorData: floorData,
        floorNodes: floorNodes,
      );
    }

    return graph;
  }

  void _addWalkableComponentBridges({
    required _RouteGraph graph,
    required _RouteFloorData floorData,
    required Map<_GridKey, int> floorNodes,
  }) {
    final List<Set<_GridKey>> components = _walkableComponents(
      floorData.walkableKeys,
    );
    if (components.length < 2) {
      return;
    }

    final Map<_GridKey, int> componentIndexes = <_GridKey, int>{};
    for (int index = 0; index < components.length; index += 1) {
      for (final _GridKey key in components[index]) {
        componentIndexes[key] = index;
      }
    }

    final Map<String, _ComponentBridge> bridges = <String, _ComponentBridge>{};
    final int maxGridOffset =
        (_walkableComponentBridgeDistance / _gridStep).ceil();
    final double maxDistanceSquared =
        _walkableComponentBridgeDistance * _walkableComponentBridgeDistance;
    final Set<_GridKey> bridgeCandidateKeys = _bridgeCandidateKeys(
      components: components,
      componentIndexes: componentIndexes,
    );

    for (final _GridKey sourceKey in bridgeCandidateKeys) {
      final int? sourceComponentIndex = componentIndexes[sourceKey];
      final int? sourceNodeIndex = floorNodes[sourceKey];
      if (sourceComponentIndex == null || sourceNodeIndex == null) {
        continue;
      }

      for (int dx = -maxGridOffset; dx <= maxGridOffset; dx += 1) {
        for (int dy = -maxGridOffset; dy <= maxGridOffset; dy += 1) {
          if (dx == 0 && dy == 0) {
            continue;
          }

          final double distanceSquared =
              (dx * dx + dy * dy).toDouble() * _gridStep * _gridStep;
          if (distanceSquared > maxDistanceSquared) {
            continue;
          }

          final _GridKey targetKey = _GridKey(
            x: sourceKey.x + dx,
            y: sourceKey.y + dy,
          );
          final int? targetComponentIndex = componentIndexes[targetKey];
          final int? targetNodeIndex = floorNodes[targetKey];
          if (targetComponentIndex == null ||
              targetNodeIndex == null ||
              targetComponentIndex == sourceComponentIndex) {
            continue;
          }

          final Offset sourcePoint = _pointFromKey(sourceKey);
          final Offset targetPoint = _pointFromKey(targetKey);
          if (!_lineIsInsideWalkableAreas(
            start: sourcePoint,
            end: targetPoint,
            walkableAreas: floorData.walkableAreas,
            blockedAreas: floorData.blockedAreas,
            allowedStart: null,
            allowedEnd: null,
          )) {
            continue;
          }

          final int leftComponentIndex = math.min(
            sourceComponentIndex,
            targetComponentIndex,
          );
          final int rightComponentIndex = math.max(
            sourceComponentIndex,
            targetComponentIndex,
          );
          final String bridgeKey = '$leftComponentIndex:$rightComponentIndex';
          final double distance = math.sqrt(distanceSquared);
          final _ComponentBridge? currentBridge = bridges[bridgeKey];
          if (currentBridge != null && currentBridge.distance <= distance) {
            continue;
          }

          bridges[bridgeKey] = _ComponentBridge(
            fromNodeIndex: sourceNodeIndex,
            toNodeIndex: targetNodeIndex,
            distance: distance,
          );
        }
      }
    }

    for (final _ComponentBridge bridge in bridges.values) {
      graph.addEdge(
        from: bridge.fromNodeIndex,
        to: bridge.toNodeIndex,
        weight: bridge.distance * _walkableComponentBridgeWeightMultiplier,
      );
    }
  }

  Set<_GridKey> _bridgeCandidateKeys({
    required List<Set<_GridKey>> components,
    required Map<_GridKey, int> componentIndexes,
  }) {
    final Set<_GridKey> keys = <_GridKey>{};
    for (final Set<_GridKey> component in components) {
      for (final _GridKey key in component) {
        if (_isComponentBoundaryKey(
          key: key,
          componentIndex: componentIndexes[key],
          componentIndexes: componentIndexes,
        )) {
          keys.add(key);
        }
      }
    }

    return keys;
  }

  bool _isComponentBoundaryKey({
    required _GridKey key,
    required int? componentIndex,
    required Map<_GridKey, int> componentIndexes,
  }) {
    if (componentIndex == null) {
      return false;
    }

    for (final _GridDirection direction in _gridDirections) {
      final _GridKey neighbor = _GridKey(
        x: key.x + direction.dx,
        y: key.y + direction.dy,
      );
      if (componentIndexes[neighbor] != componentIndex) {
        return true;
      }
    }

    return false;
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
    final _RouteObject? routeTarget = floorData.routeTargets[entry.roomId];
    if (routeTarget == null) {
      throw StateError('Контур $label ${entry.name} не найден на карте.');
    }

    final int nodeIndex = graph.addNode(
      _RouteNode(
        floorId: floorData.floor.id,
        floorNumber: floorData.floor.number,
        point: routeTarget.bounds.center,
        gridKey: null,
      ),
    );
    final List<_GridNodeDistance> nearbyGridNodes = _findNearbyGridNodes(
      graph: graph,
      floorData: floorData,
      candidates: _connectionCandidates(routeTarget.bounds),
      maxDistance: _roomConnectionMaxDistance,
    );
    for (final _GridNodeDistance gridNode in nearbyGridNodes) {
      graph.addEdge(
        from: nodeIndex,
        to: gridNode.nodeIndex,
        weight: gridNode.distance,
      );
    }

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
        final List<_GridNodeDistance> nearbyGridNodes;
        try {
          nearbyGridNodes = _findNearbyGridNodes(
            graph: graph,
            floorData: floorData,
            candidates: _connectionCandidates(stair.bounds),
            maxDistance: _stairConnectionMaxDistance,
          );
        } on StateError catch (error) {
          throw StateError(
            'Не найден ближайший коридор для лестницы ${stair.dataObject} '
            'на этаже ${floorData.floor.number}: $error. '
            '${_stairConnectionDebug(floorData: floorData, bounds: stair.bounds)}',
          );
        }
        for (final _GridNodeDistance gridNode in nearbyGridNodes) {
          graph.addEdge(
            from: nodeIndex,
            to: gridNode.nodeIndex,
            weight: gridNode.distance + _stairAccessWeight,
          );
        }
        stairNodes.add(
          _StairNode(
            nodeIndex: nodeIndex,
            center: stair.bounds.center,
            objectId: _stairObjectId(stair.dataObject),
          ),
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
          if (!_canConnectStairsByCoordinates(
                lower: lower,
                upper: upper,
                lowerStairs: lowerStairs,
                upperStairs: upperStairs,
                distance: distance,
              ) &&
              !_canConnectStairsByManualPair(lower: lower, upper: upper)) {
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

  bool _canConnectStairsByCoordinates({
    required _StairNode lower,
    required _StairNode upper,
    required List<_StairNode> lowerStairs,
    required List<_StairNode> upperStairs,
    required double distance,
  }) {
    if (distance > _stairCoordinateMatchingTolerance) {
      return false;
    }

    return _isNearestStairMatch(
      lower: lower,
      upper: upper,
      lowerStairs: lowerStairs,
      upperStairs: upperStairs,
    );
  }

  bool _canConnectStairsByManualPair({
    required _StairNode lower,
    required _StairNode upper,
  }) {
    return _manualStairLinkIds.contains(
          _manualStairLinkId(lower.objectId, upper.objectId),
        ) ||
        _manualStairLinkIds.contains(
          _manualStairLinkId(upper.objectId, lower.objectId),
        );
  }

  String _manualStairLinkId(String firstObjectId, String secondObjectId) {
    return '$firstObjectId|$secondObjectId';
  }

  String _stairObjectId(String dataObject) {
    final int stairMarkerIndex = dataObject.indexOf('__s__');
    if (stairMarkerIndex < 0) {
      return dataObject;
    }

    return dataObject.substring(stairMarkerIndex + 5);
  }

  bool _isNearestStairMatch({
    required _StairNode lower,
    required _StairNode upper,
    required List<_StairNode> lowerStairs,
    required List<_StairNode> upperStairs,
  }) {
    final _StairNode? nearestUpper = _nearestStairNode(
      center: lower.center,
      stairs: upperStairs,
    );
    final _StairNode? nearestLower = _nearestStairNode(
      center: upper.center,
      stairs: lowerStairs,
    );

    return nearestUpper?.nodeIndex == upper.nodeIndex ||
        nearestLower?.nodeIndex == lower.nodeIndex;
  }

  _StairNode? _nearestStairNode({
    required Offset center,
    required List<_StairNode> stairs,
  }) {
    _StairNode? nearestStair;
    double nearestDistance = double.infinity;

    for (final _StairNode stair in stairs) {
      final double distance = (center - stair.center).distance;
      if (distance >= nearestDistance) {
        continue;
      }

      nearestDistance = distance;
      nearestStair = stair;
    }

    return nearestStair;
  }

  List<_GridNodeDistance> _findNearbyGridNodes({
    required _RouteGraph graph,
    required _RouteFloorData floorData,
    required List<Offset> candidates,
    required double maxDistance,
  }) {
    final Map<_GridKey, int> floorGridNodes =
        graph.gridNodesByFloor[floorData.floor.id] ?? <_GridKey, int>{};
    final Set<int> nodeIndexes = _nearbyNodeIndexes(
      floorGridNodes: floorGridNodes,
      candidates: candidates,
      maxDistance: maxDistance,
    );
    final List<_GridNodeDistance> nearbyNodes = <_GridNodeDistance>[];

    for (final int nodeIndex in nodeIndexes) {
      final Offset point = graph.nodes[nodeIndex].point;
      double nearestCandidateDistance = double.infinity;
      for (final Offset candidate in candidates) {
        final double distance = (point - candidate).distance;
        if (distance < nearestCandidateDistance) {
          nearestCandidateDistance = distance;
        }
      }
      if (nearestCandidateDistance > maxDistance) {
        continue;
      }

      nearbyNodes.add(
        _GridNodeDistance(
          nodeIndex: nodeIndex,
          distance: nearestCandidateDistance,
        ),
      );
    }

    if (nearbyNodes.isEmpty) {
      throw StateError(
        'Не найден ближайший коридор на этаже ${floorData.floor.number}.',
      );
    }

    nearbyNodes.sort(
      (_GridNodeDistance left, _GridNodeDistance right) =>
          left.distance.compareTo(right.distance),
    );

    return nearbyNodes
        .take(_maximumConnectionNodeCount)
        .toList(growable: false);
  }

  Set<int> _nearbyNodeIndexes({
    required Map<_GridKey, int> floorGridNodes,
    required List<Offset> candidates,
    required double maxDistance,
  }) {
    final Set<int> nodeIndexes = <int>{};
    final int maxGridOffset = (maxDistance / _gridStep).ceil();

    for (final Offset candidate in candidates) {
      final int centerX = (candidate.dx / _gridStep).round();
      final int centerY = (candidate.dy / _gridStep).round();
      for (int dx = -maxGridOffset; dx <= maxGridOffset; dx += 1) {
        for (int dy = -maxGridOffset; dy <= maxGridOffset; dy += 1) {
          final _GridKey key = _GridKey(x: centerX + dx, y: centerY + dy);
          final int? nodeIndex = floorGridNodes[key];
          if (nodeIndex == null) {
            continue;
          }

          final Offset point = _pointFromKey(key);
          if ((point - candidate).distance > maxDistance) {
            continue;
          }

          nodeIndexes.add(nodeIndex);
        }
      }
    }

    return nodeIndexes;
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

    final List<_RouteEdge>? cachedGridEdges = graph.gridEdges[nodeIndex];
    if (cachedGridEdges != null) {
      yield* cachedGridEdges;
      return;
    }

    final Map<_GridKey, int>? floorGridNodes =
        graph.gridNodesByFloor[node.floorId];
    if (floorGridNodes == null) {
      return;
    }
    final _RouteFloorData? floorData = graph.floorDataById[node.floorId];
    if (floorData == null) {
      return;
    }

    final List<_RouteEdge> gridEdges = <_RouteEdge>[];
    for (final _GridDirection direction in _gridDirections) {
      final _GridKey neighborKey = _GridKey(
        x: key.x + direction.dx,
        y: key.y + direction.dy,
      );
      final int? neighborIndex = floorGridNodes[neighborKey];
      if (neighborIndex == null) {
        continue;
      }
      final Offset neighborPoint = graph.nodes[neighborIndex].point;
      if (!_lineIsWalkable(
        start: node.point,
        end: neighborPoint,
        walkableAreas: floorData.walkableAreas,
        walkableKeys: floorData.walkableKeys,
        blockedAreas: floorData.blockedAreas,
      )) {
        continue;
      }

      gridEdges.add(
        _RouteEdge(to: neighborIndex, weight: direction.weight * _gridStep),
      );
    }
    graph.gridEdges[nodeIndex] = gridEdges;
    yield* gridEdges;
  }

  List<MapRouteSegment> _buildSegments({
    required _RouteGraph graph,
    required List<int> path,
    required List<_RouteFloorData> floors,
  }) {
    final List<MapRouteSegment> segments = <MapRouteSegment>[];
    final Map<String, _RouteFloorData> floorDataById =
        <String, _RouteFloorData>{
          for (final _RouteFloorData floorData in floors)
            floorData.floor.id: floorData,
        };
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
          floorData:
              currentFloorId == null ? null : floorDataById[currentFloorId],
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
      floorData: currentFloorId == null ? null : floorDataById[currentFloorId],
    );

    return segments;
  }

  void _addSegment({
    required List<MapRouteSegment> segments,
    required String? floorId,
    required int? floorNumber,
    required List<Offset> points,
    required _RouteFloorData? floorData,
  }) {
    if (floorId == null || floorNumber == null || points.isEmpty) {
      return;
    }

    final List<Offset> segmentPoints =
        floorData == null
            ? _simplifyPoints(points)
            : _smoothPoints(points: points, floorData: floorData);

    segments.add(
      MapRouteSegment(
        floorId: floorId,
        floorNumber: floorNumber,
        points: segmentPoints,
      ),
    );
  }

  List<Offset> _smoothPoints({
    required List<Offset> points,
    required _RouteFloorData floorData,
  }) {
    if (points.length < 3) {
      return _simplifyPoints(points);
    }

    final List<Offset> smoothed = <Offset>[points.first];
    int anchorIndex = 0;
    while (anchorIndex < points.length - 1) {
      int nextIndex = points.length - 1;
      while (nextIndex > anchorIndex + 1 &&
          !_lineIsWalkable(
            start: points[anchorIndex],
            end: points[nextIndex],
            walkableAreas: floorData.walkableAreas,
            walkableKeys: floorData.walkableKeys,
            blockedAreas: floorData.blockedAreas,
          )) {
        nextIndex -= 1;
      }

      smoothed.add(points[nextIndex]);
      anchorIndex = nextIndex;
    }

    return _simplifyPoints(smoothed);
  }

  bool _lineIsWalkable({
    required Offset start,
    required Offset end,
    required List<_WalkableArea> walkableAreas,
    required Set<_GridKey> walkableKeys,
    required List<_BlockedArea> blockedAreas,
  }) {
    final double distance = (end - start).distance;
    if (distance == 0) {
      return true;
    }

    final int steps = math.max(2, (distance / (_gridStep / 2)).ceil());
    for (int index = 1; index < steps; index += 1) {
      final double ratio = index / steps;
      final Offset point = Offset.lerp(start, end, ratio)!;
      if (!_pointHasRouteClearance(
        point: point,
        walkableAreas: walkableAreas,
        blockedAreas: blockedAreas,
        allowedStart: start,
        allowedEnd: end,
      )) {
        return false;
      }
      if (!_pointIsWalkable(point: point, walkableKeys: walkableKeys)) {
        return false;
      }
    }

    return true;
  }

  bool _lineIsInsideWalkableAreas({
    required Offset start,
    required Offset end,
    required List<_WalkableArea> walkableAreas,
    required List<_BlockedArea> blockedAreas,
    required Offset? allowedStart,
    required Offset? allowedEnd,
  }) {
    final double distance = (end - start).distance;
    final int steps = math.max(2, (distance / (_gridStep / 3)).ceil());
    for (int index = 0; index <= steps; index += 1) {
      final double ratio = index / steps;
      final Offset point = Offset.lerp(start, end, ratio)!;
      if (!_pointHasRouteClearance(
        point: point,
        walkableAreas: walkableAreas,
        blockedAreas: blockedAreas,
        allowedStart: allowedStart,
        allowedEnd: allowedEnd,
      )) {
        return false;
      }
    }

    return true;
  }

  bool _pointIsInsideWalkableAreas({
    required Offset point,
    required List<_WalkableArea> walkableAreas,
  }) {
    for (final _WalkableArea walkableArea in walkableAreas) {
      if (!walkableArea.bounds.contains(point)) {
        continue;
      }
      if (walkableArea.path.contains(point)) {
        return true;
      }
    }

    return false;
  }

  bool _pointHasRouteClearance({
    required Offset point,
    required List<_WalkableArea> walkableAreas,
    required List<_BlockedArea> blockedAreas,
    required Offset? allowedStart,
    required Offset? allowedEnd,
  }) {
    if (!_pointCanContainPedestrian(
      point: point,
      walkableAreas: walkableAreas,
      blockedAreas: blockedAreas,
      allowedStart: allowedStart,
      allowedEnd: allowedEnd,
    )) {
      return false;
    }

    for (final Offset clearanceOffset in _pedestrianClearanceOffsets) {
      if (_pointIsInsideBlockedAreas(
        point: point + clearanceOffset,
        blockedAreas: blockedAreas,
        allowedStart: allowedStart,
        allowedEnd: allowedEnd,
      )) {
        return false;
      }
    }

    return true;
  }

  bool _pointCanContainPedestrian({
    required Offset point,
    required List<_WalkableArea> walkableAreas,
    required List<_BlockedArea> blockedAreas,
    required Offset? allowedStart,
    required Offset? allowedEnd,
  }) {
    if (!_pointIsInsideWalkableAreas(
      point: point,
      walkableAreas: walkableAreas,
    )) {
      return false;
    }

    return !_pointIsInsideBlockedAreas(
      point: point,
      blockedAreas: blockedAreas,
      allowedStart: allowedStart,
      allowedEnd: allowedEnd,
    );
  }

  bool _pointIsInsideBlockedAreas({
    required Offset point,
    required List<_BlockedArea> blockedAreas,
    required Offset? allowedStart,
    required Offset? allowedEnd,
  }) {
    for (final _BlockedArea blockedArea in blockedAreas) {
      if (!blockedArea.bounds.contains(point)) {
        continue;
      }
      if (!blockedArea.path.contains(point)) {
        continue;
      }
      if (_blockedAreaContainsAllowedPoint(
        blockedArea: blockedArea,
        allowedPoint: allowedStart,
      )) {
        continue;
      }
      if (_blockedAreaContainsAllowedPoint(
        blockedArea: blockedArea,
        allowedPoint: allowedEnd,
      )) {
        continue;
      }

      return true;
    }

    return false;
  }

  bool _blockedAreaContainsAllowedPoint({
    required _BlockedArea blockedArea,
    required Offset? allowedPoint,
  }) {
    if (allowedPoint == null) {
      return false;
    }
    if (!blockedArea.bounds.contains(allowedPoint)) {
      return false;
    }

    return blockedArea.path.contains(allowedPoint);
  }

  String _stairConnectionDebug({
    required _RouteFloorData floorData,
    required Rect bounds,
  }) {
    final List<Offset> candidates = _connectionCandidates(bounds);
    final int maxGridOffset = (_stairConnectionMaxDistance / _gridStep).ceil();
    int rawWalkableCount = 0;
    int retainedWalkableCount = 0;
    double nearestRawWalkableDistance = double.infinity;
    double nearestRetainedWalkableDistance = double.infinity;
    final Set<String> blockerLabels = <String>{};

    for (final Offset candidate in candidates) {
      final int centerX = (candidate.dx / _gridStep).round();
      final int centerY = (candidate.dy / _gridStep).round();
      for (int dx = -maxGridOffset; dx <= maxGridOffset; dx += 1) {
        for (int dy = -maxGridOffset; dy <= maxGridOffset; dy += 1) {
          final _GridKey key = _GridKey(x: centerX + dx, y: centerY + dy);
          final Offset point = _pointFromKey(key);
          final double distance = (point - candidate).distance;
          if (distance > _stairConnectionMaxDistance) {
            continue;
          }

          if (_pointIsInsideWalkableAreas(
            point: point,
            walkableAreas: floorData.walkableAreas,
          )) {
            rawWalkableCount += 1;
            nearestRawWalkableDistance = math.min(
              nearestRawWalkableDistance,
              distance,
            );
          }
          if (floorData.walkableKeys.contains(key)) {
            retainedWalkableCount += 1;
            nearestRetainedWalkableDistance = math.min(
              nearestRetainedWalkableDistance,
              distance,
            );
          }

          final _BlockedArea? blockedArea = _blockedAreaAtPoint(
            point: point,
            blockedAreas: floorData.blockedAreas,
          );
          if (blockedArea != null) {
            blockerLabels.add(blockedArea.label);
          }
        }
      }
    }

    final String nearestRaw =
        nearestRawWalkableDistance.isFinite
            ? nearestRawWalkableDistance.toStringAsFixed(1)
            : 'none';
    final String nearestRetained =
        nearestRetainedWalkableDistance.isFinite
            ? nearestRetainedWalkableDistance.toStringAsFixed(1)
            : 'none';
    final String blockers = blockerLabels.take(6).join(', ');
    return 'rawWalkable=$rawWalkableCount, retainedWalkable='
        '$retainedWalkableCount, nearestRaw=$nearestRaw, '
        'nearestRetained=$nearestRetained, blockers=[$blockers]';
  }

  _BlockedArea? _blockedAreaAtPoint({
    required Offset point,
    required List<_BlockedArea> blockedAreas,
  }) {
    for (final _BlockedArea blockedArea in blockedAreas) {
      if (!blockedArea.bounds.contains(point)) {
        continue;
      }
      if (blockedArea.path.contains(point)) {
        return blockedArea;
      }
    }

    return null;
  }

  String _blockedRectangleLabel(Rect bounds) {
    return 'rect:${bounds.left.round()}:${bounds.top.round()}:'
        '${bounds.width.round()}:${bounds.height.round()}';
  }

  bool _pointIsWalkable({
    required Offset point,
    required Set<_GridKey> walkableKeys,
  }) {
    final int centerX = (point.dx / _gridStep).round();
    final int centerY = (point.dy / _gridStep).round();
    for (int dx = -1; dx <= 1; dx += 1) {
      for (int dy = -1; dy <= 1; dy += 1) {
        final _GridKey key = _GridKey(x: centerX + dx, y: centerY + dy);
        if (!walkableKeys.contains(key)) {
          continue;
        }

        final Offset gridPoint = _pointFromKey(key);
        if ((gridPoint - point).distance <= _gridStep * 0.75) {
          return true;
        }
      }
    }

    return false;
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

  static const double _gridStep = 16;
  static const double _stairCoordinateMatchingTolerance = 80;
  static const double _roomConnectionMaxDistance = 360;
  static const double _stairConnectionMaxDistance = 240;
  static const double _stairAccessWeight = 1200;
  static const double _floorTransferWeight = 420;
  static const double _walkableComponentBridgeDistance = 336;
  static const double _walkableComponentBridgeWeightMultiplier = 2;
  static const double _pedestrianClearanceRadius = 16;
  static const double _pedestrianDiagonalClearance = 11.313708498984761;
  static const int _minimumWalkableComponentSize = 4;
  static const int _maximumConnectionNodeCount = 12;
  static const List<Offset> _pedestrianClearanceOffsets = <Offset>[
    Offset(_pedestrianClearanceRadius, 0),
    Offset(-_pedestrianClearanceRadius, 0),
    Offset(0, _pedestrianClearanceRadius),
    Offset(0, -_pedestrianClearanceRadius),
    Offset(_pedestrianDiagonalClearance, _pedestrianDiagonalClearance),
    Offset(-_pedestrianDiagonalClearance, _pedestrianDiagonalClearance),
    Offset(_pedestrianDiagonalClearance, -_pedestrianDiagonalClearance),
    Offset(-_pedestrianDiagonalClearance, -_pedestrianDiagonalClearance),
  ];
  static final Set<String> _manualStairLinkIds = <String>{
    '2318:6530|2318:5360',
    '2318:4486|2318:4298',
  };
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

enum _RouteObjectType { routeTarget, stairs }

class _WalkableArea {
  const _WalkableArea({required this.path, required this.bounds});

  final Path path;
  final Rect bounds;
}

class _BlockedArea {
  const _BlockedArea({
    required this.path,
    required this.bounds,
    required this.label,
  });

  final Path path;
  final Rect bounds;
  final String label;
}

class _RouteObject {
  const _RouteObject({required this.dataObject, required this.bounds});

  final String dataObject;
  final Rect bounds;
}

class _RouteFloorData {
  const _RouteFloorData({
    required this.floor,
    required this.walkableAreas,
    required this.blockedAreas,
    required this.walkableKeys,
    required this.routeTargets,
    required this.stairs,
  });

  final FloorModel floor;
  final List<_WalkableArea> walkableAreas;
  final List<_BlockedArea> blockedAreas;
  final Set<_GridKey> walkableKeys;
  final Map<String, _RouteObject> routeTargets;
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

class _GridNodeDistance {
  const _GridNodeDistance({required this.nodeIndex, required this.distance});

  final int nodeIndex;
  final double distance;
}

class _ComponentBridge {
  const _ComponentBridge({
    required this.fromNodeIndex,
    required this.toNodeIndex,
    required this.distance,
  });

  final int fromNodeIndex;
  final int toNodeIndex;
  final double distance;
}

class _RouteGraph {
  _RouteGraph() : gridEdges = <int, List<_RouteEdge>>{};

  _RouteGraph._copyWithSharedGridEdges({required this.gridEdges});

  final List<_RouteNode> nodes = <_RouteNode>[];
  final Map<int, List<_RouteEdge>> edges = <int, List<_RouteEdge>>{};
  final Map<int, List<_RouteEdge>> gridEdges;
  final Map<String, Map<_GridKey, int>> gridNodesByFloor =
      <String, Map<_GridKey, int>>{};
  final Map<String, _RouteFloorData> floorDataById =
      <String, _RouteFloorData>{};

  _RouteGraph copy() {
    final _RouteGraph graph = _RouteGraph._copyWithSharedGridEdges(
      gridEdges: gridEdges,
    );
    graph.nodes.addAll(nodes);
    for (final MapEntry<int, List<_RouteEdge>> entry in edges.entries) {
      graph.edges[entry.key] = List<_RouteEdge>.of(entry.value);
    }
    for (final MapEntry<String, Map<_GridKey, int>> entry
        in gridNodesByFloor.entries) {
      graph.gridNodesByFloor[entry.key] = Map<_GridKey, int>.of(entry.value);
    }
    graph.floorDataById.addAll(floorDataById);

    return graph;
  }

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
  const _StairNode({
    required this.nodeIndex,
    required this.center,
    required this.objectId,
  });

  final int nodeIndex;
  final Offset center;
  final String objectId;
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
