import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FilterChipItem {
  const FilterChipItem({
    required this.id,
    required this.label,
    this.badge,
  });

  final String id;
  final String label;
  final int? badge;
}

/// Fila horizontal de chips de filtro.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
  });

  final List<FilterChipItem> items;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final selected = item.id == selectedId;
          return ChoiceChip(
            selected: selected,
            label: Text(
              item.badge == null || item.badge == 0
                  ? item.label
                  : '${item.label} ${item.badge}',
            ),
            selectedColor: AppTheme.moradoPrincipal,
            backgroundColor: AppTheme.borde.withValues(alpha: 0.7),
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppTheme.texto,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            side: BorderSide.none,
            onSelected: (_) => onSelected(item.id),
          );
        },
      ),
    );
  }
}
