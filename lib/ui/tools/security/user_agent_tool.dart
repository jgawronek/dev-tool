/// User agent generator/validator tool view.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _UserAgentToolView extends StatefulWidget {
  const _UserAgentToolView();

  @override
  State<_UserAgentToolView> createState() => _UserAgentToolViewState();
}

class _UserAgentToolViewState extends State<_UserAgentToolView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _browser = 'Chrome';
  String _platform = 'Any';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _generate() {
    final platform = _platform == 'Any'
        ? null
        : _UaPlatform.values.firstWhere((value) => value.label == _platform);
    final ua = _UaGenerator.generateFromSelection(_browser, platform);
    setState(() => _input.text = ua);
    _validate();
  }

  void _validate() {
    final result = _UaValidator.validate(_input.text);
    _output.text = _formatUserAgentResult(result);
    setState(() {});
  }

  void _setSample() {
    final sample = _UaGenerator.generate(
      browser: _UaBrowser.chrome,
      platform: _UaPlatform.macOS,
    );
    setState(() => _input.text = sample);
    _validate();
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: buildSplitEditors(
        inputLabel: 'User Agent',
        outputLabel: 'Analysis',
        inputActions: [
          ToolButton(label: 'Go', onPressed: _validate),
          ToolButton(label: 'Generate', onPressed: _generate),
          SmallDropdown(
            items: _UaGenerator.browserLabels,
            initialValue: _browser,
            onChanged: (value) => setState(() => _browser = value),
          ),
          SmallDropdown(
            items: _UaGenerator.platformLabels,
            initialValue: _platform,
            onChanged: (value) => setState(() => _platform = value),
          ),
        ],
        outputActions: [
          ToolButton(
            label: 'Copy',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _output.text)),
          ),
        ],
        inputController: _input,
        outputController: _output,
        inputPlaceholder: 'Paste or generate a user agent...',
        outputPlaceholder: 'Analysis appears here...',
        onInputChanged: (_) => _validate(),
      ),
    );
  }
}

String _formatUserAgentResult(_UaValidationResult result) {
  final parsed = result.parsed;
  final buffer = StringBuffer();
  buffer.writeln('Summary: ${result.summary}');
  buffer.writeln('Score: ${result.score}');
  buffer.writeln('Valid: ${result.isValid ? "Yes" : "No"}');
  buffer.writeln('Confidence: ${(parsed.confidence * 100).round()}%');
  buffer.writeln('Length: ${parsed.raw.length}');
  if (parsed.isBot) {
    buffer.writeln('Bot: ${parsed.botName ?? "Unknown"}');
  }
  if (parsed.browser != null) {
    final browser = parsed.browser!;
    buffer.writeln('Browser: ${browser.name} ${browser.version}');
    if (browser.isWebView) {
      buffer.writeln('WebView: Yes');
    }
  }
  if (parsed.webView != null) {
    final webView = parsed.webView!;
    buffer.writeln('WebView App: ${webView.app}');
    if (webView.appVersion != null) {
      buffer.writeln('App Version: ${webView.appVersion}');
    }
    if (webView.buildId != null) {
      buffer.writeln('Build ID: ${webView.buildId}');
    }
    if (webView.additionalInfo.isNotEmpty) {
      buffer.writeln('App Details:');
      webView.additionalInfo.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
    }
  }
  if (parsed.platform != null) {
    final platform = parsed.platform!;
    final parts = [
      platform.name,
      if (platform.version != null) platform.version!,
      if (platform.architecture != null) '(${platform.architecture})',
    ];
    buffer.writeln('Platform: ${parts.join(' ')}');
  }
  if (parsed.device != null) {
    final device = parsed.device!;
    final parts = [
      device.type.name,
      if (device.model != null) device.model!,
      if (device.vendor != null) '(${device.vendor})',
    ];
    buffer.writeln('Device: ${parts.join(' ')}');
  }
  if (parsed.engine != null) {
    final engine = parsed.engine!;
    buffer.writeln(
      'Engine: ${engine.name}${engine.version != null ? " ${engine.version}" : ""}',
    );
  }
  if (parsed.issues.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Issues:');
    for (final issue in parsed.issues) {
      buffer.writeln(
        '  ${issue.severity.name.toUpperCase()}: ${issue.message}',
      );
    }
  }
  return buffer.toString().trimRight();
}

enum _UaBrowser {
  chrome('Chrome'),
  safari('Safari'),
  firefox('Firefox'),
  edge('Edge'),
  brave('Brave'),
  chromium('Chromium'),
  facebook('Facebook'),
  instagram('Instagram'),
  twitter('Twitter'),
  tiktok('TikTok'),
  linkedin('LinkedIn'),
  snapchat('Snapchat'),
  pinterest('Pinterest'),
  whatsapp('WhatsApp'),
  telegram('Telegram'),
  discord('Discord'),
  slack('Slack'),
  wechat('WeChat'),
  line('Line');

  const _UaBrowser(this.label);
  final String label;
}

enum _UaPlatform {
  macOS('macOS'),
  windows('Windows'),
  linux('Linux'),
  iOS('iOS'),
  android('Android');

  const _UaPlatform(this.label);
  final String label;
}

class _UaGenerator {
  static final Random _rand = Random();

  static const List<String> chromeVersions = [
    '120.0.6099.109',
    '121.0.6167.85',
    '122.0.6261.94',
    '123.0.6312.58',
    '124.0.6367.91',
    '125.0.6422.76',
    '126.0.6478.126',
    '127.0.6533.72',
    '128.0.6613.84',
    '129.0.6668.70',
    '130.0.6723.91',
    '131.0.6778.85',
  ];

  static const List<String> chromiumVersions = [
    '120.0.6099.0',
    '121.0.6167.0',
    '122.0.6261.0',
    '123.0.6312.0',
    '124.0.6367.0',
    '125.0.6422.0',
    '126.0.6478.0',
    '127.0.6533.0',
    '128.0.6613.0',
    '129.0.6668.0',
    '130.0.6723.0',
    '131.0.6778.0',
  ];

  static const List<String> braveVersions = [
    '1.60.125',
    '1.61.109',
    '1.62.153',
    '1.63.165',
    '1.64.109',
    '1.65.132',
    '1.66.110',
    '1.67.123',
    '1.68.134',
    '1.69.153',
    '1.70.117',
    '1.71.114',
  ];

  static const List<String> firefoxVersions = [
    '121.0',
    '122.0',
    '123.0',
    '124.0',
    '125.0',
    '126.0',
    '127.0',
    '128.0',
    '129.0',
    '130.0',
    '131.0',
    '132.0',
  ];

  static const List<String> safariVersions = [
    '17.0',
    '17.1',
    '17.2',
    '17.3',
    '17.4',
    '17.5',
    '17.6',
    '18.0',
    '18.1',
  ];

  static const List<String> edgeVersions = [
    '120.0.2210.91',
    '121.0.2277.83',
    '122.0.2365.66',
    '123.0.2420.65',
    '124.0.2478.67',
    '125.0.2535.51',
    '126.0.2592.68',
    '127.0.2651.74',
    '128.0.2739.42',
    '129.0.2792.52',
    '130.0.2849.56',
    '131.0.2903.63',
  ];

