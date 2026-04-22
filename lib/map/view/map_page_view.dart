import 'dart:async';

import 'package:app_ui/src/colors/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:rtu_mirea_app/map/map.dart';

typedef SelectedRoomActionBuilder =
    Widget Function(BuildContext context, String roomName);

Widget buildEmptySelectedRoomAction(BuildContext context, String roomName) {
  return const SizedBox.shrink();
}

Widget buildScheduleSearchSelectedRoomAction(
  BuildContext context,
  String roomName,
) {
  if (roomName.isEmpty) {
    return const SizedBox.shrink();
  }

  return TextButton.icon(
    onPressed: () {
      final Uri uri = Uri(
        path: '/schedule/search',
        queryParameters: <String, String>{'query': roomName},
      );
      context.go(uri.toString());
    },
    icon: const Icon(Icons.event_note),
    label: const Text('Расписание аудитории'),
  );
}

class MapPageView extends StatefulWidget {
  const MapPageView({
    super.key,
    required this.controlsBottomOffset,
    required this.selectedRoomActionBuilder,
  });

  final double controlsBottomOffset;
  final SelectedRoomActionBuilder selectedRoomActionBuilder;

  @override
  State<MapPageView> createState() => _MapPageViewState();
}

class _MapPageViewState extends State<MapPageView> {
  static const int _searchLimit = 12;

