// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The brand theme in force, and how widgets reach it. TrobarApp rebuilds its
// themes when brandNotifier changes; the Settings screen writes it.

import 'package:flutter/material.dart';

import 'brand_tokens.dart';

final brandNotifier = ValueNotifier<BrandTheme>(BrandTheme.fallback);

/// The brand theme as part of ThemeData, so the mark, the wordmark and the
/// connect-four coins can colour themselves from the active theme.
class TrobarBrand extends ThemeExtension<TrobarBrand> {
  const TrobarBrand(this.theme);

  final BrandTheme theme;

  static BrandTheme of(BuildContext context) =>
      Theme.of(context).extension<TrobarBrand>()?.theme ?? BrandTheme.fallback;

  @override
  TrobarBrand copyWith({BrandTheme? theme}) => TrobarBrand(theme ?? this.theme);

  @override
  TrobarBrand lerp(TrobarBrand? other, double t) => t < 0.5 ? this : (other ?? this);
}
