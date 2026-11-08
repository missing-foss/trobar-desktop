// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The Trobar rosette in the active brand theme, and its syncing state: the
// star alone turns 90° every 2.4 s, eased (brand/BRAND.md §5), and holds still
// when the platform asks for reduced motion. SyncingLogo adds tap-to-sync.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'brand_notifier.dart';
import 'brand_tokens.dart';

const _markAsset = 'assets/brand/trobar-mark-themable.svg';
Future<String>? _markSource;

/// The mark as three stacked layers, filled in [theme]'s colours: disc and
/// pommels, the star (two paths, the only part that turns), hub and dot.
/// From brand/svg/mark/trobar-mark-themable.svg, whose paths read the --tb-*
/// roles; the colours are put in here instead.
List<String> markLayers(String source, BrandTheme theme) {
  final paths = RegExp(r'<path style="fill:var\(--tb-(\w+),[^)]*\)" d="([^"]*)"/>')
      .allMatches(source)
      .toList();
  if (paths.length != 6) {
    throw StateError('unexpected mark: ${paths.length} paths');
  }
  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  Color role(String name) => switch (name) {
        'disc' => theme.disc,
        'star' => theme.star,
        'dot' => theme.dot,
        _ => throw StateError('unexpected role $name'),
      };
  String svg(Iterable<RegExpMatch> ms) =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">'
      '${ms.map((m) => '<path fill="${hex(role(m[1]!))}" d="${m[2]}"/>').join()}'
      '</svg>';
  return [svg(paths.sublist(0, 2)), svg(paths.sublist(2, 4)), svg(paths.sublist(4))];
}

class TrobarMark extends StatefulWidget {
  final double size;
  final bool syncing;

  const TrobarMark({super.key, this.size = 96, this.syncing = false});

  @override
  State<TrobarMark> createState() => _TrobarMarkState();
}

class _TrobarMarkState extends State<TrobarMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));
  // A quarter turn per cycle, eased; the star repeats every 90°, so the
  // restart at 0 is seamless.
  late final Animation<double> _turns = Tween(begin: 0.0, end: 0.25)
      .animate(CurvedAnimation(parent: _c, curve: const Cubic(0.45, 0, 0.55, 1)));

  bool _shouldTurn(BuildContext context) =>
      widget.syncing && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync(BuildContext context) {
    if (_shouldTurn(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else if (_c.isAnimating || _c.value != 0) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(context);
  }

  @override
  void didUpdateWidget(TrobarMark old) {
    super.didUpdateWidget(old);
    _sync(context);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TrobarBrand.of(context);
    return SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<String>(
        future: _markSource ??= rootBundle.loadString(_markAsset),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          final layers = markLayers(snap.data!, theme);
          return Stack(
            fit: StackFit.expand,
            children: [
              SvgPicture.string(layers[0]),
              RotationTransition(
                key: const ValueKey('mark-star'),
                turns: _turns,
                child: SvgPicture.string(layers[1]),
              ),
              SvgPicture.string(layers[2]),
            ],
          );
        },
      ),
    );
  }
}

/// The mark on the home screen: tap to sync, the star turning while it runs.
class SyncingLogo extends StatelessWidget {
  final bool syncing;
  final double size;
  final VoidCallback? onTap;

  const SyncingLogo({
    super.key,
    required this.syncing,
    this.size = 96,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: TrobarMark(size: size, syncing: syncing),
      );
}
