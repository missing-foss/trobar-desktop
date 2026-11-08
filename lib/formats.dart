// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// How dates and decimal numbers read and are read back, in the user's
// language rather than one fixed form.

import 'package:intl/intl.dart';

/// A last-sync time in [locale]'s own date and 24-hour time, year included:
/// "16/10/2026 14:05" in French, "10/16/2026 14:05" in English.
String syncTimeText(DateTime dt, String locale) =>
    DateFormat.yMd(locale).add_Hm().format(dt.toLocal());

/// A number of gigabytes as typed, with a decimal point or a decimal comma
/// ("1.5" or "1,5"); null when it isn't one. A grouped number ("1,000.5"
/// or "1.000,5") ends up with two points and doesn't parse: it's ambiguous
/// across languages, so it's refused rather than read wrong.
double? parseGigabytes(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));
