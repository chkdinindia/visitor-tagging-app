import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../data/api_client.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _loading = false;
  bool _choosingCategory = false;
  TaggingCategory? _selected;
  List<TaggingCategory> _categories = const <TaggingCategory>[];
  String? _status;
  String? _error;

  String get _code => _controller.text;
  bool get _isComplete => _code.length == AppConfig.eventIdLength;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_isComplete || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final categories = await context.read<AppState>().fetchCategories(_code);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _choosingCategory = true;
        _loading = false;
      });
    } on ApiException catch (e) {
      _fail(e.isNetwork ? '${e.message}. Check the internet and try again.' : e.message);
    } catch (e) {
      _fail('Something went wrong: $e');
    }
  }

  void _backToEventId() {
    if (_loading) return;
    setState(() {
      _choosingCategory = false;
      _error = null;
    });
    _focus.requestFocus();
  }

  Future<void> _download(TaggingCategory category) async {
    if (_loading) return;
    setState(() {
      _selected = category;
      _loading = true;
      _error = null;
      _status = 'Connecting…';
    });
    try {
      await context.read<AppState>().login(
            _code,
            category,
            onStatus: (s) {
              if (mounted) setState(() => _status = s);
            },
          );
      // AppState switches the app to the scan screen.
    } on ApiException catch (e) {
      _fail(e.isNetwork ? '${e.message}. Check the internet and try again.' : e.message);
    } catch (e) {
      _fail('Something went wrong: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _loading = false;
      _status = null;
      _error = message;
    });
  }

  Future<void> _editServer() async {
    final app = context.read<AppState>();
    final controller = TextEditingController(text: app.baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Server URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'URL of the visitor_tagging controller, e.g. https://yoursite.com/visitor_tagging',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'https://yoursite.com/visitor_tagging'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(AppConfig.defaultBaseUrl),
            child: const Text('Reset'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await app.setBaseUrl(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      floatingActionButton: _loading
          ? null
          : IconButton(
              onPressed: _editServer,
              tooltip: 'Server URL',
              icon: const Icon(Icons.dns_outlined, color: AppColors.textMuted),
            ),
      body: GlowBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Spacer(flex: 2),
                      const Center(child: AppLogo(size: 84)),
                      const SizedBox(height: 28),
                      const Text(
                        'Visitor Tagging',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _choosingCategory
                            ? 'Event $_code\nSelect the category you are tagging.'
                            : 'Enter your 6-digit Event ID to download\nthe guest database to this device.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.45),
                      ),
                      const SizedBox(height: 32),
                      if (_choosingCategory) ...<Widget>[
                        for (final category in _categories)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _CategoryTile(
                              category: category,
                              enabled: !_loading,
                              loading: _loading && _selected == category,
                              status: _status,
                              onTap: () => _download(category),
                            ),
                          ),
                        const SizedBox(height: 6),
                        _ErrorText(error: _error),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _loading ? null : _backToEventId,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Change Event ID'),
                          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                        ),
                      ] else ...<Widget>[
                      _PinField(
                        controller: _controller,
                        focusNode: _focus,
                        enabled: !_loading,
                        hasError: _error != null,
                        onCompleted: _continue,
                      ),
                      const SizedBox(height: 16),
                      _ErrorText(error: _error),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _isComplete && !_loading ? _continue : null,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Text('Continue'),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded, size: 20),
                                ],
                              ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Use 000000 to try the demo without internet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                      ),
                      ],
                      const Spacer(flex: 3),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Powered by CHKDIN',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12, letterSpacing: 1.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final message = error;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: message == null
          ? const SizedBox(height: 20)
          : Row(
              key: ValueKey<String>(message),
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.enabled,
    required this.loading,
    required this.status,
    required this.onTap,
  });

  final TaggingCategory category;
  final bool enabled;
  final bool loading;
  final String? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forCategory(category.id);
    return Material(
      color: loading ? color.withValues(alpha: 0.14) : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: loading ? color : AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.style_rounded, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(category.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      loading ? (status ?? 'Please wait…') : 'Category ID ${category.id}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (loading)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
                )
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Six digit boxes backed by one invisible text field.
class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    const length = AppConfig.eventIdLength;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? focusNode.requestFocus : null,
      child: Stack(
        children: <Widget>[
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 64,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: length,
                showCursor: false,
                enableInteractiveSelection: false,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', filled: false, border: InputBorder.none),
                onChanged: (value) {
                  if (value.length == length) onCompleted();
                },
                onSubmitted: (_) => onCompleted(),
              ),
            ),
          ),
          IgnorePointer(
            child: ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[controller, focusNode]),
              builder: (context, _) {
                final text = controller.text;
                return Row(
                  children: List<Widget>.generate(length, (i) {
                    final filled = i < text.length;
                    final active = focusNode.hasFocus && i == text.length.clamp(0, length - 1) && enabled;
                    final borderColor = hasError
                        ? AppColors.error
                        : active
                            ? AppColors.primary
                            : filled
                                ? AppColors.primary.withValues(alpha: 0.5)
                                : AppColors.border;
                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 64,
                        margin: EdgeInsets.only(right: i == length - 1 ? 0 : 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: filled ? AppColors.surfaceHigh : AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: active ? 2 : 1.2),
                          boxShadow: active
                              ? <BoxShadow>[
                                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.30), blurRadius: 16),
                                ]
                              : null,
                        ),
                        child: Text(
                          filled ? text[i] : '',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