  static const List<String> facebookAppVersions = [
    '450.0.0.40.109',
    '451.0.0.41.110',
    '452.0.0.42.111',
    '453.0.0.43.112',
    '454.0.0.44.113',
  ];
  static const List<String> instagramAppVersions = [
    '312.0.0.34.111',
    '313.0.0.35.112',
    '314.0.0.36.113',
    '315.0.0.37.114',
    '316.0.0.38.115',
  ];
  static const List<String> twitterAppVersions = [
    '10.23.0',
    '10.24.0',
    '10.25.0',
    '10.26.0',
    '10.27.0',
    '10.28.0',
  ];
  static const List<String> tiktokAppVersions = [
    '32.5.3',
    '32.6.4',
    '32.7.5',
    '33.0.3',
    '33.1.4',
    '33.2.5',
  ];
  static const List<String> linkedinAppVersions = [
    '9.29.5421',
    '9.30.5432',
    '9.31.5443',
    '9.32.5454',
    '9.33.5465',
  ];
  static const List<String> snapchatAppVersions = [
    '12.75.0.38',
    '12.76.0.39',
    '12.77.0.40',
    '12.78.0.41',
    '12.79.0.42',
  ];
  static const List<String> pinterestAppVersions = [
    '11.38.0',
    '11.39.0',
    '11.40.0',
    '11.41.0',
    '11.42.0',
  ];
  static const List<String> whatsappAppVersions = [
    '2.24.2.76',
    '2.24.3.77',
    '2.24.4.78',
    '2.24.5.79',
    '2.24.6.80',
  ];
  static const List<String> telegramAppVersions = [
    '10.6.2',
    '10.7.3',
    '10.8.4',
    '10.9.5',
    '10.10.6',
  ];
  static const List<String> discordAppVersions = [
    '223.0',
    '224.0',
    '225.0',
    '226.0',
    '227.0',
  ];
  static const List<String> slackAppVersions = [
    '24.01.10',
    '24.02.11',
    '24.03.12',
    '24.04.13',
    '24.05.14',
  ];
  static const List<String> wechatAppVersions = [
    '8.0.43',
    '8.0.44',
    '8.0.45',
    '8.0.46',
    '8.0.47',
  ];
  static const List<String> lineAppVersions = [
    '14.0.1',
    '14.1.2',
    '14.2.3',
    '14.3.4',
    '14.4.5',
  ];

  static const List<_UaPair> macOSVersions = [
    _UaPair('10_15_7', '10.15.7'),
    _UaPair('11_7_10', '11.7.10'),
    _UaPair('12_7_6', '12.7.6'),
    _UaPair('13_6_9', '13.6.9'),
    _UaPair('14_6_1', '14.6.1'),
    _UaPair('15_1', '15.1'),
  ];

  static const List<_UaPair> windowsVersions = [
    _UaPair('10.0; Win64; x64', '10'),
    _UaPair('10.0; Win64; x64', '11'),
  ];

  static const List<String> iOSVersions = [
    '16_6',
    '17_0',
    '17_1',
    '17_2',
    '17_3',
    '17_4',
    '17_5',
    '17_6',
    '18_0',
    '18_1',
  ];

  static const List<String> androidVersions = ['11', '12', '13', '14', '15'];

  static const List<_UaPair> iPhoneModels = [
    _UaPair('iPhone13,2', 'iPhone 12'),
    _UaPair('iPhone13,3', 'iPhone 12 Pro'),
    _UaPair('iPhone13,4', 'iPhone 12 Pro Max'),
    _UaPair('iPhone14,5', 'iPhone 13'),
    _UaPair('iPhone14,2', 'iPhone 13 Pro'),
    _UaPair('iPhone14,3', 'iPhone 13 Pro Max'),
    _UaPair('iPhone14,7', 'iPhone 14'),
    _UaPair('iPhone14,8', 'iPhone 14 Plus'),
    _UaPair('iPhone15,2', 'iPhone 14 Pro'),
    _UaPair('iPhone15,3', 'iPhone 14 Pro Max'),
    _UaPair('iPhone15,4', 'iPhone 15'),
    _UaPair('iPhone15,5', 'iPhone 15 Plus'),
    _UaPair('iPhone16,1', 'iPhone 15 Pro'),
    _UaPair('iPhone16,2', 'iPhone 15 Pro Max'),
    _UaPair('iPhone17,1', 'iPhone 16'),
    _UaPair('iPhone17,2', 'iPhone 16 Plus'),
    _UaPair('iPhone17,3', 'iPhone 16 Pro'),
    _UaPair('iPhone17,4', 'iPhone 16 Pro Max'),
  ];

  static const List<_UaDevice> androidDevices = [
    _UaDevice('Samsung', 'SM-S911B', 'Galaxy S23'),
    _UaDevice('Samsung', 'SM-S918B', 'Galaxy S23 Ultra'),
    _UaDevice('Samsung', 'SM-S921B', 'Galaxy S24'),
    _UaDevice('Samsung', 'SM-S928B', 'Galaxy S24 Ultra'),
    _UaDevice('Samsung', 'SM-A546B', 'Galaxy A54'),
    _UaDevice('Samsung', 'SM-A556B', 'Galaxy A55'),
    _UaDevice('Google', 'Pixel 7', 'Pixel 7'),
    _UaDevice('Google', 'Pixel 7 Pro', 'Pixel 7 Pro'),
    _UaDevice('Google', 'Pixel 8', 'Pixel 8'),
    _UaDevice('Google', 'Pixel 8 Pro', 'Pixel 8 Pro'),
    _UaDevice('Google', 'Pixel 9', 'Pixel 9'),
    _UaDevice('Google', 'Pixel 9 Pro', 'Pixel 9 Pro'),
    _UaDevice('OnePlus', 'CPH2449', 'OnePlus 11'),
    _UaDevice('OnePlus', 'CPH2551', 'OnePlus 12'),
    _UaDevice('Xiaomi', '2312DRA50G', 'Xiaomi 14'),
    _UaDevice('Xiaomi', '2311DRK48G', 'Xiaomi 14 Pro'),
    _UaDevice('Oppo', 'CPH2551', 'Find X7'),
    _UaDevice('Huawei', 'ALN-AL00', 'Mate 60 Pro'),
  ];

  static const String webkitVersion = '537.36';
  static const String geckoVersion = '20100101';
  static const List<String> facebookBuildIds = [
    '477985655',
    '478012312',
    '478123456',
    '478234567',
    '478345678',
  ];

  static const List<String> browserLabels = [
    'Random',
    'Random Standard',
    'Random WebView',
    'Chrome',
    'Safari',
    'Firefox',
    'Edge',
    'Brave',
    'Chromium',
    'Facebook',
    'Instagram',
    'Twitter',
    'TikTok',
    'LinkedIn',
    'Snapchat',
    'Pinterest',
    'WhatsApp',
    'Telegram',
    'Discord',
    'Slack',
    'WeChat',
    'Line',
  ];

  static const List<String> platformLabels = [
    'Any',
    'macOS',
    'Windows',
    'Linux',
    'iOS',
    'Android',
  ];

  static String generateFromSelection(String selection, _UaPlatform? platform) {
    if (selection == 'Random') {
      return random();
    }
    if (selection == 'Random Standard') {
      return randomStandardBrowser();
    }
    if (selection == 'Random WebView') {
      return randomWebView();
    }
    final browser = _UaBrowser.values.firstWhere(
      (value) => value.label == selection,
    );
    return generate(browser: browser, platform: platform);
  }

