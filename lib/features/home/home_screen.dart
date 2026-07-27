import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme/tokens.dart';
import '../scan/art_providers.dart';
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
              const _ScanPrewarm(),
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

/// Starts the scan pipeline's two expensive one-time setups while the user is
/// still looking at the menu: parsing the ~14 400-entry pHash index off the
/// bundled asset, and spawning the OpenCV detector's worker isolate.
///
/// Both providers are `keepAlive`, so what is warmed here is still warm when Log
/// Cards is opened — otherwise this would be pure waste. Without it the very
/// first open of each app run still pays for both **while
/// `CameraController.initialize()` is running**, which is exactly the moment
/// there is no budget: the index's copy back from its `compute` isolate lands on
/// the UI isolate, and a UI isolate that stops painting is indistinguishable
/// from a camera that never started.
///
/// Renders nothing, and deliberately does not `watch`: this is a warm-up, not a
/// dependency, so nothing here can gate or rebuild the menu — a failure to parse
/// the index must surface on the scan screen, where it can be acted on, not as a
/// broken home screen.
class _ScanPrewarm extends ConsumerStatefulWidget {
  const _ScanPrewarm();

  @override
  ConsumerState<_ScanPrewarm> createState() => _ScanPrewarmState();
}

class _ScanPrewarmState extends ConsumerState<_ScanPrewarm> {
  @override
  void initState() {
    super.initState();
    // In `initState`, not `build`: the standing "no business logic in build()"
    // rule, and building must stay free of side effects that repeat on rebuild.
    ref.read(hashIndexProvider);
    ref.read(cardDetectorProvider);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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
