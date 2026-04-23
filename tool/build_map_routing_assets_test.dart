import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtu_mirea_app/map/config/map_campuses.dart';
import 'package:rtu_mirea_app/map/models/campus_model.dart';
import 'package:rtu_mirea_app/map/services/map_routing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generate baked route graph assets',
    () async {
      final CampusModel campus = universityMapCampuses.firstWhere(
        (CampusModel campus) => campus.id == 'v-78',
      );
      final String graphJson =
          await MapRoutingService.buildCampusGraphAssetJson(campus: campus);
      final File outputFile = File('assets/map_routing/v-78.json');
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsString(graphJson);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
