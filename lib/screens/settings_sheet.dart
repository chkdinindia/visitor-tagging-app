import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';

Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => ChangeNotifierProvider<AppState>.value(
      value: context.read<AppState>(),
      child: const _SettingsSheet(),
    ),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Device & Sync', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            _Section(children: <Widget>[
              _InfoRow(label: 'Event', value: app.eventName),
              _InfoRow(label: 'Event ID', value: app.eventId ?? '—'),
              _InfoRow(label: 'Device ID', value: app.deviceId),
              _InfoRow(label: 'Server', value: app.baseUrl),
            ]),
            const SizedBox(height: 12),
            _Section(children: <Widget>[
              _InfoRow(label: 'Guests in local DB', value: '${app.totalCodes}'),
              _InfoRow(label: 'Last sync', value: fullLocalTime(app.lastSyncUtc)),
              _InfoRow(label: 'Sync checkpoint', value: fullUtcTime(app.lastSyncUtc)),
              _InfoRow(label: 'Last attempt', value: timeAgo(app.lastAttemptUtc)),
              _InfoRow(label: 'Changes in last sync', value: '${app.lastChangeCount}'),
              _InfoRow(
                label: 'Auto sync',
                value: 'Every ${AppConfig.syncInterval.inMinutes} min',
              ),
              if (app.lastError != null)
                _InfoRow(label: 'Last error', value: app.lastError!, valueColor: AppColors.error),
            ]),
            const SizedBox(height: 12),
            _Section(children: <Widget>[
              _InfoRow(label: 'Uploaded tags', value: '${app.syncedCount}', valueColor: AppColors.success),
              _InfoRow(
                label: 'Waiting to upload',
                value: '${app.pendingCount}',
                valueColor: app.pendingCount > 0 ? AppColors.warning : null,
              ),
              _InfoRow(
                label: 'Rejected by server',
                value: '${app.rejectedCount}',
                valueColor: app.rejectedCount > 0 ? AppColors.error : null,
              ),
            ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: app.syncing ? null : app.syncNow,
              icon: app.syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(app.syncing ? 'Syncing…' : 'Sync now'),
            ),
            if (app.rejectedCount > 0) ...<Widget>[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: app.retryRejected,
                icon: const Icon(Icons.replay_rounded),
                label: Text('Retry ${app.rejectedCount} rejected'),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _confirmLogout(context, app),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log out of event'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AppState app) async {
    final pending = app.pendingCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Log out?'),
        content: Text(
          pending > 0
              ? '$pending tag(s) have not been uploaded yet and will be lost. '
                  'Connect to the internet and sync first.'
              : 'The local guest database will be removed from this device.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(pending > 0 ? 'Log out anyway' : 'Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).pop();
    await app.logout();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, color: valueColor ?? AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
