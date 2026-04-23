import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart' as xml;

class SvgPathParser {
  static Rect parseViewBox(xml.XmlElement svgRoot) {
    final String? viewBoxAttr = svgRoot.getAttribute('viewBox');
    if (viewBoxAttr == null) {
      return const Rect.fromLTWH(0, 0, 1000, 1000);
    }

    final List<double> parts = _parseNumbers(viewBoxAttr);
    if (parts.length != 4) {
      return const Rect.fromLTWH(0, 0, 1000, 1000);
    }

    return Rect.fromLTWH(parts[0], parts[1], parts[2], parts[3]);
  }

  static Map<String, xml.XmlElement> collectElementsById(
    xml.XmlElement svgRoot,
  ) {
    final Map<String, xml.XmlElement> elementsById = <String, xml.XmlElement>{};
    for (final xml.XmlElement element
        in svgRoot.descendants.whereType<xml.XmlElement>()) {
      final String? id = element.getAttribute('id');
      if (id != null && id.isNotEmpty) {
        elementsById[id] = element;
      }
    }

    return elementsById;
  }

  static Path? parseElementToPath({
    required xml.XmlElement element,
    required Map<String, xml.XmlElement> elementsById,
  }) {
    if (element.getAttribute('data-object') != null) {
      final Path? objectSurfacePath = _parseLargestShapeToPath(
        element: element,
        elementsById: elementsById,
      );
      if (objectSurfacePath != null) {
        return objectSurfacePath;
      }
    }

    final Path path = Path()..fillType = _parseFillType(element);
    final Matrix4 inheritedTransform = _ancestorTransform(element);
    _addElementPath(
      targetPath: path,
      element: element,
      elementsById: elementsById,
      parentTransform: inheritedTransform,
    );

    if (path.getBounds().isEmpty) {
      return null;
    }

    return path;
  }

  static Path? _parseLargestShapeToPath({
    required xml.XmlElement element,
    required Map<String, xml.XmlElement> elementsById,
  }) {
    Path? largestPath;
    double largestArea = 0;

    for (final xml.XmlElement candidate in _shapeElementsForObject(element)) {
      final Matrix4 transform = _combinedTransform(
        _ancestorTransform(candidate),
        candidate.getAttribute('transform'),
      );
      final Path? path = _parseShapeToPath(
        element: candidate,
        elementsById: elementsById,
        transform: transform,
      );
      if (path == null) {
        continue;
      }

      final Rect bounds = path.getBounds();
      if (bounds.isEmpty) {
        continue;
      }

      final double area = bounds.width * bounds.height;
      if (area <= largestArea) {
        continue;
      }

      largestArea = area;
      largestPath = path;
    }

    return largestPath;
  }

  static List<xml.XmlElement> _shapeElementsForObject(xml.XmlElement element) {
    final List<xml.XmlElement> shapeElements = <xml.XmlElement>[];
    if (_isShapeElement(element)) {
      shapeElements.add(element);
    }

    for (final xml.XmlElement descendant
        in element.descendants.whereType<xml.XmlElement>()) {
      if (_isShapeElement(descendant)) {
        shapeElements.add(descendant);
      }
    }

    return shapeElements;
  }

