import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:rtu_mirea_app/map/models/models.dart';
import 'package:rtu_mirea_app/map/services/svg_path_parser.dart';
import 'package:xml/xml.dart' as xml;

class SvgRoomsParser {
  static Future<(List<RoomModel>, ui.Rect)> parseSvg(String assetPath) async {
    final String svgString = await rootBundle.loadString(assetPath);
    final xml.XmlDocument document = xml.XmlDocument.parse(svgString);
    final xml.XmlElement svgRoot = document.findElements('svg').first;

    final ui.Rect parsedViewBox = SvgPathParser.parseViewBox(svgRoot);
    final Map<String, xml.XmlElement> elementsById =
        SvgPathParser.collectElementsById(svgRoot);

    final List<RoomModel> rooms = <RoomModel>[];
    final Iterable<xml.XmlElement> objectElements = svgRoot.descendants
        .whereType<xml.XmlElement>()
        .where(
          (xml.XmlElement node) => node.getAttribute('data-object') != null,
        );

    double globalMinX = double.infinity;
    double globalMinY = double.infinity;
    double globalMaxX = -double.infinity;
    double globalMaxY = -double.infinity;

    for (final xml.XmlElement element in objectElements) {
      final String dataRoom = element.getAttribute('data-object')!;

      final ui.Path? parsedPath = SvgPathParser.parseElementToPath(
        element: element,
        elementsById: elementsById,
      );
      if (parsedPath == null) {
        continue;
      }

      final ui.Path combinedPath = parsedPath;
      final ui.Rect bounds = combinedPath.getBounds();
      if (!bounds.isEmpty) {
        globalMinX = math.min(globalMinX, bounds.left);
        globalMinY = math.min(globalMinY, bounds.top);
        globalMaxX = math.max(globalMaxX, bounds.right);
        globalMaxY = math.max(globalMaxY, bounds.bottom);
      }

      rooms.add(RoomModel(roomId: dataRoom, path: combinedPath));
    }

    if (rooms.isEmpty) {
      return (<RoomModel>[], parsedViewBox);
    }

    final ui.Rect realBox = ui.Rect.fromLTWH(
      globalMinX,
      globalMinY,
      globalMaxX - globalMinX,
      globalMaxY - globalMinY,
    );
    final ui.Rect unionRect = _rectUnion(parsedViewBox, realBox);

    final ui.Offset shiftOffset = ui.Offset(-unionRect.left, -unionRect.top);
    for (final RoomModel room in rooms) {
      room.path = room.path.shift(shiftOffset);
    }

    final ui.Rect normalizedRect = ui.Rect.fromLTWH(
      0,
      0,
      unionRect.width,
      unionRect.height,
    );
    return (rooms, normalizedRect);
  }

  static ui.Rect _rectUnion(ui.Rect r1, ui.Rect r2) {
    final double left = math.min(r1.left, r2.left);
    final double top = math.min(r1.top, r2.top);
    final double right = math.max(r1.right, r2.right);
    final double bottom = math.max(r1.bottom, r2.bottom);
    return ui.Rect.fromLTRB(left, top, right, bottom);
  }
}
