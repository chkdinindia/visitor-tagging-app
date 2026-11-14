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

  Future<void> _submit() async {
    if (!_isComplete || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _status = 'Connecting…';
    });
    try {
      await context.read<AppState>().login(
            _code,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      const Text(
                        'Enter your 6-digit Event ID to download\nthe guest database to this device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.45),
                      ),
                      const SizedBox(height: 36),
                      _PinField(
                        controller: _controller,
                        focusNode: _focus,
                        enabled: !_loading,
                        hasError: _error != null,
                        onCompleted: _submit,
                      ),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _error == null
                            ? const SizedBox(height: 20)
                            : Row(
                                key: ValueKey<String>(_error!),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _isComplete && !_loading ? _submit : null,
                        child: _loading
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(child: Text(_status ?? 'Please wait…', overflow: TextOverflow.ellipsis)),
                                ],
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
