import 'dart:ui' as ui;

import 'package:rtu_mirea_app/map/models/map_room_search_entry.dart';
import 'package:rtu_mirea_app/map/services/svg_path_parser.dart';
import 'package:xml/xml.dart' as xml;

const String mapEntranceExitName = 'Вход/выход';

const String _mapEntranceExitFill = '#22c55e';
const String _mapEntranceExitPrefix = '__e__';

bool isSyntheticEntranceExitElement(xml.XmlElement element) {
  return SvgPathParser.fillValue(element) == _mapEntranceExitFill;
}

bool isSyntheticEntranceExitId(String dataObject) {
  return dataObject.contains(_mapEntranceExitPrefix);
}

MapObjectType? syntheticMapObjectTypeFromDataObject(String dataObject) {
  if (isSyntheticEntranceExitId(dataObject)) {
    return MapObjectType.entranceExit;
  }

  return null;
}

String syntheticEntranceExitDataObject({
  required String assetPath,
  required ui.Rect bounds,
}) {
  final String assetKey = _syntheticAssetKey(assetPath);
  final int left = bounds.left.round();
  final int top = bounds.top.round();
  final int width = bounds.width.round();
  final int height = bounds.height.round();

  return '$assetKey$_mapEntranceExitPrefix$left:$top:$width:$height';
}

String _syntheticAssetKey(String assetPath) {
  final String normalizedPath = assetPath.replaceAll('\\', '/');
  final List<String> pathParts = normalizedPath.split('/');
  final String campusSlug =
      pathParts.length >= 2 ? pathParts[pathParts.length - 2] : 'map';
  final String floorFile = pathParts.isNotEmpty ? pathParts.last : 'floor.svg';
  final String floorSlug =
      floorFile.endsWith('.svg')
          ? floorFile.substring(0, floorFile.length - 4)
          : floorFile;

  return '${campusSlug}__$floorSlug';
}