  late final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode = FocusNode();
  Timer? _hideSearchResultsTimer;
  bool _showSearchResults = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchQueryChanged);
    _searchFocusNode.addListener(_onSearchQueryChanged);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _hideSearchResultsTimer?.cancel();
    _searchController
      ..removeListener(_onSearchQueryChanged)
      ..dispose();
    _searchFocusNode
      ..removeListener(_onSearchQueryChanged)
      ..dispose();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MapBloc>(
      create:
          (_) => MapBloc(
            availableCampuses: universityMapCampuses,
            objectsService: ObjectsService(),
            routingService: MapRoutingService(),
          )..add(MapInitialized()),
      child: Scaffold(
        appBar: AppBar(title: const Text('Карта университета')),
        body: BlocBuilder<MapBloc, MapState>(
          builder: (BuildContext context, MapState state) {
            if (state is MapError) {
              return Center(child: Text(state.message));
            }

            if (state is! MapLoaded) {
              return const Center(child: CircularProgressIndicator());
            }

            final bool isLandscape =
                MediaQuery.of(context).orientation == Orientation.landscape;
            return Stack(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Expanded(
                      child: SvgInteractiveMap(
                        svgAssetPath: state.selectedFloor.svgPath,
                        selectedRoomId: state.selectedRoomId,
                        routeSegments: _currentFloorRouteSegments(state),
                        onRoomSelected: (RoomModel room) {
                          context.read<MapBloc>().add(
                            RoomSelected(room.roomId),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: MediaQuery.of(context).size.width < 560 ? 132 : null,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width < 560 ? null : 420,
                    child: _MapRoomSearchPanel(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      entries: filterMapRoomSearchEntries(
                        entries: state.searchEntries,
                        query: _searchController.text,
                        limit: _searchLimit,
                      ),
                      hasQuery:
                          normalizeMapRoomSearchQuery(
                            _searchController.text,
                          ).isNotEmpty,
                      showResults: _showSearchResults,
                      onEntrySelected: (MapRoomSearchEntry entry) {
                        _hideSearchResultsTimer?.cancel();
                        _searchController.text = entry.name;
                        _searchController.selection = TextSelection.collapsed(
                          offset: entry.name.length,
                        );
                        setState(() {
                          _showSearchResults = false;
                        });
                        FocusScope.of(context).unfocus();
                        context.read<MapBloc>().add(
                          RoomSearchResultSelected(entry),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: SizedBox(
                    width: 100,
                    child: CampusSelector(
                      campuses: universityMapCampuses,
                      selectedCampus: state.selectedCampus,
                      onCampusSelected: (CampusModel campus) {
                        context.read<MapBloc>().add(CampusSelected(campus));
                      },
                    ),
                  ),
                ),
                Positioned(
                  bottom: widget.controlsBottomOffset,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          Theme.of(
                            context,
                          ).extension<AppColors>()!.background02,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        isLandscape
                            ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: state.selectedCampus.floors
                                  .map((FloorModel floor) {
                                    return MapNavigationButton(
                                      floor: floor.number,
                                      isSelected:
                                          state.selectedFloor.number ==
                                          floor.number,
                                      onClick: () {
                                        context.read<MapBloc>().add(
                                          FloorSelected(
                                            floor,
                                            state.selectedCampus,
                                          ),
                                        );
                                      },
                                    );
                                  })
                                  .toList(growable: false),
                            )
                            : Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: state.selectedCampus.floors
                                  .map((FloorModel floor) {
                                    return MapNavigationButton(
                                      floor: floor.number,
                                      isSelected:
                                          state.selectedFloor.number ==
                                          floor.number,
                                      onClick: () {
                                        context.read<MapBloc>().add(
                                          FloorSelected(
                                            floor,
                                            state.selectedCampus,
                                          ),
                                        );
                                      },
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                  ),
                ),
                if (state.selectedRoomId != null)
                  Positioned(
                    left: 16,
                    right: MediaQuery.of(context).size.width < 560 ? 84 : null,
                    bottom: widget.controlsBottomOffset,
                    child: SizedBox(
                      width:
                          MediaQuery.of(context).size.width < 560 ? null : 360,
                      child: _SelectedRoomPanel(
                        roomName: _selectedRoomName(state),
                        selectedRoomEntry: _selectedRoomEntry(state),
                        routeState: state.routeState,
                        selectedRoomActionBuilder:
                            widget.selectedRoomActionBuilder,
                        onSelectRouteStart: (MapRoomSearchEntry entry) {
                          context.read<MapBloc>().add(
                            RouteStartSelected(entry),
                          );
                        },
                        onSelectRouteDestination: (MapRoomSearchEntry entry) {
                          context.read<MapBloc>().add(
                            RouteDestinationSelected(entry),
                          );
                        },
                        onClearRoute: () {
                          context.read<MapBloc>().add(RouteCleared());
                        },
                        onClose: () {
                          context.read<MapBloc>().add(RoomSelectionCleared());
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _onSearchQueryChanged() {
    if (mounted) {
      final bool hasQuery =
          normalizeMapRoomSearchQuery(_searchController.text).isNotEmpty;
      if (_searchFocusNode.hasFocus) {
        _hideSearchResultsTimer?.cancel();
      }
      setState(() {
        if (_searchFocusNode.hasFocus) {
          _showSearchResults = hasQuery;
          return;
        }

        if (!hasQuery) {
          _showSearchResults = false;
        }
      });
      if (!_searchFocusNode.hasFocus) {
        _scheduleSearchResultsHide();
      }
    }
  }

  void _scheduleSearchResultsHide() {
    _hideSearchResultsTimer?.cancel();
    _hideSearchResultsTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _showSearchResults = false;
      });
    });
  }

  MapRoomSearchEntry? _selectedRoomEntry(MapLoaded state) {
    final String? selectedRoomId = state.selectedRoomId;
    if (selectedRoomId == null) {
      return null;
    }

    for (final MapRoomSearchEntry entry in state.searchEntries) {
      if (entry.roomId == selectedRoomId &&
          entry.floor == state.selectedFloor &&
          entry.campus == state.selectedCampus) {
        return entry;
      }
    }

    for (final RoomModel room in state.rooms) {
      if (room.roomId == selectedRoomId) {
        return MapRoomSearchEntry(
          roomId: room.roomId,
          name: room.name,
          campus: state.selectedCampus,
          floor: state.selectedFloor,
        );
      }
    }

    return null;
  }

  String _selectedRoomName(MapLoaded state) {
    final MapRoomSearchEntry? entry = _selectedRoomEntry(state);
    if (entry != null) {
      return entry.name;
    }

    for (final RoomModel room in state.rooms) {
      if (room.roomId == state.selectedRoomId) {
        return room.name;
      }
    }

    return '';
  }

  List<MapRouteSegment> _currentFloorRouteSegments(MapLoaded state) {
    final MapRouteResult? routeResult = state.routeState.result;
    if (routeResult == null) {
      return <MapRouteSegment>[];
    }

    return routeResult.segments
        .where(
          (MapRouteSegment segment) =>
              segment.floorId == state.selectedFloor.id,
        )
        .toList(growable: false);
  }
}

class _MapRoomSearchPanel extends StatelessWidget {
  const _MapRoomSearchPanel({
    required this.controller,
    required this.focusNode,
    required this.entries,
    required this.hasQuery,
    required this.showResults,
    required this.onEntrySelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<MapRoomSearchEntry> entries;
  final bool hasQuery;
  final bool showResults;
  final ValueChanged<MapRoomSearchEntry> onEntrySelected;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    final TextStyle searchTextStyle =
        (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
          color: colors.active,
          height: 1,
        );
    final TextStyle searchHintStyle = searchTextStyle.copyWith(
      color: colors.deactive,
    );

    return Material(
      color: colors.background02,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.14),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 48,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: searchTextStyle,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Найти аудиторию',
                hintStyle: searchHintStyle,
                prefixIcon: const Icon(Icons.search),
                prefixIconConstraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                suffixIcon:
                    hasQuery
                        ? IconButton(
                          tooltip: 'Очистить',
                          icon: const Icon(Icons.close),
                          onPressed: controller.clear,
                        )
                        : null,
                suffixIconConstraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          if (hasQuery && showResults) const Divider(height: 1),
          if (hasQuery && showResults)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child:
                  entries.isEmpty
                      ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Аудитория не найдена',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.deactive),
                          ),
                        ),
                      )
                      : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: entries.length,
                        itemBuilder: (BuildContext context, int index) {
                          final MapRoomSearchEntry entry = entries[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${entry.campus.displayName}, ${_formatFloor(entry.floor.number)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => onEntrySelected(entry),
                          );
                        },
                      ),
            ),
        ],
      ),
    );
  }
}

class _SelectedRoomPanel extends StatelessWidget {
  const _SelectedRoomPanel({
    required this.roomName,
    required this.selectedRoomEntry,
    required this.routeState,
    required this.selectedRoomActionBuilder,
    required this.onSelectRouteStart,
    required this.onSelectRouteDestination,
    required this.onClearRoute,
    required this.onClose,
  });

  final String roomName;
  final MapRoomSearchEntry? selectedRoomEntry;
  final MapRouteState routeState;
  final SelectedRoomActionBuilder selectedRoomActionBuilder;
  final ValueChanged<MapRoomSearchEntry> onSelectRouteStart;
  final ValueChanged<MapRoomSearchEntry> onSelectRouteDestination;
  final VoidCallback onClearRoute;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    final MapRoomSearchEntry? routeEntry = selectedRoomEntry;

    return Material(
      color: colors.background02,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.14),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    roomName.isEmpty ? 'Аудитория' : 'Аудитория $roomName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.active,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Снять выделение',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            if (routeEntry != null) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.trip_origin),
                    label: const Text('Отсюда'),
                    onPressed: () => onSelectRouteStart(routeEntry),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Сюда'),
                    onPressed: () => onSelectRouteDestination(routeEntry),
                  ),
                ],
              ),
            ],
            _RouteStatus(routeState: routeState, onClearRoute: onClearRoute),
            selectedRoomActionBuilder(context, roomName),
          ],
        ),
      ),
    );
  }
}

