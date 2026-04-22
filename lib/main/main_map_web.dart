import 'package:app_ui/src/colors/colors.dart';
import 'package:flutter/material.dart';
import 'package:rtu_mirea_app/map/view/view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MapWebApp());
}

class MapWebApp extends StatelessWidget {
  const MapWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Карта университета',
      theme: _buildMapTheme(
        brightness: Brightness.light,
        colors: AppColors.light,
      ),
      darkTheme: _buildMapTheme(
        brightness: Brightness.dark,
        colors: AppColors.dark,
      ),
      themeMode: ThemeMode.system,
      home: MapPageView(
        controlsBottomOffset: 16,
        selectedRoomActionBuilder: buildEmptySelectedRoomAction,
      ),
    );
  }
}

ThemeData _buildMapTheme({
  required Brightness brightness,
  required AppColors colors,
}) {
  final ThemeData baseTheme =
      brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();

  return baseTheme.copyWith(
    extensions: <ThemeExtension<dynamic>>[colors],
    scaffoldBackgroundColor: colors.background01,
    colorScheme: baseTheme.colorScheme.copyWith(
      brightness: brightness,
      primary: colors.primary,
      secondary: colors.secondary,
      surface: colors.surface,
      error: colors.error,
      onPrimary: colors.white,
      onSecondary: colors.white,
      onSurface: colors.onSurface,
      onError: colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background01,
      foregroundColor: colors.active,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.background02,
      border: InputBorder.none,
    ),
  );
}
