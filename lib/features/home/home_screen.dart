import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme/tokens.dart';
import 'home_menu_tile.dart';

typedef _HomeTileSpec = ({IconData icon, String label, String route});

const List<_HomeTileSpec> _tiles = [
  (
    icon: Icons.camera_alt,
    label: AppStrings.homeTileLogCards,
    route: AppRoutes.scan,
  ),
  (
    icon: Icons.style,
    label: AppStrings.homeTileMyCollection,
    route: AppRoutes.collection,
  ),
  (
    icon: Icons.bar_chart,
    label: AppStrings.homeTileStatistics,
    route: AppRoutes.statistics,
  ),
  (
    icon: Icons.settings,
    label: AppStrings.homeTileSettings,
    route: AppRoutes.settings,
  ),
];

/// Four tiles filling the screen in a fixed 2x2 layout — deliberately not a
/// scrolling GridView. All four must be visible and reachable at a glance,
/// without scrolling, on any device.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    assert(_tiles.length == HomeMenuTokens.tileCount);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Expanded(child: _HomeTileRow(left: _tiles[0], right: _tiles[1])),
              const SizedBox(height: HomeMenuTokens.tileSpacing),
              Expanded(child: _HomeTileRow(left: _tiles[2], right: _tiles[3])),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTileRow extends StatelessWidget {
  const _HomeTileRow({required this.left, required this.right});

  final _HomeTileSpec left;
  final _HomeTileSpec right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildTile(context, left)),
        const SizedBox(width: HomeMenuTokens.tileSpacing),
        Expanded(child: _buildTile(context, right)),
      ],
    );
  }

  Widget _buildTile(BuildContext context, _HomeTileSpec spec) {
    return HomeMenuTile(
      icon: spec.icon,
      label: spec.label,
      onTap: () => context.push(spec.route),
    );
  }
}