class _RouteStatus extends StatelessWidget {
  const _RouteStatus({required this.routeState, required this.onClearRoute});

  final MapRouteState routeState;
  final VoidCallback onClearRoute;

  @override
  Widget build(BuildContext context) {
    if (routeState.start == null &&
        routeState.destination == null &&
        routeState.errorMessage == null) {
      return const SizedBox.shrink();
    }

    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    final TextStyle? baseStyle = Theme.of(context).textTheme.bodySmall;
    final String startName =
        routeState.start == null
            ? 'не выбрано'
            : _routeEntryTitle(routeState.start!);
    final String destinationName =
        routeState.destination == null
            ? 'не выбрано'
            : _routeEntryTitle(routeState.destination!);
    final String statusText = _routeStatusText(routeState);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background01,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Маршрут',
                      style: baseStyle?.copyWith(
                        color: colors.active,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Сбросить маршрут',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.clear),
                    onPressed: onClearRoute,
                  ),
                ],
              ),
              Text(
                'От: $startName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseStyle?.copyWith(color: colors.active),
              ),
              Text(
                'До: $destinationName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseStyle?.copyWith(color: colors.active),
              ),
              const SizedBox(height: 4),
              Text(
                statusText,
                style: baseStyle?.copyWith(
                  color:
                      routeState.errorMessage == null
                          ? colors.deactive
                          : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _routeStatusText(MapRouteState routeState) {
  if (routeState.errorMessage != null) {
    return routeState.errorMessage!;
  }

  if (routeState.isBuilding) {
    return 'Строю маршрут...';
  }

  if (routeState.result != null) {
    return 'Маршрут построен';
  }

  if (routeState.start == null || routeState.destination == null) {
    return 'Выберите начало и конец маршрута';
  }

  return 'Маршрут не построен';
}

String _routeEntryTitle(MapRoomSearchEntry entry) {
  if (entry.name.isNotEmpty) {
    return entry.name;
  }

  return entry.roomId;
}

String _formatFloor(int floor) {
  return '$floor этаж';
}
