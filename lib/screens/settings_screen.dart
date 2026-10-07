import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ai_service.dart';
import '../services/shizuku_service.dart';
import '../services/screen_automation_service.dart';
import '../services/telegram_service.dart';
import 'task_history_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../config/feature_flags.dart';

class SettingsScreen extends StatefulWidget {
  final AiService aiService;
  final ShizukuService shizukuService;
  final ScreenAutomationService screenAutomationService;
  final TelegramService telegramService;

  const SettingsScreen({
    super.key,
    required this.aiService,
    required this.shizukuService,
    required this.screenAutomationService,
    required this.telegramService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _telegramTokenController;
  bool _obscureKey = true;
  bool _telegramEnabled = false;
  double _maxSteps = 15;
  bool _disableMaxSteps = false;
  late TextEditingController _maxTokensController;
  double _temperature = 1.0;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  bool _floatingIconEnabled = false;
  bool _isOverlayPermissionGranted = false;
  final Map<String, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiKeyController = TextEditingController(text: widget.aiService.apiKey);
    _baseUrlController = TextEditingController(text: widget.aiService.baseUrl);
    _modelController = TextEditingController(text: widget.aiService.model);
    _telegramTokenController = TextEditingController(text: widget.telegramService.botToken);
    _telegramEnabled = widget.telegramService.isEnabled;
    _maxSteps = widget.aiService.rawMaxSteps.toDouble();
    _disableMaxSteps = widget.aiService.disableMaxSteps;
    _temperature = widget.aiService.temperature;
    _maxTokensController = TextEditingController(text: widget.aiService.maxTokens.toString());
    _useScreenCompression = widget.aiService.useScreenCompression;
    _useSystemPrompt = widget.aiService.useSystemPrompt;
    _apiKeyController.addListener(_autoSave);
    _baseUrlController.addListener(_autoSave);
    _modelController.addListener(_autoSave);
    _telegramTokenController.addListener(_autoSave);
    _maxTokensController.addListener(_autoSave);
    _checkPermissions();
    if (FeatureFlags.floatingOverlayEnabled) _checkOverlayStatus();
  }

  Future<void> _checkOverlayStatus() async {
    bool isActive = await FlutterOverlayWindow.isActive();
    bool isGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) setState(() { _floatingIconEnabled = isActive; _isOverlayPermissionGranted = isGranted; });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiKeyController.removeListener(_autoSave);
    _baseUrlController.removeListener(_autoSave);
    _modelController.removeListener(_autoSave);
    _telegramTokenController.removeListener(_autoSave);
    _maxTokensController.removeListener(_autoSave);
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _telegramTokenController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      if (FeatureFlags.floatingOverlayEnabled) _checkOverlayStatus();
    }
  }

  Future<void> _checkPermissions() async {
    final perms = {
      'Microphone': Permission.microphone,
      'Contacts': Permission.contacts,
      'Phone': Permission.phone,
      'SMS': Permission.sms,
      'Notifications': Permission.notification,
    };
    for (final entry in perms.entries) {
      _permissions[entry.key] = await entry.value.status;
    }
    final overlayGranted = FeatureFlags.floatingOverlayEnabled
        ? await FlutterOverlayWindow.isPermissionGranted()
        : false;
    if (mounted) setState(() => _isOverlayPermissionGranted = overlayGranted);
  }

  Future<void> _requestPermission(String name, Permission permission) async {
    final status = await permission.request();
    setState(() => _permissions[name] = status);
  }

  void _autoSave() {
    widget.aiService.saveSettings(
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
    );
    widget.telegramService.saveSettings(
      botToken: _telegramTokenController.text.trim(),
      isEnabled: _telegramEnabled,
    );
    widget.aiService.saveMaxSteps(_maxSteps.toInt());
    widget.aiService.saveDisableMaxSteps(_disableMaxSteps);
    widget.aiService.saveAdvancedSettings(
      temperature: _temperature,
      maxTokens: int.tryParse(_maxTokensController.text) ?? 1024,
      useScreenCompression: _useScreenCompression,
      useSystemPrompt: _useSystemPrompt,
    );
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter Base URL and API Key first.')));
      return;
    }
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
    final models = await widget.aiService.fetchAvailableModels(baseUrl, apiKey);
    if (mounted) Navigator.pop(context);
    if (models.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No models found or error fetching models.')));
      return;
    }
    if (mounted) {
      final isNvidia = AiService.isNvidiaBaseUrl(baseUrl);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isNvidia ? 'Select a Free NVIDIA Model' : 'Select a Model'),
          content: SizedBox(
            width: double.maxFinite, height: 300,
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (ctx, i) => ListTile(title: Text(models[i]), onTap: () { setState(() => _modelController.text = models[i]); Navigator.pop(ctx); }),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
        ),
      );
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  InputDecoration _dec(String label, String hint, {Widget? pre, Widget? suf}) {
    return InputDecoration(
      labelText: label, hintText: hint, prefixIcon: pre, suffixIcon: suf,
      filled: true, fillColor: const Color(0xFF111111),
      labelStyle: const TextStyle(color: Color(0xFF888888), fontSize: 13),
      hintStyle: const TextStyle(color: Color(0xFF444444), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC8FF00), width: 1.5)),
    );
  }

  Widget _header(String t) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF666666), letterSpacing: 1.4)),
  );

  Widget _tile({required IconData icon, required String title, String? sub, Widget? trail, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: const Color(0xFFC8FF00)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
            if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF888888)))],
          ])),
          // ignore: use_null_aware_elements
          if (trail != null) trail,
        ]),
      ),
    );
  }

  Widget _box(List<Widget> children) => Material(
    color: const Color(0xFF111111),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFF2A2A2A)),
    ),
    child: Column(children: children),
  );

  Widget _div() => const Divider(height: 1, color: Color(0xFF2A2A2A));

  Widget _chip(String label, IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF2A2A2A))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: const Color(0xFFC8FF00)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
      ]),
    ),
  );

  Widget _val(String v) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: const Color(0xFFC8FF00).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
    child: Text(v, style: const TextStyle(color: Color(0xFFC8FF00), fontWeight: FontWeight.bold, fontSize: 13)),
  );

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
        children: [
          _header('AI Model'),
          TextField(controller: _apiKeyController, obscureText: _obscureKey,
            decoration: _dec('API Key', 'sk-...', pre: const Icon(Icons.key_rounded, size: 18),
              suf: IconButton(icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility, size: 18, color: const Color(0xFF888888)), onPressed: () => setState(() => _obscureKey = !_obscureKey)))),
          const SizedBox(height: 10),
          TextField(controller: _baseUrlController, decoration: _dec('API Base URL', 'https://openrouter.ai/api/v1', pre: const Icon(Icons.dns_rounded, size: 18))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _chip('Gemini', Icons.auto_awesome_rounded, () { _baseUrlController.text = 'https://generativelanguage.googleapis.com/v1beta/openai/'; _modelController.text = 'gemini-1.5-pro'; }),
            _chip('OpenRouter', Icons.router_rounded, () { _baseUrlController.text = 'https://openrouter.ai/api/v1'; _modelController.text = 'anthropic/claude-3.5-sonnet'; }),
            _chip('Ollama', Icons.computer_rounded, () { _baseUrlController.text = 'http://10.0.2.2:11434/v1'; _modelController.text = 'llama3'; }),
            _chip('Custom', Icons.edit_rounded, () { _baseUrlController.text = ''; _modelController.text = ''; }),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _modelController, decoration: _dec('Model', 'e.g. gemini-1.5-pro', pre: const Icon(Icons.smart_toy_rounded, size: 18)))),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _fetchModels,
              icon: const Icon(Icons.cloud_download, size: 16, color: Colors.black),
              label: const Text('Fetch', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC8FF00), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ]),

          _header('Agent Settings'),
          _box([
            SwitchListTile(
              title: const Text('Disable Max Steps', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text('May cause infinite loops', style: TextStyle(fontSize: 12, color: Colors.orange)),
              value: _disableMaxSteps, contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              activeThumbColor: const Color(0xFFC8FF00), activeTrackColor: const Color(0x4DC8FF00),
              onChanged: (v) { setState(() => _disableMaxSteps = v); _autoSave(); },
            ),
            if (!_disableMaxSteps) ...[
              _div(),
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Row(children: [const Text('Max Steps', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)), const Spacer(), _val('${_maxSteps.toInt()}')])),
              Slider(value: _maxSteps, min: 5, max: 50, divisions: 45, activeColor: const Color(0xFFC8FF00), onChanged: (v) => setState(() => _maxSteps = v), onChangeEnd: (_) => _autoSave()),
            ],
            _div(),
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Row(children: [const Text('Temperature', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)), const Spacer(), _val(_temperature.toStringAsFixed(2))])),
            Slider(value: _temperature, min: 0.0, max: 2.0, divisions: 20, activeColor: const Color(0xFFC8FF00), onChanged: (v) => setState(() => _temperature = v), onChangeEnd: (_) => _autoSave()),
            const SizedBox(height: 4),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _maxTokensController, keyboardType: TextInputType.number, decoration: _dec('Max Tokens', '1024', pre: const Icon(Icons.token_rounded, size: 18))),

          _header('Behavior'),
          _box([
            SwitchListTile(
              title: const Text('Screen Compression', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text('Removes duplicate elements to save tokens', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
              value: _useScreenCompression, contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              activeThumbColor: const Color(0xFFC8FF00), activeTrackColor: const Color(0x4DC8FF00),
              onChanged: (v) { setState(() => _useScreenCompression = v); _autoSave(); },
            ),
            _div(),
            SwitchListTile(
              title: const Text('System Prompt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text('Turn off for custom fine-tuned models', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
              value: _useSystemPrompt, contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              activeThumbColor: const Color(0xFFC8FF00), activeTrackColor: const Color(0x4DC8FF00),
              onChanged: (v) { setState(() => _useSystemPrompt = v); _autoSave(); },
            ),
            if (FeatureFlags.floatingOverlayEnabled) ...[
              _div(),
              SwitchListTile(
                title: const Text('Floating Agent Icon', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: const Text('Assign tasks without opening the app', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                value: _floatingIconEnabled, contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                activeThumbColor: const Color(0xFFC8FF00), activeTrackColor: const Color(0x4DC8FF00),
                onChanged: (val) async {
                  if (val) {
                    bool? isGranted = await FlutterOverlayWindow.isPermissionGranted();
                    if (isGranted != true) {
                      bool? result = await FlutterOverlayWindow.requestPermission();
                      if (result != true) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission to draw over other apps is required.'))); return; }
                    }
                    if (await FlutterOverlayWindow.isActive() == false) {
                      await FlutterOverlayWindow.showOverlay(enableDrag: true, overlayTitle: 'AgenOS', overlayContent: 'Floating Assistant', flag: OverlayFlag.focusPointer, alignment: OverlayAlignment.centerRight, visibility: NotificationVisibility.visibilitySecret, positionGravity: PositionGravity.auto, startPosition: const OverlayPosition(0, 200), width: 56, height: 56);
                    }
                  } else { if (await FlutterOverlayWindow.isActive() == true) await FlutterOverlayWindow.closeOverlay(); }
                  setState(() => _floatingIconEnabled = val);
                  _autoSave();
                },
              ),
            ],
          ]),

          _header('Permissions'),
          _box(_buildPermissionTiles()),

          _header('Screen Control'),
          _buildAccessibilityCard(),

          _header('Telegram Remote Access'),
          TextField(controller: _telegramTokenController, decoration: _dec('Bot Token', '123456:ABC-DEF...', pre: const Icon(Icons.send_rounded, size: 18))),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Telegram Bot', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text('Remote control via Telegram chat', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
            value: _telegramEnabled,
            activeThumbColor: const Color(0xFFC8FF00), activeTrackColor: const Color(0x4DC8FF00),
            onChanged: (val) { setState(() => _telegramEnabled = val); _autoSave(); },
          ),

          _header('History'),
          _tile(icon: Icons.history_rounded, title: 'Task History', sub: 'View logs and token usage',
            trail: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF888888)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskHistoryScreen()))),

          _header('About'),
          _box([
            _tile(icon: Icons.person_rounded, title: 'Developed by Rimon Dutta', sub: 'Creator & Lead Developer of AgenOS'),
            _div(),
            _tile(icon: Icons.chat_rounded, title: 'WhatsApp Support', sub: '+880 1404-587727', trail: const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF888888)), onTap: () => launchUrl(Uri.parse('https://wa.me/8801404587727'), mode: LaunchMode.externalApplication)),
          ]),
        ],
      ),
    );
  }

  List<Widget> _buildPermissionTiles() {
    final permissionMap = {'Microphone': Permission.microphone, 'Contacts': Permission.contacts, 'Phone': Permission.phone, 'SMS': Permission.sms, 'Notifications': Permission.notification};
    final icons = {'Microphone': Icons.mic, 'Contacts': Icons.contacts, 'Phone': Icons.phone, 'SMS': Icons.sms, 'Notifications': Icons.notifications};
    final list = <Widget>[];
    final entries = permissionMap.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final status = _permissions[entry.key];
      final isGranted = status?.isGranted ?? false;
      list.add(ListTile(
        leading: Icon(icons[entry.key], color: const Color(0xFFC8FF00)),
        title: Text(entry.key, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(isGranted ? 'Allowed' : (status?.isDenied ?? true ? 'Not granted' : 'Denied permanently'), style: TextStyle(color: isGranted ? const Color(0xFFC8FF00) : Colors.orange, fontSize: 12)),
        trailing: isGranted
            ? const Icon(Icons.check_circle_rounded, color: Color(0xFFC8FF00), size: 20)
            : TextButton(onPressed: () => _requestPermission(entry.key, entry.value), child: const Text('Allow', style: TextStyle(color: Color(0xFFC8FF00), fontWeight: FontWeight.bold))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ));
      if (i < entries.length - 1 || FeatureFlags.floatingOverlayEnabled) list.add(_div());
    }
    if (FeatureFlags.floatingOverlayEnabled) {
      list.add(ListTile(
        leading: const Icon(Icons.layers_rounded, color: Color(0xFFC8FF00)),
        title: const Text('Display Over Other Apps', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(_isOverlayPermissionGranted ? 'Allowed' : 'Not granted', style: TextStyle(color: _isOverlayPermissionGranted ? const Color(0xFFC8FF00) : Colors.orange, fontSize: 12)),
        trailing: _isOverlayPermissionGranted
            ? const Icon(Icons.check_circle_rounded, color: Color(0xFFC8FF00), size: 20)
            : TextButton(onPressed: () async { await FlutterOverlayWindow.requestPermission(); final g = await FlutterOverlayWindow.isPermissionGranted(); setState(() => _isOverlayPermissionGranted = g); }, child: const Text('Allow', style: TextStyle(color: Color(0xFFC8FF00), fontWeight: FontWeight.bold))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ));
    }
    return list;
  }

  Widget _buildAccessibilityCard() {
    return FutureBuilder<bool>(
      future: widget.screenAutomationService.isServiceRunning(),
      builder: (context, snapshot) {
        final isRunning = snapshot.data ?? false;
        return Container(
          decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF2A2A2A))),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(isRunning ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: isRunning ? const Color(0xFFC8FF00) : const Color(0xFF888888), size: 20),
              const SizedBox(width: 10),
              Text(isRunning ? 'Screen Control Active' : 'Screen Control Disabled', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isRunning ? const Color(0xFFC8FF00) : const Color(0xFF888888))),
            ]),
            if (!isRunning) ...[
              const SizedBox(height: 10),
              const Text('Open Accessibility Settings and enable "AgenOS Screen Control".', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async => await widget.screenAutomationService.openAccessibilitySettings(),
                icon: const Icon(Icons.settings_rounded, size: 16),
                label: const Text('Open Accessibility Settings'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC8FF00), side: const BorderSide(color: Color(0xFFC8FF00))),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text('Can read screen, tap, scroll, and type in other apps.', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
            ],
          ]),
        );
      },
    );
  }
}