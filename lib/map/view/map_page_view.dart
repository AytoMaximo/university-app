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
                      showResults: _searchFocusNode.hasFocus,
                      onEntrySelected: (MapRoomSearchEntry entry) {
                        _searchController.text = entry.name;
                        _searchController.selection = TextSelection.collapsed(
                          offset: entry.name.length,
                        );
                        _searchFocusNode.unfocus();
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
                        selectedRoomActionBuilder:
                            widget.selectedRoomActionBuilder,
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
      setState(() {});
    }
  }

  String _selectedRoomName(MapLoaded state) {
    for (final MapRoomSearchEntry entry in state.searchEntries) {
      if (entry.roomId == state.selectedRoomId &&
          entry.floor == state.selectedFloor &&
          entry.campus == state.selectedCampus) {
        return entry.name;
      }
    }

    for (final RoomModel room in state.rooms) {
      if (room.roomId == state.selectedRoomId) {
        return room.name;
      }
    }

    return '';
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

    return Material(
      color: colors.background02,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.14),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Найти аудиторию',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  hasQuery
                      ? IconButton(
                        tooltip: 'Очистить',
                        icon: const Icon(Icons.close),
                        onPressed: controller.clear,
                      )
                      : null,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
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
    required this.selectedRoomActionBuilder,
    required this.onClose,
  });

  final String roomName;
  final SelectedRoomActionBuilder selectedRoomActionBuilder;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;

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
            selectedRoomActionBuilder(context, roomName),
          ],
        ),
      ),
    );
  }
}

String _formatFloor(int floor) {
  return '$floor этаж';
}
