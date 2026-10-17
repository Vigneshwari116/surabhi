import 'package:flutter/material.dart';
import 'package:surabhi/config/local_credentials.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/services/session_service.dart';

class LocationResetResult {
  final bool ok;
  final bool localCleared;
  final String? error;

  const LocationResetResult({
    required this.ok,
    required this.localCleared,
    this.error,
  });
}

/// Clears all sales data for the current location on this device.
class LocationResetService {
  static const String resetLocalOnlyMessage =
      'RESET permanently deletes ALL sales data for this location on this '
      'device and resets bill numbers to 1.';

  static Future<bool> confirmReset(BuildContext context) async {
    final passwordOk = await _promptPassword(
      context,
      title: 'Reset password',
      message: 'Enter reset password to continue.',
      confirmLabel: 'CONTINUE',
    );
    if (!passwordOk || !context.mounted) {
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset all sales data?'),
          content: Text(
            'This will permanently delete ALL sales data for this location '
            'on this device and reset bill numbers to 1.\n\n'
            '$resetLocalOnlyMessage\n\n'
            'Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('RESET'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  static Future<LocationResetResult> resetCurrentLocation({
    required String locationDisplayName,
    required String password,
  }) async {
    if (password != resetPassword) {
      return const LocationResetResult(
        ok: false,
        localCleared: false,
        error: 'Incorrect password',
      );
    }

    try {
      await LocalDb.instance.resetLocationSalesData(locationDisplayName);
      await SessionService.clearBillSession();

      return const LocationResetResult(
        ok: true,
        localCleared: true,
      );
    } catch (e) {
      return LocationResetResult(
        ok: false,
        localCleared: false,
        error: 'Reset failed: $e',
      );
    }
  }

  static Future<bool> _promptPassword(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      if (controller.text == resetPassword) {
                        Navigator.pop(dialogContext, true);
                      } else {
                        setState(() => error = 'Incorrect password');
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('CANCEL'),
                ),
                TextButton(
                  onPressed: () {
                    if (controller.text == resetPassword) {
                      Navigator.pop(dialogContext, true);
                    } else {
                      setState(() => error = 'Incorrect password');
                    }
                  },
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    return ok ?? false;
  }
}
