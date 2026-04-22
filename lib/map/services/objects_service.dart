import 'dart:convert';

import 'package:app_ui/src/generated/generated.dart';
import 'package:flutter/services.dart';

class ObjectsService {
  final Map<String, String> _idToNameMap = <String, String>{};
  final Map<String, String> _idToTypeMap = <String, String>{};

  Future<void> loadObjects() async {
    final String jsonString = await rootBundle.loadString(Assets.maps.objects);
    final Object? decodedJson = json.decode(jsonString);
    if (decodedJson is! Map<String, dynamic>) {
      throw const FormatException('objects.json должен содержать JSON-объект.');
    }

    final Map<String, dynamic> jsonData = decodedJson;
    final Object? rawObjects = jsonData['objects'];
    if (rawObjects is! List<dynamic>) {
      throw const FormatException('В objects.json отсутствует список objects.');
    }

    for (final Object? rawObject in rawObjects) {
      if (rawObject is! Map<String, dynamic>) {
        throw const FormatException(
          'Некорректный объект карты в objects.json.',
        );
      }

      final Object? id = rawObject['id'];
      final Object? type = rawObject['type'];
      final Object? name = rawObject['name'];
      if (id is! String || type is! String || name is! String) {
        throw const FormatException(
          'Объект карты должен содержать строковые id, type и name.',
        );
      }

      _idToNameMap[id] = name;
      _idToTypeMap[id] = type;
    }
  }

  String? getNameById(String id) {
    return _idToNameMap[id];
  }

  bool isRoom(String id) {
    return _idToTypeMap[id] == 'room';
  }
}
