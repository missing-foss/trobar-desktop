// SPDX-License-Identifier: GPL-3.0-or-later
// About screen: version, links, licenses, donate. The update
// check is user-initiated only — one GitHub API call per button press,
// never automatic (the app otherwise talks to nothing but your server).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/gen/app_localizations.dart';
import 'main.dart' show brandCream, brandRose;

const _repoUrl = 'https://github.com/missing-foss/trobar-desktop';
const _docsUrl =
    'https://github.com/missing-foss/trobar-server/blob/main/docs/clients.md';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  bool _checking = false;
  String? _updateStatus;
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  Future<void> _checkUpdates() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _checking = true;
      _updateAvailable = false;
      _updateStatus = l.updateChecking;
    });
    String status;
    try {
      final resp = await http
          .get(Uri.parse(
              'https://api.github.com/repos/missing-foss/trobar-desktop/releases/latest'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final tag = (jsonDecode(resp.body)['tag_name'] as String?) ?? '';
      final latest = tag.replaceFirst('desktop-v', '');
      if (latest.isNotEmpty && latest != _version) {
        _updateAvailable = true;
        status = l.updateAvailable(tag);
      } else {
        status = l.updateUpToDate(_version);
      }
    } catch (e) {
      status = l.updateCheckFailed(e.toString());
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _updateStatus = status;
      });
    }
  }

  Future<void> _showDoc(String title, String asset) async {
    final text = await rootBundle.loadString(asset);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Text(text,
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.close)),
        ],
      ),
    );
  }

  Widget _link(IconData icon, String label, String url) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: () => launchUrl(Uri.parse(url)),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.aboutTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Image.asset('assets/logo_bard.png', width: 110),
              const SizedBox(height: 8),
              Center(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: 'Trob',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                              color: brandCream, fontWeight: FontWeight.w600)),
                  TextSpan(
                      text: 'ar',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                              color: brandRose, fontWeight: FontWeight.w600)),
                ])),
              ),
              Center(
                child: Text(l.aboutVersion(_version),
                    style: TextStyle(color: brandCream.withValues(alpha: .7))),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _checking ? null : _checkUpdates,
                    child: Text(l.checkUpdates),
                  ),
                  // Liberapay brand yellow — a vendored "button", no external
                  // widget script (a deliberate no-CDN choice).
                  FilledButton(
                    onPressed: () => launchUrl(
                        Uri.parse('https://liberapay.com/Trobar/donate')),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF6C915),
                        foregroundColor: const Color(0xFF1A171B)),
                    child: Text(l.donate),
                  ),
                ],
              ),
              if (_updateStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Center(
                    child: Text(_updateStatus!,
                        style: TextStyle(
                            fontSize: 13,
                            color: _updateAvailable
                                ? brandRose
                                : brandCream.withValues(alpha: .7))),
                  ),
                ),
              const SizedBox(height: 20),
              Text(l.aboutLinks,
                  style: Theme.of(context).textTheme.titleSmall),
              Card(
                child: Column(children: [
                  _link(Icons.menu_book, l.aboutDocumentation, _docsUrl),
                  _link(Icons.code, l.aboutSourceCode, _repoUrl),
                  _link(Icons.bug_report, l.aboutReportIssue,
                      '$_repoUrl/issues/new/choose'),
                  _link(Icons.new_releases, l.aboutReleases,
                      '$_repoUrl/releases'),
                ]),
              ),
              const SizedBox(height: 20),
              Text(l.aboutLicenses,
                  style: Theme.of(context).textTheme.titleSmall),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.aboutLicenseSummary,
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton(
                          onPressed: () => _showDoc(
                              'GPL-3.0-or-later', 'LICENSE'),
                          child: Text(l.showLicense),
                        ),
                        // Flutter's own registry: every Dart package's
                        // license.
                        OutlinedButton(
                          onPressed: () => showLicensePage(
                              context: context,
                              applicationName: 'Trobar desktop',
                              applicationVersion: _version),
                          child: Text(l.showThirdParty),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
