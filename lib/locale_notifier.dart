// SPDX-License-Identifier: GPL-3.0-or-later
// App-wide selected locale; null = follow the system locale. TrobarApp
// rebuilds MaterialApp when this changes; the Settings screen (#17) writes it.

import 'package:flutter/widgets.dart';

final localeNotifier = ValueNotifier<Locale?>(null);
