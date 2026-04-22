import 'package:app_ui/src/colors/colors.dart';
import 'package:flutter/material.dart';

class MapNavigationButton extends StatelessWidget {
  const MapNavigationButton({
    super.key,
    required this.floor,
    required this.onClick,
    required this.isSelected,
    required this.hasRouteSegment,
  });

  final int floor;
  final Function onClick;
  final bool isSelected;
  final bool hasRouteSegment;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      child: ElevatedButton(
        style: ButtonStyle(
          padding: WidgetStateProperty.all<EdgeInsets>(EdgeInsets.zero),
          backgroundColor: WidgetStateProperty.all<Color>(
            isSelected
                ? Theme.of(context).extension<AppColors>()!.background03
                : Theme.of(context).extension<AppColors>()!.background02,
          ),
          shadowColor: WidgetStateProperty.all<Color>(Colors.transparent),
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Text(
              floor.toString(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color:
                    isSelected
                        ? Theme.of(context).extension<AppColors>()!.active
                        : Theme.of(context).extension<AppColors>()!.deactive,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hasRouteSegment)
              Positioned(
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC857),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const SizedBox(width: 18, height: 4),
                ),
              ),
          ],
        ),
        onPressed: () => onClick(),
      ),
    );
  }
}