  static String generate({
    required _UaBrowser browser,
    _UaPlatform? platform,
    String? version,
  }) {
    final _UaPlatform platformValue = platform ?? _pick(_UaPlatform.values);
    switch (browser) {
      case _UaBrowser.chrome:
        return _generateChrome(platformValue, version);
      case _UaBrowser.safari:
        return _generateSafari(platformValue, version);
      case _UaBrowser.firefox:
        return _generateFirefox(platformValue, version);
      case _UaBrowser.edge:
        return _generateEdge(platformValue, version);
      case _UaBrowser.brave:
        return _generateBrave(platformValue, version);
      case _UaBrowser.chromium:
        return _generateChromium(platformValue, version);
      case _UaBrowser.facebook:
        return _generateFacebook(platformValue, version);
      case _UaBrowser.instagram:
        return _generateInstagram(platformValue, version);
      case _UaBrowser.twitter:
        return _generateTwitter(platformValue, version);
      case _UaBrowser.tiktok:
        return _generateTikTok(platformValue, version);
      case _UaBrowser.linkedin:
        return _generateLinkedIn(platformValue, version);
      case _UaBrowser.snapchat:
        return _generateSnapchat(platformValue, version);
      case _UaBrowser.pinterest:
        return _generatePinterest(platformValue, version);
      case _UaBrowser.whatsapp:
        return _generateWhatsApp(platformValue, version);
      case _UaBrowser.telegram:
        return _generateTelegram(platformValue, version);
      case _UaBrowser.discord:
        return _generateDiscord(platformValue, version);
      case _UaBrowser.slack:
        return _generateSlack(platformValue, version);
      case _UaBrowser.wechat:
        return _generateWeChat(platformValue, version);
      case _UaBrowser.line:
        return _generateLine(platformValue, version);
    }
  }

  static String random() {
    return generate(
      browser: _pick(_UaBrowser.values),
      platform: _pick(_UaPlatform.values),
    );
  }

  static String randomStandardBrowser() {
    const standard = [
      _UaBrowser.chrome,
      _UaBrowser.safari,
      _UaBrowser.firefox,
      _UaBrowser.edge,
      _UaBrowser.brave,
      _UaBrowser.chromium,
    ];
    return generate(
      browser: _pick(standard),
      platform: _pick(_UaPlatform.values),
    );
  }

  static String randomWebView() {
    const webviews = [
      _UaBrowser.facebook,
      _UaBrowser.instagram,
      _UaBrowser.twitter,
      _UaBrowser.tiktok,
      _UaBrowser.linkedin,
      _UaBrowser.snapchat,
      _UaBrowser.pinterest,
      _UaBrowser.whatsapp,
      _UaBrowser.telegram,
      _UaBrowser.discord,
      _UaBrowser.slack,
      _UaBrowser.wechat,
      _UaBrowser.line,
    ];
    const platforms = [_UaPlatform.iOS, _UaPlatform.android];
    return generate(browser: _pick(webviews), platform: _pick(platforms));
  }

  static String _generateChrome(_UaPlatform platform, String? version) {
    final chromeVersion = version ?? _pick(chromeVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/$webkitVersion (KHTML, like Gecko) CriOS/$chromeVersion Mobile/15E148 Safari/$webkitVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Mobile Safari/$webkitVersion';
    }
  }

  static String _generateChromium(_UaPlatform platform, String? version) {
    final chromiumVersion = version ?? _pick(chromiumVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Safari/$webkitVersion';
      case _UaPlatform.iOS:
        return _generateChrome(_UaPlatform.iOS, version);
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Mobile Safari/$webkitVersion';
    }
  }

  static String _generateBrave(_UaPlatform platform, String? version) {
    final braveVersion = version ?? _pick(braveVersions);
    final chromeVersion = _pick(chromeVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Brave/$braveVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Brave/$braveVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Brave/$braveVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final safariVersion = _pick(safariVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariVersion Mobile/15E148 Safari/604.1 Brave/$braveVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Mobile Safari/$webkitVersion Brave/$braveVersion';
    }
  }

  static String _generateSafari(_UaPlatform platform, String? version) {
    final safariVersion = version ?? _pick(safariVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariVersion Safari/605.1.15';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariVersion Mobile/15E148 Safari/604.1';
      case _UaPlatform.windows:
      case _UaPlatform.linux:
      case _UaPlatform.android:
        return _generateSafari(_UaPlatform.macOS, version);
    }
  }

  static String _generateFirefox(_UaPlatform platform, String? version) {
    final firefoxVersion = version ?? _pick(firefoxVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer; rv:$firefoxVersion) Gecko/$geckoVersion Firefox/$firefoxVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer; rv:$firefoxVersion) Gecko/$geckoVersion Firefox/$firefoxVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64; rv:$firefoxVersion) Gecko/$geckoVersion Firefox/$firefoxVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/$firefoxVersion Mobile/15E148 Safari/605.1.15';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        return 'Mozilla/5.0 (Android $androidVer; Mobile; rv:$firefoxVersion) Gecko/$firefoxVersion Firefox/$firefoxVersion';
    }
  }

  static String _generateEdge(_UaPlatform platform, String? version) {
    final edgeVersion = version ?? _pick(edgeVersions);
    final chromeVersion = _pick(chromeVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Edg/$edgeVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Edg/$edgeVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Edg/$edgeVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final safariVersion = _pick(safariVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/$safariVersion EdgiOS/$edgeVersion Mobile/15E148 Safari/$webkitVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Mobile Safari/$webkitVersion EdgA/$edgeVersion';
    }
  }

  static String _generateFacebook(_UaPlatform platform, String? version) {
    final fbVersion = version ?? _pick(facebookAppVersions);
    final buildId = _pick(facebookBuildIds);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final deviceId = _pick(iPhoneModels).key;
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/$fbVersion;FBBV/$buildId;FBDV/$deviceId;FBMD/iPhone;FBSN/iOS;FBSV/${iosVer.replaceAll("_", ".")};FBSS/3;FBID/phone;FBLC/en_US;FBOP/5]';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices);
        final dpi = _pick(['240', '320', '480', '640']);
        return 'Mozilla/5.0 (Linux; Android $androidVer; ${device.model} Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion [FB_IAB/FB4A;FBAV/$fbVersion;FBBV/$buildId;FBDM/{density=$dpi.0,width=1080,height=2340};FBLC/en_US;FBRV/$buildId;FBCR/;FBMF/${device.vendor};FBBD/${device.vendor};FBPN/com.facebook.katana;FBDV/${device.model};FBSV/$androidVer;FBOP/1;FBCA/armeabi-v7a:armeabi;]';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateFacebook(_UaPlatform.iOS, version);
    }
  }

  static String _generateInstagram(_UaPlatform platform, String? version) {
    final igVersion = version ?? _pick(instagramAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram $igVersion (iPhone; iOS ${iosVer.replaceAll("_", ".")}); en_US; en-US; scale=3.00; 1170x2532; ${_pick(facebookBuildIds)})';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices);
        return 'Mozilla/5.0 (Linux; Android $androidVer; ${device.model} Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Instagram $igVersion Android ($androidVer/${device.model}; 480dpi; 1080x2340; ${device.vendor}; ${device.model}; ${device.model.toLowerCase()}; qcom; en_US; ${_pick(facebookBuildIds)})';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateInstagram(_UaPlatform.iOS, version);
    }
  }

  static String _generateTwitter(_UaPlatform platform, String? version) {
    final twitterVersion = version ?? _pick(twitterAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Twitter for iPhone/$twitterVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Twitter for Android/$twitterVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateTwitter(_UaPlatform.iOS, version);
    }
  }

  static String _generateTikTok(_UaPlatform platform, String? version) {
    final tiktokVersion = version ?? _pick(tiktokAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final deviceId = _pick(iPhoneModels).key;
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 BytedanceWebview/d8a21c6 musical_ly_$tiktokVersion JsSdk/1.0 NetType/WIFI Channel/App Store ByteLocale/en Region/US FalconTag/$deviceId';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices);
        return 'Mozilla/5.0 (Linux; Android $androidVer; ${device.model} Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion trill/$tiktokVersion BytedanceWebview/d8a21c6 JsSdk/1.0 NetType/wifi Channel/googleplay AppName/musical_ly app_version/$tiktokVersion ByteLocale/en Region/US';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateTikTok(_UaPlatform.iOS, version);
    }
  }

  static String _generateLinkedIn(_UaPlatform platform, String? version) {
    final linkedinVersion = version ?? _pick(linkedinAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [LinkedInApp]/$linkedinVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion [LinkedInApp]/$linkedinVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateLinkedIn(_UaPlatform.iOS, version);
    }
  }

  static String _generateSnapchat(_UaPlatform platform, String? version) {
    final snapVersion = version ?? _pick(snapchatAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Snapchat/$snapVersion (iPhone; iOS ${iosVer.replaceAll("_", ".")}; Scale/3.00)';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Snapchat/$snapVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateSnapchat(_UaPlatform.iOS, version);
    }
  }

  static String _generatePinterest(_UaPlatform platform, String? version) {
    final pinterestVersion = version ?? _pick(pinterestAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [Pinterest/iOS $pinterestVersion]';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion [Pinterest/Android $pinterestVersion]';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generatePinterest(_UaPlatform.iOS, version);
    }
  }

  static String _generateWhatsApp(_UaPlatform platform, String? version) {
    final waVersion = version ?? _pick(whatsappAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 WhatsApp/$waVersion w';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion WhatsApp/$waVersion a';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateWhatsApp(_UaPlatform.iOS, version);
    }
  }

  static String _generateTelegram(_UaPlatform platform, String? version) {
    final tgVersion = version ?? _pick(telegramAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Telegram-iOS/$tgVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion TelegramAndroid/$tgVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateTelegram(_UaPlatform.iOS, version);
    }
  }

  static String _generateDiscord(_UaPlatform platform, String? version) {
    final discordVersion = version ?? _pick(discordAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Discord/$discordVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion discord/$discordVersion';
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) discord/$discordVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) discord/$discordVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) discord/$discordVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
    }
  }

  static String _generateSlack(_UaPlatform platform, String? version) {
    final slackVersion = version ?? _pick(slackAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Slack/$slackVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Slack/$slackVersion';
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Slack/$slackVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Slack/$slackVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Slack/$slackVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
    }
  }

  static String _generateWeChat(_UaPlatform platform, String? version) {
    final wechatVersion = version ?? _pick(wechatAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/$wechatVersion NetType/WIFI Language/en';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion MicroMessenger/$wechatVersion NetType/WIFI Language/en';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateWeChat(_UaPlatform.iOS, version);
    }
  }

  static String _generateLine(_UaPlatform platform, String? version) {
    final lineVersion = version ?? _pick(lineAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari Line/$lineVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Line/$lineVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateLine(_UaPlatform.iOS, version);
    }
  }

  static T _pick<T>(List<T> items) => items[_rand.nextInt(items.length)];
}

