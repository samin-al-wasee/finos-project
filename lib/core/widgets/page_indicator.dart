import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small dot row showing which page is currently selected in a swipeable
/// single-item-per-page carousel (e.g. the Accounts and Loans card views).
class PageIndicator extends StatelessWidget {
  const PageIndicator({
    super.key,
    required this.count,
    required this.selectedIndex,
  });

  final int count;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FinosColors>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == selectedIndex
                  ? Theme.of(context).colorScheme.primary
                  : colors.border,
            ),
          ),
      ],
    );
  }
}
