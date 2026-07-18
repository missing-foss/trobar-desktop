// SPDX-License-Identifier: GPL-3.0-or-later
// Settings screen (#17/#18) — parity with the Android SettingsScreen, scoped
// to what desktop can reach: the paired card's server URL, an app-wide
// language override, the missing-file sync policy, and this device's storage
// limit. Standard desktop Cancel/Save.

import 'dart:io';

import 'package:flutter/material.dart';

import 'l10n/gen/app_localizations.dart';

import 'api_client.dart';
import 'app_prefs.dart';
import 'card_store.dart';
import 'locale_notifier.dart';
import 'models.dart';

class SettingsScreen extends StatefulWidget {
  final Directory root;
  final DeviceConfig config;
  final ApiClient api;
  final DeviceInfo? info;

  const SettingsScreen({
    super.key,
    required this.root,
    required this.config,
    required this.api,
    this.info,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url =
      TextEditingController(text: widget.config.serverUrl);
  late final TextEditingController _limit =
      TextEditingController(text: _bytesToGbField(widget.info?.maxSizeBytes));
  late String _language = AppPrefs.instance.language;
  late String _missing = AppPrefs.instance.missingPolicy;
  bool _saving = false;
  String? _error;

  static String _bytesToGbField(int? bytes) {
    if (bytes == null) return '';
    return (bytes / 1e9).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  }

  @override
  void dispose() {
    _url.dispose();
    _limit.dispose();
    super.dispose();
  }

  /// Parsed storage limit in bytes, or null for "no limit" (empty field).
  /// Throws [FormatException] on garbage — guarded by the field validator.
  int? _limitBytes() {
    final t = _limit.text.trim();
    if (t.isEmpty) return null;
    return (double.parse(t) * 1e9).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 1. Server URL — write it back to the card's device.json (token kept).
      var config = widget.config;
      final newUrl = _url.text.trim();
      if (newUrl != widget.config.serverUrl) {
        config = DeviceConfig(serverUrl: newUrl, token: widget.config.token);
        await writeConfig(widget.root, config);
      }
      // 2. Storage limit — PATCH against the (possibly new) server URL.
      final newLimit = _limitBytes();
      if (newLimit != widget.info?.maxSizeBytes) {
        final client = identical(config, widget.config)
            ? widget.api
            : ApiClient(config);
        try {
          await client.updateLimit(newLimit);
        } finally {
          if (!identical(client, widget.api)) client.close();
        }
      }
      // 3. App-wide prefs — language + missing-file policy.
      AppPrefs.instance
        ..language = _language
        ..missingPolicy = _missing;
      await AppPrefs.instance.save();
      localeNotifier.value = _language == 'system' ? null : Locale(_language);

      if (mounted) Navigator.pop(context, config);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Server URL
                  TextFormField(
                    key: const Key('settingsServerUrl'),
                    controller: _url,
                    decoration: InputDecoration(
                      labelText: l.settingsServerUrl,
                      helperText: l.settingsServerUrlHelp,
                      helperMaxLines: 3,
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      final uri = Uri.tryParse(s);
                      final ok = uri != null &&
                          (uri.scheme == 'http' || uri.scheme == 'https') &&
                          uri.host.isNotEmpty;
                      return ok ? null : l.settingsInvalidUrl;
                    },
                  ),
                  const SizedBox(height: 20),
                  // Language override
                  DropdownButtonFormField<String>(
                    initialValue: _language,
                    decoration:
                        InputDecoration(labelText: l.settingsLanguage),
                    items: [
                      DropdownMenuItem(
                          value: 'system',
                          child: Text(l.settingsLanguageSystem)),
                      const DropdownMenuItem(
                          value: 'en', child: Text('English')),
                      const DropdownMenuItem(
                          value: 'fr', child: Text('Français')),
                    ],
                    onChanged: (v) =>
                        setState(() => _language = v ?? 'system'),
                  ),
                  const SizedBox(height: 20),
                  // Missing-file policy
                  DropdownButtonFormField<String>(
                    initialValue: _missing,
                    decoration:
                        InputDecoration(labelText: l.settingsMissingPolicy),
                    items: [
                      DropdownMenuItem(
                          value: 'ask', child: Text(l.settingsMissingAsk)),
                      DropdownMenuItem(
                          value: 'redownload',
                          child: Text(l.settingsMissingRedownload)),
                      DropdownMenuItem(
                          value: 'exclude',
                          child: Text(l.settingsMissingExclude)),
                    ],
                    onChanged: (v) => setState(() => _missing = v ?? 'ask'),
                  ),
                  const SizedBox(height: 20),
                  // Storage limit (GB)
                  TextFormField(
                    key: const Key('settingsStorageLimit'),
                    controller: _limit,
                    decoration: InputDecoration(
                      labelText: l.settingsStorageLimit,
                      helperText: l.settingsStorageLimitHelp,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return null;
                      final gb = double.tryParse(s);
                      return (gb != null && gb >= 0)
                          ? null
                          : l.settingsInvalidLimit;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        child: Text(l.cancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('settingsSave'),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(l.save),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