class _UaPair {
  const _UaPair(this.key, this.value);
  final String key;
  final String value;
}

class _UaDevice {
  const _UaDevice(this.vendor, this.model, this.name);
  final String vendor;
  final String model;
  final String name;
}

class _UaValidationResult {
  const _UaValidationResult({
    required this.isValid,
    required this.parsed,
    required this.score,
    required this.summary,
  });

  final bool isValid;
  final _UaParsedUserAgent parsed;
  final int score;
  final String summary;
}

class _UaParsedUserAgent {
  const _UaParsedUserAgent({
    required this.raw,
    required this.browser,
    required this.platform,
    required this.device,
    required this.engine,
    required this.webView,
    required this.isBot,
    required this.botName,
    required this.isValid,
    required this.issues,
    required this.confidence,
  });

  final String raw;
  final _UaBrowserInfo? browser;
  final _UaPlatformInfo? platform;
  final _UaDeviceInfo? device;
  final _UaEngineInfo? engine;
  final _UaWebViewInfo? webView;
  final bool isBot;
  final String? botName;
  final bool isValid;
  final List<_UaValidationIssue> issues;
  final double confidence;
}

class _UaBrowserInfo {
  const _UaBrowserInfo({
    required this.name,
    required this.version,
    required this.majorVersion,
    required this.isWebView,
  });

  final String name;
  final String version;
  final int? majorVersion;
  final bool isWebView;
}

class _UaPlatformInfo {
  const _UaPlatformInfo({
    required this.name,
    required this.version,
    required this.architecture,
  });

  final String name;
  final String? version;
  final String? architecture;
}

class _UaDeviceInfo {
  const _UaDeviceInfo({
    required this.type,
    required this.model,
    required this.vendor,
  });

  final _UaDeviceType type;
  final String? model;
  final String? vendor;
}

class _UaEngineInfo {
  const _UaEngineInfo({required this.name, required this.version});
  final String name;
  final String? version;
}

class _UaWebViewInfo {
  const _UaWebViewInfo({
    required this.app,
    required this.appVersion,
    required this.buildId,
    required this.additionalInfo,
  });

  final String app;
  final String? appVersion;
  final String? buildId;
  final Map<String, String> additionalInfo;
}

enum _UaDeviceType { desktop, mobile, tablet, tv, bot, unknown }

class _UaValidationIssue {
  const _UaValidationIssue({
    required this.severity,
    required this.message,
    required this.field,
  });

  final _UaIssueSeverity severity;
  final String message;
  final String? field;
}

enum _UaIssueSeverity { error, warning, info }

class _UaRange {
  const _UaRange(this.min, this.max);
  final int min;
  final int max;
  bool contains(int value) => value >= min && value <= max;
}

class _UaValidator {
  static const List<_UaBotPattern> botPatterns = [
    _UaBotPattern('googlebot', 'Googlebot'),
    _UaBotPattern('bingbot', 'Bingbot'),
    _UaBotPattern('slurp', 'Yahoo Slurp'),
    _UaBotPattern('duckduckbot', 'DuckDuckBot'),
    _UaBotPattern('baiduspider', 'Baiduspider'),
    _UaBotPattern('yandexbot', 'YandexBot'),
    _UaBotPattern('facebookexternalhit', 'Facebook Bot'),
    _UaBotPattern('twitterbot', 'Twitter Bot'),
    _UaBotPattern('linkedinbot', 'LinkedIn Bot'),
    _UaBotPattern('applebot', 'Applebot'),
    _UaBotPattern('semrushbot', 'SEMrush Bot'),
    _UaBotPattern('ahrefsbot', 'Ahrefs Bot'),
    _UaBotPattern('mj12bot', 'Majestic Bot'),
    _UaBotPattern('dotbot', 'Moz Bot'),
    _UaBotPattern('rogerbot', 'Moz Bot'),
    _UaBotPattern('screaming frog', 'Screaming Frog'),
    _UaBotPattern('crawler', 'Generic Crawler'),
    _UaBotPattern('spider', 'Generic Spider'),
    _UaBotPattern('scraper', 'Scraper'),
    _UaBotPattern('headless', 'Headless Browser'),
    _UaBotPattern('phantom', 'PhantomJS'),
    _UaBotPattern('selenium', 'Selenium'),
    _UaBotPattern('puppeteer', 'Puppeteer'),
    _UaBotPattern('playwright', 'Playwright'),
    _UaBotPattern('wget', 'Wget'),
    _UaBotPattern('curl', 'cURL'),
    _UaBotPattern('python-requests', 'Python Requests'),
    _UaBotPattern('python-urllib', 'Python urllib'),
    _UaBotPattern('java/', 'Java Client'),
    _UaBotPattern('libwww', 'libwww'),
    _UaBotPattern('httpclient', 'HTTP Client'),
    _UaBotPattern('okhttp', 'OkHttp'),
    _UaBotPattern('axios', 'Axios'),
    _UaBotPattern('node-fetch', 'Node Fetch'),
    _UaBotPattern('go-http-client', 'Go HTTP Client'),
    _UaBotPattern('guzzle', 'Guzzle'),
  ];

