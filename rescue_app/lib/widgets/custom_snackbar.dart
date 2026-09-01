import 'package:flutter/material.dart';
import '../config/app_theme.dart';

enum SnackBarType { success, error, info }

class CustomSnackBar {
  static void show(BuildContext context, String message, {SnackBarType type = SnackBarType.info}) {
    if (!context.mounted) return;
    
    Color bgColor;
    IconData icon;
    
    switch (type) {
      case SnackBarType.success:
        bgColor = AppTheme.kSuccess;
        icon = Icons.check_circle_outline;
        break;
      case SnackBarType.error:
        bgColor = AppTheme.kDanger;
        icon = Icons.error_outline;
        break;
      case SnackBarType.info:
      default:
        bgColor = AppTheme.kPrimary;
        icon = Icons.info_outline;
        break;
    }
    
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        elevation: 8,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
