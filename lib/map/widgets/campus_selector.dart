import 'package:app_ui/src/colors/colors.dart';
import 'package:flutter/material.dart';
import 'package:rtu_mirea_app/map/map.dart';

class CampusSelector extends StatelessWidget {
  final List<CampusModel> campuses;
  final CampusModel selectedCampus;
  final Function(CampusModel) onCampusSelected;

  const CampusSelector({
    super.key,
    required this.campuses,
    required this.selectedCampus,
    required this.onCampusSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).extension<AppColors>()!.background02,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).extension<AppColors>()!.divider,
          width: 1,
        ),
      ),
      child: DropdownButton<CampusModel>(
        value: selectedCampus,
        isExpanded: true,
        underline: const SizedBox(),
        icon: Icon(
          Icons.arrow_drop_down,
          color: Theme.of(context).extension<AppColors>()!.active,
        ),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).extension<AppColors>()!.active,
          fontWeight: FontWeight.w700,
        ),
        dropdownColor: Theme.of(context).extension<AppColors>()!.background02,
        items:
            campuses.map((campus) {
              return DropdownMenuItem<CampusModel>(
                value: campus,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Text(
                    campus.displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).extension<AppColors>()!.active,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
        onChanged: (campus) {
          if (campus != null) {
            onCampusSelected(campus);
          }
        },
      ),
    );
  }
}
