/// AntiBot detection tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../../tool_sample_action.dart';

class _AntiBotDetectorView extends StatefulWidget {
  const _AntiBotDetectorView();

  @override
  State<_AntiBotDetectorView> createState() => _AntiBotDetectorViewState();
}

class _AntiBotDetectorViewState extends State<_AntiBotDetectorView> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _url.dispose();
    _output.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final rawUrl = _url.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _output.clear();
        _error = null;
      });
      return;
    }
    final normalized = _normalizeUrl(rawUrl);
    if (normalized == null) {
      setState(() => _error = 'Invalid URL');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _output.text = 'Fetching...';
    });
    try {
      final fetched = await _fetchPage(normalized);
      final analysis = _AntiBotDetector.analyze(
        url: fetched.url,
        html: fetched.html,
        headers: fetched.headers,
        cookies: fetched.cookies,
        scripts: fetched.scripts,
        jsVariables: fetched.inlineScripts,
      );
      _output.text = _formatAntiBotResult(analysis, fetched.statusCode);
    } catch (e) {
      _output.clear();
      _error = 'Failed to fetch page: $e';
    } finally {
      setState(() => _loading = false);
    }
  }

  Uri? _normalizeUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    return Uri.tryParse(withScheme);
  }

  Future<_FetchedPage> _fetchPage(Uri uri) async {
    final client = HttpClient();
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml',
    );
    request.headers.set(
      HttpHeaders.userAgentHeader,
      _AntiBotDetector.defaultUserAgent,
    );
    final response = await request.close();
    final statusCode = response.statusCode;
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    final cookies = <String, String>{};
    // Parse cookies from header manually to avoid FormatException with invalid characters
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null) {
      for (final header in setCookieHeaders) {
        try {
          final parts = header.split(';').first.split('=');
          if (parts.length >= 2) {
            cookies[parts[0].trim()] = parts.sublist(1).join('=').trim();
          }
        } catch (_) {
          // Skip malformed cookies
        }
      }
    }
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return _FetchedPage(
      url: uri.toString(),
      statusCode: statusCode,
      headers: headers,
      cookies: cookies,
      html: body,
      scripts: _extractScriptSrc(body),
      inlineScripts: _extractInlineScripts(body),
    );
  }

  List<String> _extractScriptSrc(String html) {
    final matches = RegExp(
      "<script[^>]+src=['\\\"]([^'\\\"]+)['\\\"]",
      caseSensitive: false,
    ).allMatches(html);
    return matches
        .map((match) => match.group(1) ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
  }

  List<String> _extractInlineScripts(String html) {
    final matches = RegExp(
      "<script(?![^>]*\\bsrc=)[^>]*>([\\s\\S]*?)</script>",
      caseSensitive: false,
    ).allMatches(html);
    return matches
        .map((match) => (match.group(1) ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  void _setSample() {
    setState(() => _url.text = 'https://example.com');
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // URL input row
          Row(
            children: [
              const Text('URL', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: toolSurfaceDecoration(context, radius: 6),
                  child: TextField(
                    controller: _url,
                    decoration: InputDecoration(
                      hintText: 'https://example.com',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintStyle: TextStyle(color: appColors.mutedText),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    style: TextStyle(
                      fontFamily: 'Menlo',
                      fontSize: 12,
                      color: appColors.editorText,
                    ),
                    onSubmitted: (_) => _analyze(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ToolButton(label: 'Go', onPressed: _analyze),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Report output
          Expanded(
            child: EditorPane(
              label: 'Report',
              actions: [
                ToolButton(
                  label: 'Copy',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _output.text)),
                ),
              ],
              placeholder: 'Detection results appear here...',
              readOnly: true,
              controller: _output,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: errorToolTextStyle(context)),
          ],
        ],
      ),
    );
  }
}

class _FetchedPage {
  const _FetchedPage({
    required this.url,
    required this.statusCode,
    required this.headers,
    required this.cookies,
    required this.html,
    required this.scripts,
    required this.inlineScripts,
  });

  final String url;
  final int statusCode;
  final Map<String, String> headers;
  final Map<String, String> cookies;
  final String html;
  final List<String> scripts;
  final List<String> inlineScripts;
}

String _formatAntiBotResult(_AntiBotAnalysisResult result, int statusCode) {
  final buffer = StringBuffer();
  buffer.writeln('URL: ${result.url}');
  buffer.writeln('Status: $statusCode');
  buffer.writeln('Risk Level: ${result.riskLevel.label}');
  buffer.writeln();
  buffer.writeln(result.summary);
  buffer.writeln();
  if (result.detections.isEmpty) {
    buffer.writeln('No protection detected.');
    return buffer.toString().trimRight();
  }
  buffer.writeln('Detections:');
  for (final detection in result.detections) {
    final value = detection.matchedValue ?? detection.matchedPattern;
    buffer.writeln(
      '  - ${detection.technology} (${detection.category.label}, ${detection.patternType.label}, ${detection.confidence}%)',
    );
    buffer.writeln('    Match: $value');
  }
  return buffer.toString().trimRight();
}

class _AntiBotTechnology {
  const _AntiBotTechnology({
    required this.name,
    required this.category,
    required this.website,
    required this.description,
    required this.patterns,
  });

  final String name;
  final AntiBotCategory category;
  final String website;
  final String description;
  final List<_AntiBotPattern> patterns;
}

class _AntiBotPattern {
  const _AntiBotPattern({
    required this.type,
    required this.key,
    required this.regex,
    required this.confidence,
  });

  final AntiBotPatternType type;
  final String? key;
  final String regex;
  final int confidence;
}

class _AntiBotDetection {
  const _AntiBotDetection({
    required this.technology,
    required this.category,
    required this.patternType,
    required this.matchedPattern,
    required this.matchedValue,
    required this.confidence,
  });

  final String technology;
  final AntiBotCategory category;
  final AntiBotPatternType patternType;
  final String matchedPattern;
  final String? matchedValue;
  final int confidence;
}

class _AntiBotAnalysisResult {
  const _AntiBotAnalysisResult({
    required this.url,
    required this.detections,
    required this.antiBot,
    required this.captcha,
    required this.fingerprinting,
    required this.waf,
    required this.summary,
    required this.riskLevel,
  });

  final String url;
  final List<_AntiBotDetection> detections;
  final List<_AntiBotDetection> antiBot;
  final List<_AntiBotDetection> captcha;
  final List<_AntiBotDetection> fingerprinting;
  final List<_AntiBotDetection> waf;
  final String summary;
  final AntiBotRiskLevel riskLevel;
}

class _AntiBotDetector {
  static const String defaultUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.85 Safari/537.36';

  static const List<_AntiBotTechnology> technologies = [
    _AntiBotTechnology(
      name: 'Cloudflare Bot Management',
      category: AntiBotCategory.antiBot,
      website: 'https://www.cloudflare.com/products/bot-management/',
      description: 'Enterprise bot management solution from Cloudflare',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'cf_clearance',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '__cf_bm',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'cf_ob_info',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_cf_chl',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'cf-ray',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'cf-cache-status',
          regex: '.*',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'server',
          regex: 'cloudflare',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'challenges\\.cloudflare\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: '/cdn-cgi/challenge-platform/',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'Checking your browser',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'cf-browser-verification',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'window._cf_chl_opt',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Akamai Bot Manager',
      category: AntiBotCategory.antiBot,
      website: 'https://www.akamai.com/products/bot-manager',
      description: 'Advanced bot detection and mitigation from Akamai',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_abck',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'ak_bmsc',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'bm_sz',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'bm_sv',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'bm_mi',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'ak\\.js',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'akamai.*sensor',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'window._cf',
          regex: '.*',
          confidence: 50,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'bmak',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'DataDome',
      category: AntiBotCategory.antiBot,
      website: 'https://datadome.co/',
      description: 'Real-time bot protection for web, mobile apps and APIs',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'datadome',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'datadome-_zldp',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'datadome-_zldt',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'js\\.datadome\\.co',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'tags\\.datadome\\.co',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-datadome',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-dd-b',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-dd-type',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'window.ddjskey',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'DataDome',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'PerimeterX',
      category: AntiBotCategory.antiBot,
      website: 'https://www.perimeterx.com/',
      description: 'Bot detection using behavioral analysis',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_px',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_px2',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_px3',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_pxvid',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_pxhd',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_pxde',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'client\\.perimeterx\\.net',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'captcha\\.px-cdn\\.net',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'window._pxAppId',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'PX',
          regex: '.*',
          confidence: 80,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Imperva/Incapsula',
      category: AntiBotCategory.antiBot,
      website: 'https://www.imperva.com/',
      description: 'Application security and bot management',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'incap_ses_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'visid_incap_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'nlbi_',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'reese84',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-iinfo',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-cdn',
          regex: 'imperva|incapsula',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: '_Incapsula_Resource',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: '/_Incapsula_Resource\\?',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Kasada',
      category: AntiBotCategory.antiBot,
      website: 'https://www.kasada.io/',
      description: 'Polyform bot defense platform',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'x-kpsdk-ct',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'x-kpsdk-cd',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'x-kpsdk-v',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: '/ips\\.js',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'ct\\.kasada',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-kpsdk-ct',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'KPSDK',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Shape Security',
      category: AntiBotCategory.antiBot,
      website: 'https://www.f5.com/products/security/shape-security',
      description: 'F5 Shape bot defense (formerly Shape Security)',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_imp_apg_r_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_imp_apg_v_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'shape\\.com',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: '/async/api\\.js',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'shape',
          regex: '.*',
          confidence: 60,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'AWS WAF',
      category: AntiBotCategory.antiBot,
      website: 'https://aws.amazon.com/waf/',
      description: 'Amazon Web Services Web Application Firewall',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'aws-waf-token',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'awswaf',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-amzn-waf-action',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-amzn-requestid',
          regex: '.*',
          confidence: 50,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'captcha\\.awswaf\\.com',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Distil Networks',
      category: AntiBotCategory.antiBot,
      website: 'https://www.imperva.com/products/advanced-bot-protection/',
      description: 'Advanced bot protection (now part of Imperva)',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'D_SID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'D_IID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'D_UID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'D_HID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'D_ZID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'distil',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'distilIdentificationBlock',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Forter',
      category: AntiBotCategory.antiBot,
      website: 'https://www.forter.com/',
      description: 'E-commerce fraud prevention',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'forterToken',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'forter\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'ftr__',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Sift',
      category: AntiBotCategory.antiBot,
      website: 'https://sift.com/',
      description: 'Digital trust and safety platform',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'cdn\\.sift\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'cdn\\.siftscience\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: '_sift',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Netacea',
      category: AntiBotCategory.antiBot,
      website: 'https://www.netacea.com/',
      description: 'Bot management and attack prevention',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '_netacea_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'netacea',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Reblaze',
      category: AntiBotCategory.antiBot,
      website: 'https://www.reblaze.com/',
      description: 'Cloud-native web security platform',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'rbzid',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: 'rbzsessionid',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-reblaze-protection',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'reCAPTCHA v2',
      category: AntiBotCategory.captcha,
      website: 'https://www.google.com/recaptcha/',
      description: 'Google CAPTCHA (checkbox)',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'google\\.com/recaptcha/api\\.js(?!.*render=)',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'www\\.gstatic\\.com/recaptcha',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'g-recaptcha',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'data-sitekey',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'grecaptcha',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'reCAPTCHA v3',
      category: AntiBotCategory.captcha,
      website: 'https://www.google.com/recaptcha/',
      description: 'Google CAPTCHA (invisible)',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'google\\.com/recaptcha/api\\.js\\?.*render=',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'recaptcha/enterprise\\.js',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'recaptcha-badge',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'grecaptcha.execute',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'hCaptcha',
      category: AntiBotCategory.captcha,
      website: 'https://www.hcaptcha.com/',
      description: 'Privacy-focused CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'hcaptcha\\.com/1/api\\.js',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'js\\.hcaptcha\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'h-captcha',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'data-hcaptcha',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'hcaptcha',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Cloudflare Turnstile',
      category: AntiBotCategory.captcha,
      website: 'https://www.cloudflare.com/products/turnstile/',
      description: 'Cloudflare CAPTCHA alternative',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'challenges\\.cloudflare\\.com/turnstile',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'cf-turnstile',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'turnstile',
          regex: '.*',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'FunCaptcha/Arkose Labs',
      category: AntiBotCategory.captcha,
      website: 'https://www.arkoselabs.com/',
      description: 'Interactive puzzle CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'arkoselabs\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'funcaptcha\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'funcaptcha',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'ArkoseEnforcement',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'GeeTest',
      category: AntiBotCategory.captcha,
      website: 'https://www.geetest.com/',
      description: 'Behavioral CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'geetest\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'gt\\.js',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'geetest_',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'initGeetest',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'KeyCAPTCHA',
      category: AntiBotCategory.captcha,
      website: 'https://www.keycaptcha.com/',
      description: 'Puzzle-based CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'keycaptcha\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'keycaptcha',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'FingerprintJS',
      category: AntiBotCategory.fingerprinting,
      website: 'https://fingerprint.com/',
      description: 'Browser fingerprinting library',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'fpjs\\.io',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'fingerprint\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.script,
          key: null,
          regex: 'fingerprintjs',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'FingerprintJS',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'Fingerprint2',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Canvas Fingerprinting',
      category: AntiBotCategory.fingerprinting,
      website: '',
      description: 'Browser identification via Canvas API',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'toDataURL',
          regex: '.*',
          confidence: 50,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.html,
          key: null,
          regex: 'canvas.*fingerprint',
          confidence: 70,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'WebGL Fingerprinting',
      category: AntiBotCategory.fingerprinting,
      website: '',
      description: 'Browser identification via WebGL',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'WEBGL_debug_renderer_info',
          regex: '.*',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'getExtension',
          regex: '.*',
          confidence: 30,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'AudioContext Fingerprinting',
      category: AntiBotCategory.fingerprinting,
      website: '',
      description: 'Browser identification via Audio API',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'OfflineAudioContext',
          regex: '.*',
          confidence: 60,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.js,
          key: 'createOscillator',
          regex: '.*',
          confidence: 50,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Cloudflare',
      category: AntiBotCategory.waf,
      website: 'https://www.cloudflare.com/',
      description: 'CDN and DDoS protection',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'server',
          regex: 'cloudflare',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'cf-ray',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.cookie,
          key: '__cflb',
          regex: '.*',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Akamai',
      category: AntiBotCategory.waf,
      website: 'https://www.akamai.com/',
      description: 'CDN and web application security',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-akamai-transformed',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'akamai-origin-hop',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'server',
          regex: 'akamai',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Fastly',
      category: AntiBotCategory.waf,
      website: 'https://www.fastly.com/',
      description: 'Edge cloud platform and CDN',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-served-by',
          regex: 'cache-',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-fastly-request-id',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'via',
          regex: 'varnish',
          confidence: 70,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Sucuri',
      category: AntiBotCategory.waf,
      website: 'https://sucuri.net/',
      description: 'Website security and WAF',
      patterns: [
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-sucuri-id',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'server',
          regex: 'sucuri',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: AntiBotPatternType.header,
          key: 'x-sucuri-cache',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
  ];

  static _AntiBotAnalysisResult analyze({
    required String url,
    String? html,
    Map<String, String> headers = const {},
    Map<String, String> cookies = const {},
    List<String> scripts = const [],
    List<String> jsVariables = const [],
  }) {
    final detections = <_AntiBotDetection>[];
    final headersLower = {
      for (final entry in headers.entries)
        entry.key.toLowerCase(): entry.value.toLowerCase(),
    };
    final cookiesLower = {
      for (final entry in cookies.entries) entry.key.toLowerCase(): entry.value,
    };
    final htmlLower = (html ?? '').toLowerCase();
    final scriptsJoined = scripts.join(' ').toLowerCase();
    final jsJoined = jsVariables.join(' ').toLowerCase();

    for (final tech in technologies) {
      for (final pattern in tech.patterns) {
        var matched = false;
        String? matchedValue;
        final regex = RegExp(pattern.regex, caseSensitive: false);
        switch (pattern.type) {
          case AntiBotPatternType.cookie:
            if (pattern.key != null) {
              final key = pattern.key!.toLowerCase();
              for (final entry in cookiesLower.entries) {
                if (entry.key == key || entry.key.startsWith(key)) {
                  if (pattern.regex == '.*' || regex.hasMatch(entry.value)) {
                    matched = true;
                    matchedValue = '${entry.key}=${entry.value}';
                    break;
                  }
                }
              }
            }
            break;
          case AntiBotPatternType.header:
            if (pattern.key != null) {
              final key = pattern.key!.toLowerCase();
              final value = headersLower[key];
              if (value != null &&
                  (pattern.regex == '.*' || regex.hasMatch(value))) {
                matched = true;
                matchedValue = '$key: $value';
              }
            }
            break;
          case AntiBotPatternType.script:
            if (regex.hasMatch(scriptsJoined)) {
              matched = true;
              matchedValue = pattern.regex;
            }
            break;
          case AntiBotPatternType.html:
          case AntiBotPatternType.meta:
            if (regex.hasMatch(htmlLower)) {
              matched = true;
              matchedValue = pattern.regex;
            }
            break;
          case AntiBotPatternType.js:
            if (pattern.key != null &&
                jsJoined.contains(pattern.key!.toLowerCase())) {
              matched = true;
              matchedValue = pattern.key!.toLowerCase();
            }
            break;
          case AntiBotPatternType.url:
            if (regex.hasMatch(url.toLowerCase())) {
              matched = true;
              matchedValue = url;
            }
            break;
        }
        if (matched) {
          detections.add(
            _AntiBotDetection(
              technology: tech.name,
              category: tech.category,
              patternType: pattern.type,
              matchedPattern: pattern.regex,
              matchedValue: matchedValue,
              confidence: pattern.confidence,
            ),
          );
        }
      }
    }

    final bestDetections = <String, _AntiBotDetection>{};
    for (final detection in detections) {
      final existing = bestDetections[detection.technology];
      if (existing == null || detection.confidence > existing.confidence) {
        bestDetections[detection.technology] = detection;
      }
    }

    final uniqueDetections = bestDetections.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final antiBot = uniqueDetections
        .where((d) => d.category == AntiBotCategory.antiBot)
        .toList();
    final captcha = uniqueDetections
        .where((d) => d.category == AntiBotCategory.captcha)
        .toList();
    final fingerprinting = uniqueDetections
        .where((d) => d.category == AntiBotCategory.fingerprinting)
        .toList();
    final waf = uniqueDetections
        .where((d) => d.category == AntiBotCategory.waf)
        .toList();

    final riskLevel = _calculateRiskLevel(antiBot, captcha);
    final summary = _generateSummary(
      antiBot: antiBot,
      captcha: captcha,
      fingerprinting: fingerprinting,
      waf: waf,
      riskLevel: riskLevel,
    );

    return _AntiBotAnalysisResult(
      url: url,
      detections: uniqueDetections,
      antiBot: antiBot,
      captcha: captcha,
      fingerprinting: fingerprinting,
      waf: waf,
      summary: summary,
      riskLevel: riskLevel,
    );
  }

  static AntiBotRiskLevel _calculateRiskLevel(
    List<_AntiBotDetection> antiBot,
    List<_AntiBotDetection> captcha,
  ) {
    const hardAntiBot = [
      'Akamai Bot Manager',
      'DataDome',
      'PerimeterX',
      'Kasada',
      'Shape Security',
    ];
    const mediumAntiBot = [
      'Cloudflare Bot Management',
      'Imperva/Incapsula',
      'AWS WAF',
    ];
    var score = 0;
    for (final detection in antiBot) {
      if (hardAntiBot.contains(detection.technology)) {
        score += 30;
      } else if (mediumAntiBot.contains(detection.technology)) {
        score += 20;
      } else {
        score += 10;
      }
    }
    for (final detection in captcha) {
      if (detection.technology.contains('reCAPTCHA v3') ||
          detection.technology.contains('Arkose')) {
        score += 15;
      } else {
        score += 10;
      }
    }
    if (score == 0) return AntiBotRiskLevel.none;
    if (score <= 15) return AntiBotRiskLevel.low;
    if (score <= 30) return AntiBotRiskLevel.medium;
    if (score <= 50) return AntiBotRiskLevel.high;
    return AntiBotRiskLevel.extreme;
  }

  static String _generateSummary({
    required List<_AntiBotDetection> antiBot,
    required List<_AntiBotDetection> captcha,
    required List<_AntiBotDetection> fingerprinting,
    required List<_AntiBotDetection> waf,
    required AntiBotRiskLevel riskLevel,
  }) {
    final lines = <String>[];
    if (antiBot.isEmpty && captcha.isEmpty && waf.isEmpty) {
      return 'No anti-bot protection detected.';
    }
    if (antiBot.isNotEmpty) {
      lines.add('Anti-Bot: ${antiBot.map((d) => d.technology).join(', ')}');
    }
    if (captcha.isNotEmpty) {
      lines.add('CAPTCHA: ${captcha.map((d) => d.technology).join(', ')}');
    }
    if (waf.isNotEmpty) {
      lines.add('WAF/CDN: ${waf.map((d) => d.technology).join(', ')}');
    }
    if (fingerprinting.isNotEmpty) {
      lines.add(
        'Fingerprinting: ${fingerprinting.map((d) => d.technology).join(', ')}',
      );
    }
    lines.add('');
    lines.add('Scraping Difficulty: ${riskLevel.label}');
    return lines.join('\n');
  }
}

Widget buildAntiBotDetection() {
  return const _AntiBotDetectorView();
}

extension _AntiBotCategoryLabel on AntiBotCategory {
  String get label {
    switch (this) {
      case AntiBotCategory.antiBot:
        return 'Anti-Bot';
      case AntiBotCategory.captcha:
        return 'CAPTCHA';
      case AntiBotCategory.fingerprinting:
        return 'Fingerprinting';
      case AntiBotCategory.waf:
        return 'WAF/CDN';
    }
  }
}

extension _AntiBotPatternTypeLabel on AntiBotPatternType {
  String get label {
    switch (this) {
      case AntiBotPatternType.cookie:
        return 'cookie';
      case AntiBotPatternType.header:
        return 'header';
      case AntiBotPatternType.script:
        return 'script';
      case AntiBotPatternType.html:
        return 'html';
      case AntiBotPatternType.js:
        return 'js';
      case AntiBotPatternType.url:
        return 'url';
      case AntiBotPatternType.meta:
        return 'meta';
    }
  }
}

extension _AntiBotRiskLevelLabel on AntiBotRiskLevel {
  String get label {
    switch (this) {
      case AntiBotRiskLevel.none:
        return 'None';
      case AntiBotRiskLevel.low:
        return 'Low';
      case AntiBotRiskLevel.medium:
        return 'Medium';
      case AntiBotRiskLevel.high:
        return 'High';
      case AntiBotRiskLevel.extreme:
        return 'Extreme';
    }
  }
}
