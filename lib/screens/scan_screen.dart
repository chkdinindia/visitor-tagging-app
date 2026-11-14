import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../data/models.dart';
import '../services/app_state.dart';
import '../services/scanner_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'settings_sheet.dart';

enum _Step { guest, card }

enum _FeedbackKind { success, warning, error }

class _Feedback {
  const _Feedback(this.kind, this.title, [this.detail]);

  final _FeedbackKind kind;
  final String title;
  final String? detail;

  Color get color => switch (kind) {
        _FeedbackKind.success => AppColors.success,
        _FeedbackKind.warning => AppColors.warning,
        _FeedbackKind.error => AppColors.error,
      };

  IconData get icon => switch (kind) {
        _FeedbackKind.success => Icons.check_circle_rounded,
        _FeedbackKind.warning => Icons.warning_amber_rounded,
        _FeedbackKind.error => Icons.cancel_rounded,
      };
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // Hidden input that receives scans from scanners in keyboard-wedge mode.
  final TextEditingController _wedgeController = TextEditingController();
  final FocusNode _wedgeFocus = FocusNode();
  Timer? _wedgeDebounce;

  StreamSubscription<String>? _broadcastSub;
  Timer? _clockTimer;
  Timer? _feedbackTimer;

  _Step _step = _Step.guest;
  QrRecord? _guest;
  TagRecord? _guestExistingTag;
  _Feedback? _feedback;
  int _flashToken = 0;
  Color _flashColor = Colors.transparent;

