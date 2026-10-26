import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../filters/filter_providers.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnlineAsync = ref.watch(backendOnlineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SYNC CENTER'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(isOnlineAsync),
            const SizedBox(height: 24),
            const Text(
              'PENDING SYNC',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.2),
            ),
            const SizedBox(height: 16),
            _buildQueueCard(),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                // Trigger manual sync
              },
              icon: const Icon(Icons.sync),
              label: const Text('SYNC NOW'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(AsyncValue<bool> isOnlineAsync) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Internet / Backend Status', style: TextStyle(color: Colors.white70)),
              isOnlineAsync.when(
                data: (isOnline) => Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: isOnline ? AppTheme.success : AppTheme.error,
                ),
                loading: () => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                error: (_, __) => Icon(Icons.wifi_off, color: AppTheme.error),
              ),
            ],
          ),
          const Divider(height: 32, color: Colors.white24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Last Sync', style: TextStyle(color: Colors.white70)),
              Text('11:42 AM', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          _buildQueueRow('Pole Records', '7'),
          const Divider(height: 24, color: Colors.white12),
          _buildQueueRow('Images', '18'),
          const Divider(height: 24, color: Colors.white12),
          _buildQueueRow('GPS Records', '7'),
        ],
      ),
    );
  }

  Widget _buildQueueRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