  static String? fillValue(xml.XmlElement element) {
    final String? fill = element.getAttribute('fill');
    if (fill != null && fill.isNotEmpty) {
      return fill.toLowerCase();
    }

    final String? style = element.getAttribute('style');
    if (style == null || style.isEmpty) {
      return null;
    }

    final RegExpMatch? match = RegExp(
      r'(^|;)\s*fill\s*:\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(style);
    return match?.group(2)?.trim().toLowerCase();
  }

  static Matrix4 _ancestorTransform(xml.XmlElement element) {
    final List<xml.XmlElement> ancestors = <xml.XmlElement>[];
    xml.XmlNode? parent = element.parent;
    while (parent is xml.XmlElement &&
        parent.name.local.toLowerCase() != 'svg') {
      ancestors.add(parent);
      parent = parent.parent;
    }

    Matrix4 transform = Matrix4.identity();
    for (final xml.XmlElement ancestor in ancestors.reversed) {
      transform = _combinedTransform(
        transform,
        ancestor.getAttribute('transform'),
      );
    }

    return transform;
  }

  static Matrix4? parseTransform(String? transformAttr) {
    if (transformAttr == null) {
      return null;
    }

    final RegExp regex = RegExp(r'(\w+)\(([^)]+)\)');
    final Iterable<RegExpMatch> matches = regex.allMatches(transformAttr);
    Matrix4 matrix = Matrix4.identity();

    for (final RegExpMatch match in matches) {
      final String transformType = match.group(1)!;
      final String params = match.group(2)!;
      final List<double> values = _parseNumbers(params);
      Matrix4 current = Matrix4.identity();

      switch (transformType) {
        case 'translate':
          if (values.length == 1) {
            current.translateByDouble(values[0], 0, 0, 1);
          } else if (values.length == 2) {
            current.translateByDouble(values[0], values[1], 0, 1);
          }
          break;
        case 'scale':
          if (values.length == 1) {
            current.scaleByDouble(values[0], values[0], 1, 1);
          } else if (values.length == 2) {
            current.scaleByDouble(values[0], values[1], 1, 1);
          }
          break;
        case 'rotate':
          if (values.length == 1) {
            current = _rotationMatrix(
              radians: _degreesToRadians(values[0]),
              centerX: 0,
              centerY: 0,
            );
          } else if (values.length == 3) {
            current = _rotationMatrix(
              radians: _degreesToRadians(values[0]),
              centerX: values[1],
              centerY: values[2],
            );
          }
          break;
        case 'skewX':
          if (values.length == 1) {
            final double tangent = math.tan(_degreesToRadians(values[0]));
            current.setValues(
              1,
              0,
              0,
              0,
              tangent,
              1,
              0,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
            );
          }
          break;
        case 'skewY':
          if (values.length == 1) {
            final double tangent = math.tan(_degreesToRadians(values[0]));
            current.setValues(
              1,
              tangent,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
            );
          }
          break;
        case 'matrix':
          if (values.length == 6) {
            final double a = values[0];
            final double b = values[1];
            final double c = values[2];
            final double d = values[3];
            final double e = values[4];
            final double f = values[5];
            current.setValues(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1);
          }
          break;
        default:
          throw UnsupportedError(
            'Unsupported SVG transformation type: $transformType',
          );
      }

      matrix = matrix.multiplied(current);
    }

    return matrix;
  }

  static void _addElementPath({
    required Path targetPath,
    required xml.XmlElement element,
    required Map<String, xml.XmlElement> elementsById,
    required Matrix4 parentTransform,
  }) {
    final Matrix4 elementTransform = _combinedTransform(
      parentTransform,
      element.getAttribute('transform'),
    );
    final Path? shapePath = _parseShapeToPath(
      element: element,
      elementsById: elementsById,
      transform: elementTransform,
    );
    if (shapePath != null) {
      targetPath.addPath(shapePath, Offset.zero);
    }

    for (final xml.XmlElement child
        in element.children.whereType<xml.XmlElement>()) {
      _addElementPath(
        targetPath: targetPath,
        element: child,
        elementsById: elementsById,
        parentTransform: elementTransform,
      );
    }
  }

  static Path? _parseShapeToPath({
    required xml.XmlElement element,
    required Map<String, xml.XmlElement> elementsById,
    required Matrix4 transform,
  }) {
    final String tag = element.name.local.toLowerCase();
    Path? path;

    if (tag == 'path') {
      final String? d = element.getAttribute('d');
      if (d != null && d.isNotEmpty) {
        path = parseSvgPathData(d)..fillType = _parseFillType(element);
      }
    } else if (tag == 'rect') {
      path = _parseRect(element);
    } else if (tag == 'circle') {
      path = _parseCircle(element);
    } else if (tag == 'ellipse') {
      path = _parseEllipse(element);
    } else if (tag == 'polygon' || tag == 'polyline') {
      path = _parsePolygon(element, tag);
    } else if (tag == 'use') {
      path = _parseUse(
        element: element,
        elementsById: elementsById,
        transform: transform,
      );
      return path;
    }

    if (path == null) {
      return null;
    }

    return path.transform(transform.storage);
  }

  static bool _isShapeElement(xml.XmlElement element) {
    final String tag = element.name.local.toLowerCase();
    return tag == 'path' ||
        tag == 'rect' ||
        tag == 'circle' ||
        tag == 'ellipse' ||
        tag == 'polygon' ||
        tag == 'polyline' ||
        tag == 'use';
  }

  static Path? _parseRect(xml.XmlElement element) {
    final double x = _parseDouble(element.getAttribute('x'));
    final double y = _parseDouble(element.getAttribute('y'));
    final double width = _parseDouble(element.getAttribute('width'));
    final double height = _parseDouble(element.getAttribute('height'));
    if (width <= 0 || height <= 0) {
      return null;
    }

    final double rx = _parseDouble(element.getAttribute('rx'));
    final double ry = _parseDouble(element.getAttribute('ry'));
    if (rx > 0 || ry > 0) {
      return Path()..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, width, height),
          topLeft: Radius.elliptical(rx, ry > 0 ? ry : rx),
          topRight: Radius.elliptical(rx, ry > 0 ? ry : rx),
          bottomLeft: Radius.elliptical(rx, ry > 0 ? ry : rx),
          bottomRight: Radius.elliptical(rx, ry > 0 ? ry : rx),
        ),
      );
    }

    return Path()..addRect(Rect.fromLTWH(x, y, width, height));
  }

  static Path? _parseCircle(xml.XmlElement element) {
    final double cx = _parseDouble(element.getAttribute('cx'));
    final double cy = _parseDouble(element.getAttribute('cy'));
    final double radius = _parseDouble(element.getAttribute('r'));
    if (radius <= 0) {
      return null;
    }

    return Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
  }

  static Path? _parseEllipse(xml.XmlElement element) {
    final double cx = _parseDouble(element.getAttribute('cx'));
    final double cy = _parseDouble(element.getAttribute('cy'));
    final double rx = _parseDouble(element.getAttribute('rx'));
    final double ry = _parseDouble(element.getAttribute('ry'));
    if (rx <= 0 || ry <= 0) {
      return null;
    }

    return Path()..addOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
    );
  }

  static Path? _parsePolygon(xml.XmlElement element, String tag) {
    final String? pointsAttr = element.getAttribute('points');
    if (pointsAttr == null || pointsAttr.isEmpty) {
      return null;
    }

    final List<double> numbers = _parseNumbers(pointsAttr);
    if (numbers.length < 4) {
      return null;
    }

    final Path path = Path()..moveTo(numbers[0], numbers[1]);
    for (int index = 2; index < numbers.length - 1; index += 2) {
      path.lineTo(numbers[index], numbers[index + 1]);
    }
    if (tag == 'polygon') {
      path.close();
    }

    return path;
  }

  static Path? _parseUse({
    required xml.XmlElement element,
    required Map<String, xml.XmlElement> elementsById,
    required Matrix4 transform,
  }) {
    final String? href =
        element.getAttribute('href') ??
        element.getAttribute('href', namespace: 'http://www.w3.org/1999/xlink');
    if (href == null || !href.startsWith('#')) {
      return null;
    }

    final xml.XmlElement? referencedElement = elementsById[href.substring(1)];
    if (referencedElement == null) {
      return null;
    }

    final Matrix4 useTransform = transform.multiplied(
      Matrix4.identity()..translateByDouble(
        _parseDouble(element.getAttribute('x')),
        _parseDouble(element.getAttribute('y')),
        0,
        1,
      ),
    );
    final Path path = Path()..fillType = _parseFillType(referencedElement);
    _addElementPath(
      targetPath: path,
      element: referencedElement,
      elementsById: elementsById,
      parentTransform: useTransform,
    );

    if (path.getBounds().isEmpty) {
      return null;
    }

    return path;
  }

  static Matrix4 _combinedTransform(
    Matrix4 parentTransform,
    String? transformAttr,
  ) {
    final Matrix4? transform = parseTransform(transformAttr);
    if (transform == null) {
      return parentTransform;
    }

    return parentTransform.multiplied(transform);
  }

  static PathFillType _parseFillType(xml.XmlElement element) {
    final String? fillRule =
        element.getAttribute('fill-rule') ?? element.getAttribute('clip-rule');
    if (fillRule == 'evenodd') {
      return PathFillType.evenOdd;
    }

    return PathFillType.nonZero;
  }

  static List<double> _parseNumbers(String value) {
    return RegExp(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?')
        .allMatches(value)
        .map((RegExpMatch match) => double.parse(match.group(0)!))
        .toList(growable: false);
  }

  static double _parseDouble(String? value) {
    if (value == null || value.isEmpty) {
      return 0;
    }

    return double.parse(value);
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  static Matrix4 _rotationMatrix({
    required double radians,
    required double centerX,
    required double centerY,
  }) {
    final double cosine = math.cos(radians);
    final double sine = math.sin(radians);
    final double translateX = centerX - cosine * centerX + sine * centerY;
    final double translateY = centerY - sine * centerX - cosine * centerY;
    return Matrix4.identity()..setValues(
      cosine,
      sine,
      0,
      0,
      -sine,
      cosine,
      0,
      0,
      0,
      0,
      1,
      0,
      translateX,
      translateY,
      0,
      1,
    );
  }
}
