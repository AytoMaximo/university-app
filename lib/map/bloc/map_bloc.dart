import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:rtu_mirea_app/map/map.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  MapBloc({
    required this.availableCampuses,
    required this.objectsService,
    required this.routingService,
  }) : super(const MapInitial()) {
    on<MapInitialized>(_onMapInitialized);
    on<CampusSelected>(_onCampusSelected);
    on<FloorSelected>(_onFloorSelected);
    on<RoomSelected>(_onRoomSelected);
    on<RoomSelectionCleared>(_onRoomSelectionCleared);
    on<RoomSearchResultSelected>(_onRoomSearchResultSelected);
    on<RouteStartSelected>(_onRouteStartSelected);
    on<RouteDestinationSelected>(_onRouteDestinationSelected);
    on<RouteCleared>(_onRouteCleared);
  }

  final List<CampusModel> availableCampuses;
  final ObjectsService objectsService;
  final MapRoutingService routingService;
  final Map<String, (List<RoomModel>, Rect)> _floorRoomsCache =
      <String, (List<RoomModel>, Rect)>{};
  List<MapRoomSearchEntry> _searchEntries = <MapRoomSearchEntry>[];

  Future<void> _onMapInitialized(
    MapInitialized event,
    Emitter<MapState> emit,
  ) async {
    if (availableCampuses.isEmpty) {
      emit(const MapError('Нет доступных кампусов.'));
      return;
    }
    emit(const MapLoading());

    try {
      await objectsService.loadObjects();
      _searchEntries = await _buildSearchEntries();
      final CampusModel campus = availableCampuses.first;
      final FloorModel floor = _defaultFloorForCampus(campus);
      final (List<RoomModel>, Rect) floorData = await _parseFloor(floor);
      emit(
        MapLoaded(
          selectedCampus: campus,
          selectedFloor: floor,
          rooms: _roomsWithSelection(floorData.$1, null),
          searchEntries: _searchEntries,
          routeState: const MapRouteState.empty(),
          boundingRect: floorData.$2,
        ),
      );
    } catch (error) {
      emit(MapError('Ошибка инициализации карты: $error'));
    }
  }

  Future<void> _onCampusSelected(
    CampusSelected event,
    Emitter<MapState> emit,
  ) async {
    emit(const MapLoading());
    try {
      final FloorModel floor = _defaultFloorForCampus(event.selectedCampus);
      final (List<RoomModel>, Rect) floorData = await _parseFloor(floor);
      emit(
        MapLoaded(
          selectedCampus: event.selectedCampus,
          selectedFloor: floor,
          rooms: _roomsWithSelection(floorData.$1, null),
          searchEntries: _searchEntries,
          routeState: const MapRouteState.empty(),
          boundingRect: floorData.$2,
        ),
      );
    } catch (error) {
      emit(MapError('Ошибка загрузки кампуса: $error'));
    }
  }

  Future<void> _onFloorSelected(
    FloorSelected event,
    Emitter<MapState> emit,
  ) async {
    final MapRouteState routeState =
        state is MapLoaded
            ? (state as MapLoaded).routeState
            : const MapRouteState.empty();
    try {
      final (List<RoomModel>, Rect) floorData = await _parseFloor(
        event.selectedFloor,
      );
      emit(
        MapLoaded(
          selectedCampus: event.selectedCampus,
          selectedFloor: event.selectedFloor,
          rooms: _roomsWithSelection(floorData.$1, null),
          searchEntries: _searchEntries,
          routeState: routeState,
          boundingRect: floorData.$2,
        ),
      );
    } catch (error) {
      emit(MapError('Ошибка загрузки этажа: $error'));
    }
  }

  void _onRoomSelected(RoomSelected event, Emitter<MapState> emit) {
    if (state is! MapLoaded) {
      return;
    }

    final MapLoaded currentState = state as MapLoaded;
    emit(
      currentState.copyWith(
        rooms: _roomsWithSelection(currentState.rooms, event.roomId),
        selectedRoomId: event.roomId,
      ),
    );
  }

  void _onRoomSelectionCleared(
    RoomSelectionCleared event,
    Emitter<MapState> emit,
  ) {
    if (state is! MapLoaded) {
      return;
    }

    final MapLoaded currentState = state as MapLoaded;
    emit(currentState.withoutSelectedRoom());
  }

  Future<void> _onRoomSearchResultSelected(
    RoomSearchResultSelected event,
    Emitter<MapState> emit,
  ) async {
    final MapRouteState routeState =
        state is MapLoaded
            ? (state as MapLoaded).routeState
            : const MapRouteState.empty();
    try {
      final (List<RoomModel>, Rect) floorData = await _parseFloor(
        event.searchEntry.floor,
      );
      emit(
        MapLoaded(
          selectedCampus: event.searchEntry.campus,
          selectedFloor: event.searchEntry.floor,
          rooms: _roomsWithSelection(floorData.$1, event.searchEntry.roomId),
          searchEntries: _searchEntries,
          routeState: routeState,
          boundingRect: floorData.$2,
          selectedRoomId: event.searchEntry.roomId,
        ),
      );
    } catch (error) {
      emit(MapError('Ошибка поиска аудитории: $error'));
    }
  }

  Future<void> _onRouteStartSelected(
    RouteStartSelected event,
    Emitter<MapState> emit,
  ) async {
    if (state is! MapLoaded) {
      return;
    }

    final MapLoaded currentState = state as MapLoaded;
    await _emitRouteState(
      routeState: currentState.routeState.withStart(event.searchEntry),
      emit: emit,
    );
  }

  Future<void> _onRouteDestinationSelected(
    RouteDestinationSelected event,
    Emitter<MapState> emit,
  ) async {
    if (state is! MapLoaded) {
      return;
    }

    final MapLoaded currentState = state as MapLoaded;
    await _emitRouteState(
      routeState: currentState.routeState.withDestination(event.searchEntry),
      emit: emit,
    );
  }

  void _onRouteCleared(RouteCleared event, Emitter<MapState> emit) {
    if (state is! MapLoaded) {
      return;
    }

    final MapLoaded currentState = state as MapLoaded;
    emit(currentState.copyWith(routeState: const MapRouteState.empty()));
  }

  Future<void> _emitRouteState({
    required MapRouteState routeState,
    required Emitter<MapState> emit,
  }) async {
    if (state is! MapLoaded) {
      return;
    }

    final MapLoaded currentState = state as MapLoaded;
    emit(currentState.copyWith(routeState: routeState));
    if (!routeState.canBuild) {
      return;
    }

    final MapRoomSearchEntry start = routeState.start!;
    final MapRoomSearchEntry destination = routeState.destination!;
    if (start.roomId == destination.roomId &&
        start.floor.id == destination.floor.id) {
      final MapLoaded loadedState =
          state is MapLoaded ? state as MapLoaded : currentState;
      emit(
        loadedState.copyWith(
          routeState: routeState.withError('Выберите разные аудитории.'),
        ),
      );
      return;
    }

    final MapRouteState buildingState = routeState.asBuilding();
    final MapLoaded loadedBeforeBuild =
        state is MapLoaded ? state as MapLoaded : currentState;
    emit(loadedBeforeBuild.copyWith(routeState: buildingState));
    try {
      final MapRouteResult routeResult = await routingService.buildRoute(
        start: start,
        destination: destination,
        availableCampuses: availableCampuses,
      );
      if (state is! MapLoaded) {
        return;
      }

      final MapLoaded loadedAfterBuild = state as MapLoaded;
      emit(
        loadedAfterBuild.copyWith(
          routeState: routeState.withResult(routeResult),
        ),
      );
    } catch (error) {
      if (state is! MapLoaded) {
        return;
      }

      final MapLoaded loadedAfterError = state as MapLoaded;
      emit(
        loadedAfterError.copyWith(
          routeState: routeState.withError(
            'Не удалось построить маршрут: $error',
          ),
        ),
      );
    }
  }

  Future<(List<RoomModel>, Rect)> _parseFloor(FloorModel floor) async {
    final (List<RoomModel>, Rect)? cachedRooms = _floorRoomsCache[floor.id];
    if (cachedRooms != null) {
      return cachedRooms;
    }

    final (List<RoomModel>, Rect) parsedSvg = await SvgRoomsParser.parseSvg(
      floor.svgPath,
    );
    final List<RoomModel> rooms = parsedSvg.$1
        .map((RoomModel room) {
          final String id = _objectIdFromDataObject(room.roomId);
          final String name =
              room.name.isNotEmpty
                  ? room.name
                  : objectsService.getNameById(id) ?? '';
          return RoomModel(
            roomId: room.roomId,
            name: name,
            path: room.path,
            isSelected: room.isSelected,
          );
        })
        .toList(growable: false);

    final (List<RoomModel>, Rect) parsedFloor = (rooms, parsedSvg.$2);
    _floorRoomsCache[floor.id] = parsedFloor;
    return parsedFloor;
  }

  Future<List<MapRoomSearchEntry>> _buildSearchEntries() async {
    final List<MapRoomSearchEntry> entries = <MapRoomSearchEntry>[];

    for (final CampusModel campus in availableCampuses) {
      for (final FloorModel floor in campus.floors) {
        final (List<RoomModel>, Rect) floorData = await _parseFloor(floor);
        for (final RoomModel room in floorData.$1) {
          if (room.name.isEmpty ||
              !objectsService.isRoom(_objectIdFromDataObject(room.roomId))) {
            continue;
          }

          entries.add(
            MapRoomSearchEntry(
              roomId: room.roomId,
              name: room.name,
              campus: campus,
              floor: floor,
            ),
          );
        }
      }
    }

    entries.sort((MapRoomSearchEntry left, MapRoomSearchEntry right) {
      final int nameComparison = left.name.compareTo(right.name);
      if (nameComparison != 0) {
        return nameComparison;
      }

      final int campusComparison = left.campus.displayName.compareTo(
        right.campus.displayName,
      );
      if (campusComparison != 0) {
        return campusComparison;
      }

      return left.floor.number.compareTo(right.floor.number);
    });

    return entries;
  }

  List<RoomModel> _roomsWithSelection(
    List<RoomModel> rooms,
    String? selectedRoomId,
  ) {
    return rooms
        .map(
          (RoomModel room) => room.copyWith(
            isSelected: selectedRoomId != null && room.roomId == selectedRoomId,
          ),
        )
        .toList(growable: false);
  }

  FloorModel _defaultFloorForCampus(CampusModel campus) {
    for (final FloorModel floor in campus.floors) {
      if (floor.number == 2) {
        return floor;
      }
    }

    return campus.floors.first;
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
}
