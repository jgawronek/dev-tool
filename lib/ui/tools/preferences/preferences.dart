/// Preferences tool views.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/app_appearance_service.dart';
import '../../../state/tool_state_scope.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

Widget buildPreferences() {
  return const _PreferencesView();
}

Widget buildPreferencesGeneral() {
  return const _PreferencesGeneralView();
}

Widget buildPreferencesAppearance() {
  return const _PreferencesAppearanceView();
}

Widget buildPreferencesScripting() {
  return const _PreferencesScriptingView();
}

class _PrefCheckbox extends StatelessWidget {
  const _PrefCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: onChanged),
          Expanded(child: Text(label, softWrap: true)),
        ],
      ),
    );
  }
}

class _PreferencesView extends StatefulWidget {
  const _PreferencesView();

  @override
  State<_PreferencesView> createState() => _PreferencesViewState();
}

class _PreferencesViewState extends State<_PreferencesView> {
  static const _tabs = ['General', 'Appearance', 'Scripting'];

  String _selectedTab = _tabs.first;
  bool _hideOnLaunch = false;
  bool _confirmQuit = false;
  bool _shareAnalytics = false;
  bool _writeLogs = false;
  bool _showStatusBar = true;
  bool _showDock = true;
  String _theme = 'System';
  String _colorTheme = 'Classic Blue';
  int _scriptSegment = 0;
  String _phpPath = 'No Usable PHP Runtime';
  final TextEditingController _whitelist = TextEditingController(
    text: 'serialize,var_export,json_encode,json_decode,unserialize',
  );
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hideOnLaunch = prefs.getBool('pref_hide_on_launch') ?? false;
      _confirmQuit = prefs.getBool('pref_confirm_quit') ?? false;
      _shareAnalytics = prefs.getBool('pref_share_analytics') ?? false;
      _writeLogs = prefs.getBool('pref_write_logs') ?? false;
      _showStatusBar = prefs.getBool('pref_show_status_bar') ?? true;
      _showDock = prefs.getBool('pref_show_dock') ?? true;
      _theme = prefs.getString('pref_theme') ?? 'System';
      _colorTheme = prefs.getString('colorTheme') ?? 'Classic Blue';
      _scriptSegment = prefs.getInt('pref_script_segment') ?? 0;
      _phpPath = prefs.getString('pref_php_path') ?? 'No Usable PHP Runtime';
      _whitelist.text =
          prefs.getString('pref_php_whitelist') ??
          'serialize,var_export,json_encode,json_decode,unserialize';
      _loaded = true;
    });
  }

  Future<void> _setPref(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  void _applyAppearance() {
    AppAppearanceService.apply(
      showStatusBar: _showStatusBar,
      showDock: _showDock,
    );
  }

  @override
  void dispose() {
    _whitelist.dispose();
    super.dispose();
  }

  Widget _buildGeneral() {
    return _PreferenceSection(
      title: 'General',
      children: [
        _PrefCheckbox(
          label: 'Hide the main window at launch',
          value: _hideOnLaunch,
          onChanged: (value) {
            setState(() => _hideOnLaunch = value ?? false);
            _setPref('pref_hide_on_launch', _hideOnLaunch);
          },
        ),
        _PrefCheckbox(
          label: 'Confirm before quitting with Cmd+Q',
          value: _confirmQuit,
          onChanged: (value) {
            setState(() => _confirmQuit = value ?? false);
            _setPref('pref_confirm_quit', _confirmQuit);
          },
        ),
        _PrefCheckbox(
          label: 'Share anonymous crash reports and analytics',
          value: _shareAnalytics,
          onChanged: (value) {
            setState(() => _shareAnalytics = value ?? false);
            _setPref('pref_share_analytics', _shareAnalytics);
          },
        ),
        _PrefCheckbox(
          label: 'Write debug logs',
          value: _writeLogs,
          onChanged: (value) {
            setState(() => _writeLogs = value ?? false);
            _setPref('pref_write_logs', _writeLogs);
          },
        ),
      ],
    );
  }

  Widget _buildAppearance() {
    final state = ToolStateScope.maybeOf(context);
    Widget colorThemePicker(String selectedTheme) {
      return _ColorThemePicker(
        selectedTheme: selectedTheme,
        onChanged: (value) {
          setState(() => _colorTheme = value);
          state?.colorTheme.value = value;
          _setPref('colorTheme', value);
        },
      );
    }

    return _PreferenceSection(
      title: 'Appearance',
      children: [
        _PrefCheckbox(
          label: 'Show status bar icon',
          value: _showStatusBar,
          // When the Dock icon is hidden the app is menu-bar-only, so the
          // status bar icon must stay on; the box is locked on in that case.
          onChanged: _showDock
              ? (value) {
                  setState(() => _showStatusBar = value ?? true);
                  _setPref('pref_show_status_bar', _showStatusBar);
                  _applyAppearance();
                }
              : null,
        ),
        _PrefCheckbox(
          label: 'Show Dock icon',
          value: _showDock,
          onChanged: (value) {
            final next = value ?? true;
            setState(() {
              _showDock = next;
              if (!next) _showStatusBar = true;
            });
            _setPref('pref_show_dock', _showDock);
            if (!next) _setPref('pref_show_status_bar', true);
            _applyAppearance();
          },
        ),
        const SizedBox(height: 8),
        _PreferenceSelectRow(
          label: 'Mode',
          child: SmallDropdown(
            items: const ['System', 'Light', 'Dark'],
            initialValue: _theme,
            onChanged: (value) {
              setState(() => _theme = value);
              _setPref('pref_theme', _theme);
              if (value == 'Light') state?.darkMode.value = false;
              if (value == 'Dark') state?.darkMode.value = true;
            },
          ),
        ),
        const SizedBox(height: 14),
        if (state == null)
          colorThemePicker(_colorTheme)
        else
          ValueListenableBuilder<String>(
            valueListenable: state.colorTheme,
            builder: (context, selectedTheme, _) {
              return colorThemePicker(selectedTheme);
            },
          ),
      ],
    );
  }

  Widget _buildScripting() {
    return _PreferenceSection(
      title: 'Scripting',
      children: [
        ToggleButtons(
          isSelected: List<bool>.generate(3, (i) => i == _scriptSegment),
          onPressed: (index) {
            setState(() => _scriptSegment = index);
            _setPref('pref_script_segment', _scriptSegment);
          },
          borderRadius: BorderRadius.circular(6),
          constraints: const BoxConstraints(minHeight: 32, minWidth: 86),
          children: const [Text('PHP'), Text('OpenSSL'), Text('Other')],
        ),
        const SizedBox(height: 16),
        _PreferenceReadonlyField(label: 'Runtime', value: _phpPath),
        const SizedBox(height: 14),
        Text(
          'Allowed PHP functions',
          style: TextStyle(
            color: context.appColors.editorText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 116,
          decoration: toolSurfaceDecoration(context),
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _whitelist,
            maxLines: null,
            expands: true,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'serialize,var_export,json_encode,json_decode',
              hintStyle: TextStyle(color: context.appColors.mutedText),
            ),
            style: TextStyle(color: context.appColors.editorText),
            onChanged: (value) => _setPref('pref_php_whitelist', value),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final body = switch (_selectedTab) {
      'Appearance' => _buildAppearance(),
      'Scripting' => _buildScripting(),
      _ => _buildGeneral(),
    };

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ToggleButtons(
              isSelected: _tabs.map((tab) => tab == _selectedTab).toList(),
              onPressed: (index) => setState(() => _selectedTab = _tabs[index]),
              borderRadius: BorderRadius.circular(6),
              constraints: const BoxConstraints(minHeight: 34, minWidth: 112),
              children: _tabs.map(Text.new).toList(),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.appColors.editorText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _PreferenceSelectRow extends StatelessWidget {
  const _PreferenceSelectRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 36),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ColorThemePicker extends StatelessWidget {
  const _ColorThemePicker({
    required this.selectedTheme,
    required this.onChanged,
  });

  final String selectedTheme;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreferenceSelectRow(
          label: 'Color theme',
          child: SmallDropdown(
            items: AppColors.colorThemeNames,
            initialValue: selectedTheme,
            width: 170,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 146),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final theme in AppColors.colorThemes)
                _ColorThemeSwatchButton(
                  theme: theme,
                  selected: theme.name == selectedTheme,
                  onTap: () => onChanged(theme.name),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 146),
          child: Text(
            'Applies to accents, selection, hover states, and focused controls.',
            style: TextStyle(color: appColors.mutedText, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ColorThemeSwatchButton extends StatelessWidget {
  const _ColorThemeSwatchButton({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AppColorThemeChoice theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Semantics(
      button: true,
      selected: selected,
      label: theme.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 122,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? appColors.selected : appColors.panelElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? appColors.accent : appColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              _ThemeDot(color: theme.darkAccent),
              const SizedBox(width: 4),
              _ThemeDot(color: theme.lightAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  theme.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: appColors.editorText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _ThemeDot extends StatelessWidget {
  const _ThemeDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.appColors.border),
      ),
    );
  }
}

class _PreferenceReadonlyField extends StatelessWidget {
  const _PreferenceReadonlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: Container(
            decoration: toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              value,
              style: TextStyle(
                color: context.appColors.editorText,
                fontFamily: 'Menlo',
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreferencesGeneralView extends StatefulWidget {
  const _PreferencesGeneralView();

  @override
  State<_PreferencesGeneralView> createState() =>
      _PreferencesGeneralViewState();
}

class _PreferencesGeneralViewState extends State<_PreferencesGeneralView> {
  bool _hideOnLaunch = false;
  bool _confirmQuit = false;
  bool _shareAnalytics = false;
  bool _writeLogs = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hideOnLaunch = prefs.getBool('pref_hide_on_launch') ?? false;
        _confirmQuit = prefs.getBool('pref_confirm_quit') ?? false;
        _shareAnalytics = prefs.getBool('pref_share_analytics') ?? false;
        _writeLogs = prefs.getBool('pref_write_logs') ?? false;
        _loaded = true;
      });
    });
  }

  Future<void> _setPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _PreferencesShell(
      selectedLabel: 'General',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PrefCheckbox(
            label: 'Always hide the main window at launch',
            value: _hideOnLaunch,
            onChanged: (value) {
              setState(() => _hideOnLaunch = value ?? false);
              _setPref('pref_hide_on_launch', _hideOnLaunch);
            },
          ),
          _PrefCheckbox(
            label: 'Ask to confirm when quitting with Cmd+Q',
            value: _confirmQuit,
            onChanged: (value) {
              setState(() => _confirmQuit = value ?? false);
              _setPref('pref_confirm_quit', _confirmQuit);
            },
          ),
          _PrefCheckbox(
            label: 'Share anonymous crash reports and analytics',
            value: _shareAnalytics,
            onChanged: (value) {
              setState(() => _shareAnalytics = value ?? false);
              _setPref('pref_share_analytics', _shareAnalytics);
            },
          ),
          Row(
            children: [
              Expanded(
                child: _PrefCheckbox(
                  label: 'Write debug logs',
                  value: _writeLogs,
                  onChanged: (value) {
                    setState(() => _writeLogs = value ?? false);
                    _setPref('pref_write_logs', _writeLogs);
                  },
                ),
              ),
              const ToolButton(label: 'Open logs directory'),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Text('Stored preferences location'),
              SizedBox(width: 8),
              ToolButton(label: 'Open'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreferencesAppearanceView extends StatefulWidget {
  const _PreferencesAppearanceView();

  @override
  State<_PreferencesAppearanceView> createState() =>
      _PreferencesAppearanceViewState();
}

class _PreferencesAppearanceViewState
    extends State<_PreferencesAppearanceView> {
  bool _showStatusBar = true;
  bool _showDock = true;
  String _theme = 'System';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _showStatusBar = prefs.getBool('pref_show_status_bar') ?? true;
        _showDock = prefs.getBool('pref_show_dock') ?? true;
        _theme = prefs.getString('pref_theme') ?? 'System';
        _loaded = true;
      });
    });
  }

  Future<void> _setPref(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _PreferencesShell(
      selectedLabel: 'Appearance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PrefCheckbox(
            label: 'Show Status Bar icon',
            value: _showStatusBar,
            onChanged: (value) {
              setState(() => _showStatusBar = value ?? true);
              _setPref('pref_show_status_bar', _showStatusBar);
            },
          ),
          _PrefCheckbox(
            label: 'Show Dock icon',
            value: _showDock,
            onChanged: (value) {
              setState(() => _showDock = value ?? true);
              _setPref('pref_show_dock', _showDock);
            },
          ),
          Row(
            children: [
              const Text('Theme'),
              const SizedBox(width: 12),
              SmallDropdown(
                items: const ['System', 'Light', 'Dark'],
                initialValue: _theme,
                onChanged: (value) {
                  setState(() => _theme = value);
                  _setPref('pref_theme', _theme);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreferencesScriptingView extends StatefulWidget {
  const _PreferencesScriptingView();

  @override
  State<_PreferencesScriptingView> createState() =>
      _PreferencesScriptingViewState();
}

class _PreferencesScriptingViewState extends State<_PreferencesScriptingView> {
  int _segment = 0;
  String _phpPath = 'No Usable PHP Runtime';
  final TextEditingController _whitelist = TextEditingController(
    text: 'serialize,var_export,json_encode,json_decode,unserialize',
  );
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _segment = prefs.getInt('pref_script_segment') ?? 0;
        _phpPath = prefs.getString('pref_php_path') ?? 'No Usable PHP Runtime';
        _whitelist.text =
            prefs.getString('pref_php_whitelist') ??
            'serialize,var_export,json_encode,json_decode,unserialize';
        _loaded = true;
      });
    });
  }

  Future<void> _setPref(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  void dispose() {
    _whitelist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _PreferencesShell(
      selectedLabel: 'Scripting',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToggleButtons(
            isSelected: List<bool>.generate(3, (i) => i == _segment),
            onPressed: (index) {
              setState(() => _segment = index);
              _setPref('pref_script_segment', _segment);
            },
            borderRadius: BorderRadius.circular(6),
            constraints: const BoxConstraints(minHeight: 32, minWidth: 80),
            children: const [Text('PHP'), Text('Open SSL'), Text('Others')],
          ),
          const SizedBox(height: 16),
          const Text('Default command path:'),
          const SizedBox(height: 8),
          SmallDropdown(
            items: [_phpPath],
            initialValue: _phpPath,
            onChanged: (value) => setState(() => _phpPath = value),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              ToolButton(label: 'Add New Path...'),
              SizedBox(width: 12),
              ToolButton(label: 'Remove'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'PHP code is run in safe mode with only whitelisted functions below allowed.',
          ),
          const SizedBox(height: 8),
          Container(
            height: 100,
            decoration: toolSurfaceDecoration(context),
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _whitelist,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText:
                    'serialize,var_export,json_encode,json_decode,unserialize',
              ),
              style: TextStyle(color: context.appColors.editorText),
              onChanged: (value) => _setPref('pref_php_whitelist', value),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferencesShell extends StatelessWidget {
  const _PreferencesShell({required this.child, required this.selectedLabel});

  final Widget child;
  final String selectedLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PrefTab(label: 'General', selected: selectedLabel == 'General'),
            _PrefTab(label: 'Hotkeys', selected: selectedLabel == 'Hotkeys'),
            _PrefTab(
              label: 'Appearance',
              selected: selectedLabel == 'Appearance',
            ),
            _PrefTab(
              label: 'Integrations',
              selected: selectedLabel == 'Integrations',
            ),
            _PrefTab(
              label: 'Scripting',
              selected: selectedLabel == 'Scripting',
            ),
            _PrefTab(label: 'Updates', selected: selectedLabel == 'Updates'),
            _PrefTab(label: 'License', selected: selectedLabel == 'License'),
          ],
        ),
        const Divider(height: 24),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _PrefTab extends StatelessWidget {
  const _PrefTab({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Icon(
            Icons.settings,
            size: 24,
            color: selected ? appColors.accent : appColors.mutedText,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: selected ? appColors.accent : appColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}
