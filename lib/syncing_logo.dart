// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #25: the bard logo with musical notes rising from the lute while a sync runs
// (parity with Android's AppLogo/RisingNote), and tap-to-sync. Purely cosmetic.

import 'dart:math' as math;

import 'package:flutter/material.dart';

class SyncingLogo extends StatefulWidget {
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
  State<SyncingLogo> createState() => _SyncingLogoState();
}

class _SyncingLogoState extends State<SyncingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.syncing) _c.repeat();
  }

  @override
  void didUpdateWidget(SyncingLogo old) {
    super.didUpdateWidget(old);
    if (widget.syncing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.syncing && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = Theme.of(context).colorScheme.secondary;
    // Room above the logo for the notes to rise into.
    final rise = widget.size * 0.7;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size + rise,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            if (widget.syncing)
              ...List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    // Each note is offset in phase so they stagger.
                    final t = (_c.value + i / 3) % 1.0;
                    final dy = rise * t; // distance risen
                    final opacity = math.sin(t * math.pi); // fade in then out
                    // gentle horizontal sway, alternating per note
                    final dx = math.sin(t * math.pi * 2) * 8 * (i.isEven ? 1 : -1);
                    return Positioned(
                      bottom: widget.size * 0.55 + dy,
                      left: widget.size * 0.5 + dx,
                      child: Opacity(
                        opacity: opacity.clamp(0, 1).toDouble(),
                        child: Icon(i.isEven ? Icons.music_note : Icons.audiotrack,
                            size: widget.size * 0.22, color: note),
                      ),
                    );
                  },
                );
              }),
            Image.asset('assets/logo_bard.png', width: widget.size),
          ],
        ),
      ),
    );
  }
}