  bool _busy = false;
  String? _lastCode;
  DateTime _lastCodeAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _broadcastSub = ScannerService.broadcastScans.listen(_handleScan);
    // Refresh "synced 1m ago" labels.
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusScanner());
  }

  @override
  void dispose() {
    _broadcastSub?.cancel();
    _clockTimer?.cancel();
    _feedbackTimer?.cancel();
    _wedgeDebounce?.cancel();
    _wedgeController.dispose();
    _wedgeFocus.dispose();
    super.dispose();
  }

  void _focusScanner() {
    if (mounted && !_wedgeFocus.hasFocus) _wedgeFocus.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // Scanner input
  // ---------------------------------------------------------------------------

  void _onWedgeChanged(String _) {
    // Some scanners do not send an Enter suffix, so submit after a short pause.
    _wedgeDebounce?.cancel();
    _wedgeDebounce = Timer(const Duration(milliseconds: 250), _submitWedge);
  }

  void _submitWedge() {
    _wedgeDebounce?.cancel();
    final value = _wedgeController.text;
    _wedgeController.clear();
    if (value.trim().isNotEmpty) _handleScan(value);
    _focusScanner();
  }

  Future<void> _handleScan(String raw) async {
    final code = raw.replaceAll(RegExp(r'[\r\n\t]'), '').trim();
    if (code.isEmpty || _busy) return;

    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastCodeAt) < AppConfig.duplicateScanWindow) return;
    _lastCode = code;
    _lastCodeAt = now;

    _busy = true;
    try {
      if (_step == _Step.guest) {
        await _handleGuestScan(code);
      } else {
        await _handleCardScan(code);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _handleGuestScan(String code) async {
    final app = context.read<AppState>();
    final found = await app.findGuest(code);
    if (!mounted) return;

    if (found == null && !AppConfig.allowUnknownGuest) {
      _showFeedback(const _Feedback(
        _FeedbackKind.error,
        'Guest not found',
        'This QR is not in the event database. Try syncing, or check the badge.',
      ));
      return;
    }
    final QrRecord guest =
        found ?? QrRecord(qrCode: code, categoryId: '', categoryName: 'Unknown guest');

    final existing = await app.tagForGuest(code);
    if (!mounted) return;

    setState(() {
      _guest = guest;
      _guestExistingTag = existing;
      _step = _Step.card;
    });
    _showFeedback(existing == null
        ? _Feedback(_FeedbackKind.success, 'Guest verified', guest.categoryLabel)
        : _Feedback(
            _FeedbackKind.warning,
            'Guest already tagged',
            'Previous card: ${existing.cardQr}. Scan a card to tag again.',
          ));
  }

  Future<void> _handleCardScan(String code) async {
    final app = context.read<AppState>();
    final guest = _guest;
    if (guest == null) {
      _reset();
      return;
    }

    if (code == guest.qrCode) {
      _showFeedback(const _Feedback(
        _FeedbackKind.error,
        'Same QR scanned again',
        'That is the guest QR. Now scan the QR on the printed card.',
      ));
      return;
    }

    if (AppConfig.rejectGuestQrAsCard && await app.findGuest(code) != null) {
      if (!mounted) return;
      _showFeedback(const _Feedback(
        _FeedbackKind.error,
        'This is a guest QR',
        'Scan the QR on the printed card, not another guest badge.',
      ));
      return;
    }

    final used = await app.tagForCard(code);
    if (!mounted) return;
    if (used != null && used.guestQr != guest.qrCode) {
      _showFeedback(_Feedback(
        _FeedbackKind.error,
        'Card already used',
        'This card is linked to guest ${used.guestQr}.',
      ));
      return;
    }

    await app.saveTag(guest, code);
    if (!mounted) return;
    setState(() {
      _step = _Step.guest;
      _guest = null;
      _guestExistingTag = null;
    });
    _showFeedback(_Feedback(
      _FeedbackKind.success,
      'Tagged successfully',
      '${guest.qrCode}  →  $code',
    ));
  }

  void _reset() {
    setState(() {
      _step = _Step.guest;
      _guest = null;
      _guestExistingTag = null;
      _feedback = null;
    });
    _focusScanner();
  }

  void _showFeedback(_Feedback feedback) {
    switch (feedback.kind) {
      case _FeedbackKind.success:
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
      case _FeedbackKind.warning:
        HapticFeedback.heavyImpact();
      case _FeedbackKind.error:
        HapticFeedback.vibrate();
        SystemSound.play(SystemSoundType.alert);
    }

    _feedbackTimer?.cancel();
    setState(() {
      _feedback = feedback;
      _flashColor = feedback.color.withValues(alpha: 0.28);
      _flashToken++;
    });
    final token = _flashToken;
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (mounted && token == _flashToken) setState(() => _flashColor = Colors.transparent);
    });
    _feedbackTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(_step == _Step.guest ? 'Enter guest QR' : 'Enter card QR'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'QR code value'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) {
      _lastCode = null; // Manual entry is always intentional.
      await _handleScan(value);
    }
    _focusScanner();
  }

  Future<void> _openSettings() async {
    await showSettingsSheet(context);
    _focusScanner();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _focusScanner,
        child: Stack(
          children: <Widget>[
            GlowBackground(
              child: SafeArea(
                child: Column(
                  children: <Widget>[
                    _Header(app: app, onSettings: _openSettings),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        children: <Widget>[
                          _StatsRow(app: app),
                          const SizedBox(height: 14),
                          _StepIndicator(step: _step),
                          const SizedBox(height: 14),
                          _ScanPanel(
                            step: _step,
                            guest: _guest,
                            existingTag: _guestExistingTag,
                            onCancel: _reset,
                          ),
                          const SizedBox(height: 12),
                          _FeedbackBanner(feedback: _feedback),
                          const SizedBox(height: 18),
                          _RecentTags(tags: app.recentTags),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: OutlinedButton.icon(
                        onPressed: _manualEntry,
                        icon: const Icon(Icons.keyboard_alt_outlined, size: 20),
                        label: const Text('Enter code manually'),
                      ),
                    ),
                    // Invisible input for keyboard-wedge scanners.
                    SizedBox(
                      width: 1,
                      height: 1,
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _wedgeController,
                          focusNode: _wedgeFocus,
                          autofocus: true,
                          keyboardType: TextInputType.none,
                          textInputAction: TextInputAction.done,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(border: InputBorder.none, filled: false),
                          onChanged: _onWedgeChanged,
                          onEditingComplete: () {},
                          onSubmitted: (_) => _submitWedge(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Full-screen color flash on scan result.
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                color: _flashColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Header
// -----------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.app, required this.onSettings});

  final AppState app;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: <Widget>[
          const AppLogo(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  app.eventName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Event ID ${app.eventId ?? ''}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          _SyncChip(app: app),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.tune_rounded),
            color: AppColors.textSecondary,
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (app.syncing) {
      color = AppColors.primary;
      label = 'Syncing';
    } else if (app.online == false) {
      color = AppColors.error;
      label = 'Offline';
    } else {
      color = AppColors.success;
      label = timeAgo(app.lastSyncUtc);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: app.syncing ? null : app.syncNow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (app.syncing)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[BoxShadow(color: color, blurRadius: 6)],
                ),
              ),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Stats
// -----------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatTile(
            icon: Icons.qr_code_2_rounded,
            value: app.totalCodes,
            label: 'Guests',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.link_rounded,
            value: app.taggedCount,
            label: 'Tagged',
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.cloud_upload_outlined,
            value: app.pendingCount,
            label: 'Pending',
            color: app.pendingCount > 0 ? AppColors.warning : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$value',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Steps
// -----------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final onCard = step == _Step.card;
    return Row(
      children: <Widget>[
        Expanded(child: _StepPill(number: 1, label: 'Guest QR', active: !onCard, done: onCard)),
        Container(
          width: 28,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: onCard ? AppColors.primary : AppColors.border,
        ),
        Expanded(child: _StepPill(number: 2, label: 'Card QR', active: onCard, done: false)),
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({required this.number, required this.label, required this.active, required this.done});

  final int number;
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = active || done ? AppColors.primary : AppColors.textMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? AppColors.primary.withValues(alpha: 0.14) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? AppColors.primary : AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active || done ? AppColors.primary : AppColors.surfaceHigh,
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: active ? AppColors.textPrimary : color),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Main scan panel
// -----------------------------------------------------------------------------

class _ScanPanel extends StatelessWidget {
  const _ScanPanel({
    required this.step,
    required this.guest,
    required this.existingTag,
    required this.onCancel,
  });

  final _Step step;
  final QrRecord? guest;
  final TagRecord? existingTag;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final onCard = step == _Step.card && guest != null;
    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      borderColor: onCard ? AppColors.primary.withValues(alpha: 0.6) : AppColors.border,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: onCard ? _cardStep(guest!) : _guestStep(),
      ),
    );
  }

  Widget _guestStep() {
    return const Column(
      key: ValueKey<String>('guest'),
      children: <Widget>[
        PulseIcon(icon: Icons.qr_code_scanner_rounded, size: 140),
        SizedBox(height: 14),
        Text('Scan guest QR', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text(
          'Press the scan button and aim the laser\nat the QR code on the guest badge.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
      ],
    );
  }

  Widget _cardStep(QrRecord guest) {
    final categoryColor = AppColors.forCategory(guest.categoryId);
    return Column(
      key: ValueKey<String>('card-${guest.qrCode}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: categoryColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.person_rounded, color: categoryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('GUEST', style: TextStyle(color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      guest.qrCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: Pill(label: guest.categoryLabel, color: categoryColor)),
            ],
          ),
        ),
        if (existingTag != null) ...<Widget>[
          const SizedBox(height: 10),
          Pill(
            label: 'Already tagged with ${existingTag!.cardQr}',
            color: AppColors.warning,
            icon: Icons.info_outline_rounded,
          ),
        ],
        const SizedBox(height: 18),
        const Center(child: PulseIcon(icon: Icons.style_rounded, color: AppColors.accent, size: 120)),
        const SizedBox(height: 12),
        const Text(
          'Now scan the printed card',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Scan the QR printed on the card to link it to this guest.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel and scan another guest'),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Feedback
// -----------------------------------------------------------------------------

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.feedback});

  final _Feedback? feedback;

  @override
  Widget build(BuildContext context) {
    final f = feedback;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: f == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: f.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: f.color.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(f.icon, color: f.color, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(f.title, style: TextStyle(color: f.color, fontWeight: FontWeight.w800, fontSize: 16)),
                        if (f.detail != null) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(f.detail!, style: const TextStyle(color: AppColors.textSecondary, height: 1.35)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Recent tags
// -----------------------------------------------------------------------------

class _RecentTags extends StatelessWidget {
  const _RecentTags({required this.tags});

  final List<TagRecord> tags;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'RECENT TAGS',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w700),
          ),
        ),
        if (tags.isEmpty)
          const Panel(
            child: Row(
              children: <Widget>[
                Icon(Icons.inbox_outlined, color: AppColors.textMuted),
                SizedBox(width: 12),
                Expanded(
                  child: Text('No tags yet. Scanned pairs will appear here.', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ),
          )
        else
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                for (var i = 0; i < tags.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1, indent: 60, color: AppColors.border),
                  _TagTile(tag: tags[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TagTile extends StatelessWidget {
  const _TagTile({required this.tag});

  final TagRecord tag;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String tooltip) = switch (tag.status) {
      TagSyncStatus.synced => (Icons.cloud_done_rounded, AppColors.success, 'Uploaded'),
      TagSyncStatus.pending => (Icons.cloud_upload_rounded, AppColors.warning, 'Waiting to upload'),
      TagSyncStatus.rejected => (Icons.error_rounded, AppColors.error, tag.error ?? 'Rejected by server'),
    };
    final categoryColor = AppColors.forCategory(tag.categoryId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          Tooltip(
            message: tooltip,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tag.guestQr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        tag.status == TagSyncStatus.rejected && tag.error != null
                            ? '${tag.cardQr} · ${tag.error}'
                            : tag.cardQr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tag.status == TagSyncStatus.rejected ? AppColors.error : AppColors.textSecondary,
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: categoryColor, shape: BoxShape.circle),
              ),
              const SizedBox(height: 6),
              Text(clockTime(tag.scannedAtUtc), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