  static const List<_UaBrowserPattern> browserPatterns = [
    _UaBrowserPattern('[fban/fbios', 'Facebook iOS', 'FBAV/([\\d.]+)', true),
    _UaBrowserPattern(
      '[fb_iab/fb4a',
      'Facebook Android',
      'FBAV/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('instagram', 'Instagram', 'Instagram ([\\d.]+)', true),
    _UaBrowserPattern(
      'twitter for iphone',
      'Twitter iOS',
      'Twitter for iPhone/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern(
      'twitter for android',
      'Twitter Android',
      'Twitter for Android/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern(
      'bytedancewebview',
      'TikTok',
      'musical_ly[_/]([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('trill/', 'TikTok', 'trill/([\\d.]+)', true),
    _UaBrowserPattern(
      '[linkedinapp]',
      'LinkedIn',
      '\\[LinkedInApp\\]/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('snapchat/', 'Snapchat', 'Snapchat/([\\d.]+)', true),
    _UaBrowserPattern('[pinterest', 'Pinterest', 'Pinterest', true),
    _UaBrowserPattern('whatsapp/', 'WhatsApp', 'WhatsApp/([\\d.]+)', true),
    _UaBrowserPattern(
      'telegram-ios',
      'Telegram iOS',
      'Telegram-iOS/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern(
      'telegramandroid',
      'Telegram Android',
      'TelegramAndroid/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('discord/', 'Discord', 'discord/([\\d.]+)', true),
    _UaBrowserPattern('slack/', 'Slack', 'Slack/([\\d.]+)', true),
    _UaBrowserPattern(
      'micromessenger/',
      'WeChat',
      'MicroMessenger/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('line/', 'Line', 'Line/([\\d.]+)', true),
    _UaBrowserPattern('edg/', 'Edge', 'Edg/([\\d.]+)', false),
    _UaBrowserPattern('edga/', 'Edge Android', 'EdgA/([\\d.]+)', false),
    _UaBrowserPattern('edgios/', 'Edge iOS', 'EdgiOS/([\\d.]+)', false),
    _UaBrowserPattern('opr/', 'Opera', 'OPR/([\\d.]+)', false),
    _UaBrowserPattern('opera', 'Opera', 'Opera[/ ]([\\d.]+)', false),
    _UaBrowserPattern('vivaldi/', 'Vivaldi', 'Vivaldi/([\\d.]+)', false),
    _UaBrowserPattern(
      'yabrowser/',
      'Yandex Browser',
      'YaBrowser/([\\d.]+)',
      false,
    ),
    _UaBrowserPattern('brave/', 'Brave', 'Brave/([\\d.]+)', false),
    _UaBrowserPattern('chromium/', 'Chromium', 'Chromium/([\\d.]+)', false),
    _UaBrowserPattern(
      'samsungbrowser/',
      'Samsung Browser',
      'SamsungBrowser/([\\d.]+)',
      false,
    ),
    _UaBrowserPattern('ucbrowser/', 'UC Browser', 'UCBrowser/([\\d.]+)', false),
    _UaBrowserPattern('crios/', 'Chrome iOS', 'CriOS/([\\d.]+)', false),
    _UaBrowserPattern('fxios/', 'Firefox iOS', 'FxiOS/([\\d.]+)', false),
    _UaBrowserPattern('firefox/', 'Firefox', 'Firefox/([\\d.]+)', false),
    _UaBrowserPattern('chrome/', 'Chrome', 'Chrome/([\\d.]+)', false),
    _UaBrowserPattern('safari/', 'Safari', 'Version/([\\d.]+)', false),
  ];

  static const Map<String, _UaRange> validVersionRanges = {
    'Chrome': _UaRange(70, 140),
    'Chrome iOS': _UaRange(70, 140),
    'Chromium': _UaRange(70, 140),
    'Firefox': _UaRange(70, 140),
    'Firefox iOS': _UaRange(70, 140),
    'Safari': _UaRange(12, 19),
    'Edge': _UaRange(80, 140),
    'Edge Android': _UaRange(80, 140),
    'Edge iOS': _UaRange(80, 140),
    'Opera': _UaRange(60, 115),
    'Brave': _UaRange(1, 2),
    'Vivaldi': _UaRange(5, 7),
    'Samsung Browser': _UaRange(18, 27),
    'UC Browser': _UaRange(13, 16),
    'Yandex Browser': _UaRange(23, 25),
  };

  static const Map<String, _UaRange> validWebViewRanges = {
    'Facebook iOS': _UaRange(400, 500),
    'Facebook Android': _UaRange(400, 500),
    'Instagram': _UaRange(280, 350),
    'Twitter iOS': _UaRange(9, 12),
    'Twitter Android': _UaRange(9, 12),
    'TikTok': _UaRange(28, 40),
    'WhatsApp': _UaRange(2, 3),
    'WeChat': _UaRange(8, 9),
    'Telegram iOS': _UaRange(9, 12),
    'Telegram Android': _UaRange(9, 12),
    'Discord': _UaRange(200, 250),
    'Slack': _UaRange(23, 26),
    'Snapchat': _UaRange(12, 14),
    'Line': _UaRange(13, 16),
  };

  static _UaValidationResult validate(String userAgent) {
    final parsed = parse(userAgent);
    final score = _calculateScore(parsed);
    final isValid = parsed.isValid && score.score >= 50;
    return _UaValidationResult(
      isValid: isValid,
      parsed: parsed,
      score: score.score,
      summary: score.summary,
    );
  }

  static _UaParsedUserAgent parse(String userAgent) {
    final ua = userAgent.trim();
    final issues = <_UaValidationIssue>[];

    if (ua.isEmpty) {
      return _UaParsedUserAgent(
        raw: ua,
        browser: null,
        platform: null,
        device: null,
        engine: null,
        webView: null,
        isBot: false,
        botName: null,
        isValid: false,
        issues: [
          const _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message: 'Empty user agent',
            field: null,
          ),
        ],
        confidence: 0,
      );
    }

    if (!ua.startsWith('Mozilla/') &&
        !_isKnownBot(ua) &&
        !_isKnownWebView(ua)) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Non-standard format: does not start with Mozilla/',
          field: 'format',
        ),
      );
    }

    final bot = _detectBot(ua);
    final browser = _parseBrowser(ua);
    if (browser == null && !bot.isBot) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Could not identify browser',
          field: 'browser',
        ),
      );
    }

    _UaWebViewInfo? webView;
    if (browser != null && browser.isWebView) {
      webView = _parseWebView(ua, browser.name);
    }

    if (browser != null && browser.majorVersion != null) {
      final major = browser.majorVersion!;
      if (browser.isWebView) {
        final range = validWebViewRanges[browser.name];
        if (range != null && !range.contains(major)) {
          issues.add(
            _UaValidationIssue(
              severity: major < range.min
                  ? _UaIssueSeverity.warning
                  : _UaIssueSeverity.info,
              message:
                  '${browser.name} version $major is outside expected range ${range.min}-${range.max}',
              field: 'browserVersion',
            ),
          );
        }
      } else {
        final range = validVersionRanges[browser.name];
        if (range != null && !range.contains(major)) {
          issues.add(
            _UaValidationIssue(
              severity: major < range.min
                  ? _UaIssueSeverity.warning
                  : _UaIssueSeverity.info,
              message:
                  '${browser.name} version $major is outside expected range ${range.min}-${range.max}',
              field: 'browserVersion',
            ),
          );
        }
      }
    }

    final platform = _parsePlatform(ua);
    if (platform == null && !bot.isBot) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Could not identify platform/OS',
          field: 'platform',
        ),
      );
    }

    final device = _parseDevice(
      ua,
      isBot: bot.isBot,
      isWebView: browser?.isWebView ?? false,
    );
    final engine = _parseEngine(ua);
    issues.addAll(
      _validateCombinations(browser, platform, engine, webView, ua),
    );
    issues.addAll(_checkSuspiciousPatterns(ua));

    final confidence = _calculateConfidence(
      browser,
      platform,
      engine,
      webView,
      issues,
      bot.isBot,
    );
    final hasErrors = issues.any(
      (issue) => issue.severity == _UaIssueSeverity.error,
    );
    final isValid =
        !hasErrors && (browser != null || bot.isBot) && confidence > 0.3;

    return _UaParsedUserAgent(
      raw: ua,
      browser: browser,
      platform: platform,
      device: device,
      engine: engine,
      webView: webView,
      isBot: bot.isBot,
      botName: bot.name,
      isValid: isValid,
      issues: issues,
      confidence: confidence,
    );
  }

  static bool _isKnownWebView(String ua) {
    final lower = ua.toLowerCase();
    const indicators = [
      '[fban/',
      '[fb_iab/',
      'instagram',
      'twitter for',
      'bytedancewebview',
      'trill/',
      '[linkedinapp]',
      'snapchat/',
      '[pinterest',
      'whatsapp/',
      'telegram-ios',
      'telegramandroid',
      'discord/',
      'slack/',
      'micromessenger/',
      'line/',
    ];
    return indicators.any(lower.contains);
  }

  static bool _isKnownBot(String ua) => _detectBot(ua).isBot;

  static _UaBotResult _detectBot(String ua) {
    final lower = ua.toLowerCase();
    if (_isKnownWebView(ua)) {
      return const _UaBotResult(false, null);
    }
    for (final pattern in botPatterns) {
      if (lower.contains(pattern.pattern)) {
        return _UaBotResult(true, pattern.name);
      }
    }
    return const _UaBotResult(false, null);
  }

  static _UaBrowserInfo? _parseBrowser(String ua) {
    final lower = ua.toLowerCase();
    for (final pattern in browserPatterns) {
      if (lower.contains(pattern.pattern)) {
        final version = _extractVersion(ua, pattern.versionPattern);
        final major = version != null
            ? int.tryParse(version.split('.').first)
            : null;
        return _UaBrowserInfo(
          name: pattern.name,
          version: version ?? 'unknown',
          majorVersion: major,
          isWebView: pattern.isWebView,
        );
      }
    }
    return null;
  }

  static _UaWebViewInfo? _parseWebView(String ua, String appName) {
    final base = appName.replaceAll(' iOS', '').replaceAll(' Android', '');
    String? appVersion;
    String? buildId;
    final additional = <String, String>{};

    const patterns = [
      _UaWebViewPattern('Facebook', [
        _UaKeyPattern('appVersion', 'FBAV/([\\d.]+)'),
        _UaKeyPattern('buildId', 'FBBV/([\\d]+)'),
        _UaKeyPattern('device', 'FBDV/([^;\\]]+)'),
        _UaKeyPattern('osVersion', 'FBSV/([\\d.]+)'),
        _UaKeyPattern('locale', 'FBLC/([^;\\]]+)'),
      ]),
      _UaWebViewPattern('Instagram', [
        _UaKeyPattern('appVersion', 'Instagram ([\\d.]+)'),
        _UaKeyPattern('scale', 'scale=([\\d.]+)'),
        _UaKeyPattern('resolution', '(\\d+x\\d+)'),
      ]),
      _UaWebViewPattern('TikTok', [
        _UaKeyPattern('appVersion', '(?:musical_ly[_/]|trill/)([\\d.]+)'),
        _UaKeyPattern('channel', 'Channel/([^\\s]+)'),
        _UaKeyPattern('region', 'Region/([A-Z]+)'),
        _UaKeyPattern('locale', 'ByteLocale/([a-z]+)'),
      ]),
      _UaWebViewPattern('WhatsApp', [
        _UaKeyPattern('appVersion', 'WhatsApp/([\\d.]+)'),
        _UaKeyPattern('platform', 'WhatsApp/[\\d.]+ ([wa])'),
      ]),
      _UaWebViewPattern('WeChat', [
        _UaKeyPattern('appVersion', 'MicroMessenger/([\\d.]+)'),
        _UaKeyPattern('netType', 'NetType/([^\\s]+)'),
        _UaKeyPattern('language', 'Language/([a-z]+)'),
      ]),
      _UaWebViewPattern('Telegram', [
        _UaKeyPattern('appVersion', 'Telegram(?:-iOS|Android)/([\\d.]+)'),
      ]),
      _UaWebViewPattern('Discord', [
        _UaKeyPattern('appVersion', 'discord/([\\d.]+)'),
        _UaKeyPattern('electronVersion', 'Electron/([\\d.]+)'),
      ]),
      _UaWebViewPattern('Slack', [
        _UaKeyPattern('appVersion', 'Slack/([\\d.]+)'),
        _UaKeyPattern('electronVersion', 'Electron/([\\d.]+)'),
      ]),
    ];

    for (final pattern in patterns) {
      if (base.contains(pattern.app) || pattern.app.contains(base)) {
        for (final pair in pattern.patterns) {
          final value = _extractVersion(ua, pair.regex);
          if (value == null) continue;
          switch (pair.key) {
            case 'appVersion':
              appVersion = value;
              break;
            case 'buildId':
              buildId = value;
              break;
            default:
              additional[pair.key] = value;
          }
        }
        break;
      }
    }

    if (base.contains('Facebook')) {
      appVersion ??= _extractVersion(ua, 'FBAV/([\\d.]+)');
      buildId ??= _extractVersion(ua, 'FBBV/([\\d]+)');
      additional['device'] ??= _extractVersion(ua, 'FBDV/([^;\\]]+)') ?? '';
      additional['osVersion'] ??= _extractVersion(ua, 'FBSV/([\\d.]+)') ?? '';
      additional['locale'] ??= _extractVersion(ua, 'FBLC/([^;\\]]+)') ?? '';
    }

    if (appVersion == null && buildId == null && additional.isEmpty) {
      return null;
    }
    additional.removeWhere((key, value) => value.isEmpty);
    return _UaWebViewInfo(
      app: base,
      appVersion: appVersion,
      buildId: buildId,
      additionalInfo: additional,
    );
  }

  static _UaPlatformInfo? _parsePlatform(String ua) {
    final lower = ua.toLowerCase();
    if (lower.contains('macintosh') || lower.contains('mac os x')) {
      final version = _extractVersion(
        ua,
        'Mac OS X ([\\d_\\.]+)',
      )?.replaceAll('_', '.');
      final arch = ua.contains('Intel') ? 'x86_64' : 'arm64';
      return _UaPlatformInfo(
        name: 'macOS',
        version: version,
        architecture: arch,
      );
    }
    if (lower.contains('iphone') ||
        lower.contains('ipad') ||
        lower.contains('ipod')) {
      final version = _extractVersion(
        ua,
        '(?:CPU (?:iPhone )?OS |FBSV/)([\\d_\\.]+)',
      )?.replaceAll('_', '.');
      return _UaPlatformInfo(
        name: 'iOS',
        version: version,
        architecture: 'arm64',
      );
    }
    if (lower.contains('android')) {
      final version = _extractVersion(ua, 'Android ([\\d\\.]+)');
      return _UaPlatformInfo(
        name: 'Android',
        version: version,
        architecture: null,
      );
    }
    if (lower.contains('windows')) {
      String? version;
      if (lower.contains('windows nt 10')) {
        version = '10/11';
      } else if (lower.contains('windows nt 6.3')) {
        version = '8.1';
      } else if (lower.contains('windows nt 6.2')) {
        version = '8';
      } else if (lower.contains('windows nt 6.1')) {
        version = '7';
      }
      final arch = lower.contains('win64') || lower.contains('x64')
          ? 'x86_64'
          : 'x86';
      return _UaPlatformInfo(
        name: 'Windows',
        version: version,
        architecture: arch,
      );
    }
    if (lower.contains('linux') && !lower.contains('android')) {
      final arch = lower.contains('x86_64')
          ? 'x86_64'
          : (lower.contains('aarch64') ? 'arm64' : null);
      return _UaPlatformInfo(name: 'Linux', version: null, architecture: arch);
    }
    if (lower.contains('cros')) {
      return _UaPlatformInfo(
        name: 'Chrome OS',
        version: null,
        architecture: null,
      );
    }
    return null;
  }

  static _UaDeviceInfo? _parseDevice(
    String ua, {
    required bool isBot,
    required bool isWebView,
  }) {
    if (isBot) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.bot,
        model: null,
        vendor: null,
      );
    }
    final lower = ua.toLowerCase();
    if (lower.contains('iphone')) {
      final model = _extractVersion(ua, 'FBDV/([^;\\]]+)') ?? 'iPhone';
      return _UaDeviceInfo(
        type: _UaDeviceType.mobile,
        model: model,
        vendor: 'Apple',
      );
    }
    if (lower.contains('ipad')) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.tablet,
        model: 'iPad',
        vendor: 'Apple',
      );
    }
    if (lower.contains('android')) {
      String? model;
      String? vendor;
      final extracted = _extractVersion(ua, 'Android[^;]*;\\s*([^)]+)');
      if (extracted != null) {
        final cleaned = extracted.split(' Build').first.trim();
        model = cleaned;
        vendor = _detectVendor(cleaned);
      }
      final isTablet =
          lower.contains('tablet') ||
          (lower.contains('android') && !lower.contains('mobile'));
      return _UaDeviceInfo(
        type: isTablet ? _UaDeviceType.tablet : _UaDeviceType.mobile,
        model: model,
        vendor: vendor,
      );
    }
    if (lower.contains('smart-tv') ||
        lower.contains('smarttv') ||
        lower.contains('webos') ||
        lower.contains('tizen')) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.tv,
        model: null,
        vendor: null,
      );
    }
    if (lower.contains('windows') ||
        lower.contains('macintosh') ||
        (lower.contains('linux') && !lower.contains('android'))) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.desktop,
        model: null,
        vendor: null,
      );
    }
    if (isWebView) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.mobile,
        model: null,
        vendor: null,
      );
    }
    return const _UaDeviceInfo(
      type: _UaDeviceType.unknown,
      model: null,
      vendor: null,
    );
  }

  static String? _detectVendor(String model) {
    final lower = model.toLowerCase();
    if (lower.startsWith('sm-') || lower.contains('samsung')) return 'Samsung';
    if (lower.startsWith('pixel')) return 'Google';
    if (lower.contains('oneplus') || lower.startsWith('cph')) return 'OnePlus';
    if (lower.contains('xiaomi') ||
        (lower.startsWith('m') && lower.contains('pro'))) {
      return 'Xiaomi';
    }
    if (lower.contains('huawei') || lower.startsWith('aln-')) return 'Huawei';
    if (lower.contains('oppo')) return 'Oppo';
    if (lower.contains('vivo')) return 'Vivo';
    if (lower.contains('lg')) return 'LG';
    if (lower.contains('sony')) return 'Sony';
    if (lower.contains('nokia')) return 'Nokia';
    if (lower.contains('motorola') || lower.startsWith('moto')) {
      return 'Motorola';
    }
    return null;
  }

  static _UaEngineInfo? _parseEngine(String ua) {
    final lower = ua.toLowerCase();
    if (lower.contains('gecko/') &&
        lower.contains('firefox') &&
        !lower.contains('like gecko')) {
      final version = _extractVersion(ua, 'rv:([\\d\\.]+)');
      return _UaEngineInfo(name: 'Gecko', version: version);
    }
    if (lower.contains('applewebkit/')) {
      final version = _extractVersion(ua, 'AppleWebKit/([\\d\\.]+)');
      return _UaEngineInfo(name: 'WebKit', version: version);
    }
    if (lower.contains('trident/')) {
      final version = _extractVersion(ua, 'Trident/([\\d\\.]+)');
      return _UaEngineInfo(name: 'Trident', version: version);
    }
    if (lower.contains('presto/')) {
      final version = _extractVersion(ua, 'Presto/([\\d\\.]+)');
      return _UaEngineInfo(name: 'Presto', version: version);
    }
    return null;
  }

  static String? _extractVersion(String ua, String pattern) {
    final regex = RegExp(pattern, caseSensitive: false);
    final match = regex.firstMatch(ua);
    if (match == null || match.groupCount < 1) {
      return null;
    }
    return match.group(1);
  }

  static List<_UaValidationIssue> _validateCombinations(
    _UaBrowserInfo? browser,
    _UaPlatformInfo? platform,
    _UaEngineInfo? engine,
    _UaWebViewInfo? webView,
    String ua,
  ) {
    final issues = <_UaValidationIssue>[];
    if (browser == null) {
      return issues;
    }
    if (browser.isWebView) {
      const mobileOnly = [
        'Facebook iOS',
        'Facebook Android',
        'Instagram',
        'Twitter iOS',
        'Twitter Android',
        'TikTok',
        'Snapchat',
        'WhatsApp',
        'WeChat',
        'Line',
        'LinkedIn',
        'Pinterest',
        'Telegram iOS',
        'Telegram Android',
      ];
      if (mobileOnly.contains(browser.name) &&
          platform != null &&
          platform.name != 'iOS' &&
          platform.name != 'Android') {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message: '${browser.name} WebView is only available on iOS/Android',
            field: 'browser-platform',
          ),
        );
      }
      if (browser.name.contains('iOS') &&
          platform != null &&
          platform.name != 'iOS') {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message:
                '${browser.name} indicates iOS but platform is ${platform.name}',
            field: 'browser-platform',
          ),
        );
      }
      if (browser.name.contains('Android') &&
          platform != null &&
          platform.name != 'Android') {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message:
                '${browser.name} indicates Android but platform is ${platform.name}',
            field: 'browser-platform',
          ),
        );
      }
      return issues;
    }
    if (platform == null) {
      return issues;
    }
    if (browser.name == 'Safari' &&
        platform.name != 'macOS' &&
        platform.name != 'iOS') {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Safari is only available on macOS and iOS',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Chromium' && platform.name == 'iOS') {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Chromium is not available on iOS',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Edge iOS' && platform.name != 'iOS') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Edge iOS identifier found but platform is ${platform.name}',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Edge Android' && platform.name != 'Android') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message:
              'Edge Android identifier found but platform is ${platform.name}',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Firefox' &&
        platform.name != 'iOS' &&
        engine != null &&
        engine.name != 'Gecko') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Firefox should use Gecko engine',
          field: 'browser-engine',
        ),
      );
    }
    const blinkBrowsers = [
      'Chrome',
      'Edge',
      'Chromium',
      'Brave',
      'Opera',
      'Vivaldi',
    ];
    if (blinkBrowsers.contains(browser.name) &&
        platform.name != 'iOS' &&
        engine != null &&
        engine.name != 'WebKit') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: '${browser.name} should use WebKit/Blink engine',
          field: 'browser-engine',
        ),
      );
    }
    if (platform.name == 'iOS' && engine != null && engine.name != 'WebKit') {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'All iOS browsers must use WebKit engine',
          field: 'engine',
        ),
      );
    }
    return issues;
  }

  static List<_UaValidationIssue> _checkSuspiciousPatterns(String ua) {
    final issues = <_UaValidationIssue>[];
    if (ua.length < 20) {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'User agent is suspiciously short (${ua.length} characters)',
          field: 'length',
        ),
      );
    }
    if (ua.length > 600 && !_isKnownWebView(ua)) {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'User agent is unusually long (${ua.length} characters)',
          field: 'length',
        ),
      );
    }
    final openParens = ua.split('(').length - 1;
    final closeParens = ua.split(')').length - 1;
    if (openParens != closeParens) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Mismatched parentheses',
          field: 'format',
        ),
      );
    }
    final openBrackets = ua.split('[').length - 1;
    final closeBrackets = ua.split(']').length - 1;
    if (openBrackets != closeBrackets) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Mismatched square brackets',
          field: 'format',
        ),
      );
    }
    if (ua.contains('\u0000') || ua.contains('\n') || ua.contains('\r')) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Contains invalid characters (null bytes or newlines)',
          field: 'format',
        ),
      );
    }
    const fakePatterns = [
      'fake',
      'test',
      'example',
      'dummy',
      'xxx',
      'asdf',
      'qwerty',
    ];
    final lower = ua.toLowerCase();
    for (final pattern in fakePatterns) {
      if (lower.contains(pattern)) {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.warning,
            message: "Contains suspicious pattern: '$pattern'",
            field: 'content',
          ),
        );
        break;
      }
    }
    return issues;
  }

  static double _calculateConfidence(
    _UaBrowserInfo? browser,
    _UaPlatformInfo? platform,
    _UaEngineInfo? engine,
    _UaWebViewInfo? webView,
    List<_UaValidationIssue> issues,
    bool isBot,
  ) {
    var confidence = 0.5;
    if (isBot) return 0.7;
    if (browser != null) {
      confidence += 0.15;
      if (browser.majorVersion != null) {
        confidence += 0.1;
      }
      if (browser.isWebView && webView != null) {
        confidence += 0.1;
      }
    }
    if (platform != null) {
      confidence += 0.12;
      if (platform.version != null) {
        confidence += 0.05;
      }
    }
    if (engine != null) {
      confidence += 0.08;
    }
    if (webView != null) {
      if (webView.appVersion != null) confidence += 0.05;
      if (webView.buildId != null) confidence += 0.03;
      if (webView.additionalInfo.isNotEmpty) confidence += 0.02;
    }
    for (final issue in issues) {
      switch (issue.severity) {
        case _UaIssueSeverity.error:
          confidence -= 0.2;
          break;
        case _UaIssueSeverity.warning:
          confidence -= 0.08;
          break;
        case _UaIssueSeverity.info:
          confidence -= 0.02;
          break;
      }
    }
    return confidence.clamp(0.0, 1.0);
  }

  static _UaScore _calculateScore(_UaParsedUserAgent parsed) {
    var score = 50;
    final notes = <String>[];
    if (parsed.isBot) {
      notes.add('Bot: ${parsed.botName ?? "unknown"}');
      return _UaScore(60, notes.join(' | '));
    }
    if (parsed.browser != null) {
      final browser = parsed.browser!;
      score += 15;
      notes.add(
        '${browser.isWebView ? "WebView" : "Browser"}: ${browser.name} ${browser.version}',
      );
      if (browser.majorVersion != null) {
        if (browser.isWebView) {
          final range = validWebViewRanges[browser.name];
          if (range != null) {
            if (range.contains(browser.majorVersion!)) {
              score += 10;
            } else if (browser.majorVersion! < range.min) {
              score -= 10;
              notes.add('Outdated app version');
            }
          }
        } else {
          final range = validVersionRanges[browser.name];
          if (range != null) {
            if (range.contains(browser.majorVersion!)) {
              score += 10;
            } else if (browser.majorVersion! < range.min) {
              score -= 10;
              notes.add('Outdated browser version');
            }
          }
        }
      }
    } else {
      score -= 20;
      notes.add('Unknown browser');
    }
    if (parsed.platform != null) {
      score += 10;
      notes.add(
        'Platform: ${parsed.platform!.name}${parsed.platform!.version != null ? " ${parsed.platform!.version}" : ""}',
      );
    } else {
      score -= 15;
      notes.add('Unknown platform');
    }
    if (parsed.device != null) {
      score += 5;
    }
    if (parsed.engine != null) {
      score += 5;
    }
    if (parsed.webView != null) {
      score += 5;
      if (parsed.webView!.buildId != null) {
        score += 3;
      }
    }
    for (final issue in parsed.issues) {
      switch (issue.severity) {
        case _UaIssueSeverity.error:
          score -= 15;
          break;
        case _UaIssueSeverity.warning:
          score -= 5;
          break;
        case _UaIssueSeverity.info:
          score -= 1;
          break;
      }
    }
    score += (parsed.confidence * 10).round();
    score = score.clamp(0, 100).toInt();
    final summary = notes.isEmpty ? 'Valid user agent' : notes.join(' | ');
    return _UaScore(score, summary);
  }
}

class _UaScore {
  const _UaScore(this.score, this.summary);
  final int score;
  final String summary;
}

class _UaBotPattern {
  const _UaBotPattern(this.pattern, this.name);
  final String pattern;
  final String name;
}

class _UaBrowserPattern {
  const _UaBrowserPattern(
    this.pattern,
    this.name,
    this.versionPattern,
    this.isWebView,
  );
  final String pattern;
  final String name;
  final String versionPattern;
  final bool isWebView;
}

class _UaBotResult {
  const _UaBotResult(this.isBot, this.name);
  final bool isBot;
  final String? name;
}

class _UaWebViewPattern {
  const _UaWebViewPattern(this.app, this.patterns);
  final String app;
  final List<_UaKeyPattern> patterns;
}

class _UaKeyPattern {
  const _UaKeyPattern(this.key, this.regex);
  final String key;
  final String regex;
}

Widget buildUserAgentTool() {
  return const _UserAgentToolView();
}
