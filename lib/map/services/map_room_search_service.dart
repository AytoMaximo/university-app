import 'package:rtu_mirea_app/map/models/map_room_search_entry.dart';

String normalizeMapRoomSearchQuery(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_]+'), '')
      .replaceAll('ё', 'е');
}

bool mapRoomSearchEntryMatchesQuery({
  required MapRoomSearchEntry entry,
  required String query,
}) {
  final String normalizedQuery = normalizeMapRoomSearchQuery(query);
  if (normalizedQuery.isEmpty) {
    return false;
  }

  final String normalizedName = normalizeMapRoomSearchQuery(entry.name);
  return normalizedName.contains(normalizedQuery);
}

List<MapRoomSearchEntry> filterMapRoomSearchEntries({
  required List<MapRoomSearchEntry> entries,
  required String query,
  required int limit,
}) {
  final Iterable<MapRoomSearchEntry> filteredEntries = entries.where(
    (MapRoomSearchEntry entry) =>
        mapRoomSearchEntryMatchesQuery(entry: entry, query: query),
  );

  return filteredEntries.take(limit).toList(growable: false);
}
