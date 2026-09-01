import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../widgets/custom_snackbar.dart';

class HQUplinkScreen extends StatefulWidget {
  const HQUplinkScreen({super.key});

  @override
  State<HQUplinkScreen> createState() => _HQUplinkScreenState();
}

class _HQUplinkScreenState extends State<HQUplinkScreen> {
  final _messageController = TextEditingController();
  final _senderController = TextEditingController(text: 'FIELD_TEAM');
  final _locationController = TextEditingController();
  bool _isSending = false;
  bool _isAttachingLocation = false;
  double? _locationLat;
  double? _locationLon;
  double? _locationAccuracy;

  @override
  void initState() {
    super.initState();
    // Fetch GS messages when screen loads; autofill sender from the
    // logged-in identity (file 05 task 5.2; stays editable, and the
    // backend stamps token identity server-side regardless).
    Future.microtask(() {
      if (!mounted) {
        return;
      }
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.isLoggedIn) {
        _senderController.text = auth.personnelId;
      }
      Provider.of<MessageProvider>(context, listen: false).fetchGSMessages();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _senderController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _attachCurrentLocation() async {
    if (_isSending || _isAttachingLocation) {
      return;
    }

    setState(() => _isAttachingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          CustomSnackBar.show(
            context,
            'Please enable Location Services and press Fetch again.',
            type: SnackBarType.error,
          );
        }
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission permanently denied. Enable it in system settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      _locationLat = position.latitude;
      _locationLon = position.longitude;
      _locationAccuracy = position.accuracy;
      _locationController.text =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)} (±${position.accuracy.toStringAsFixed(1)}m)';

      if (!mounted) {
        return;
      }

      CustomSnackBar.show(context, 'Current location attached.',
          type: SnackBarType.success);
    } catch (e) {
      if (!mounted) {
        return;
      }

      CustomSnackBar.show(context, 'Could not attach location: $e',
          type: SnackBarType.error);
    } finally {
      if (mounted) {
        setState(() => _isAttachingLocation = false);
      }
    }
  }

  void _submitMessage() async {
    if (_messageController.text.trim().isEmpty) {
      CustomSnackBar.show(context, 'Please enter a message',
          type: SnackBarType.error);
      return;
    }

    setState(() => _isSending = true);

    try {
      final provider = Provider.of<MessageProvider>(context, listen: false);
      await provider.submitGSUplink(
        _messageController.text.trim(),
        _senderController.text.trim(),
        locationLat: _locationLat,
        locationLon: _locationLon,
        locationAccuracy: _locationAccuracy,
      );

      _messageController.clear();
      _locationController.clear();
      _locationLat = null;
      _locationLon = null;
      _locationAccuracy = null;
      CustomSnackBar.show(context, 'Message sent to HQ!',
          type: SnackBarType.success);
    } catch (e) {
      final provider = Provider.of<MessageProvider>(context, listen: false);
      final authMessage = (provider.apiError?.isCredentialFailure ?? false)
          ? 'Not authorized. Log in again or check Settings.'
          : 'Error: $e';
      CustomSnackBar.show(context, authMessage, type: SnackBarType.error);
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HQ Uplink'),
      ),
      body: Consumer<MessageProvider>(
        builder: (context, messageProvider, child) {
          return CustomScrollView(
            slivers: [
              // Message input section
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send Message to HQ',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A2E),
                            ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _senderController,
                        decoration: _modernDecoration(
                          'Sender Name',
                          Icons.person,
                        ),
                        enabled: !_isSending,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _locationController,
                        decoration: _modernDecoration(
                          'Location',
                          Icons.place,
                          hint: 'Attach your current GPS location',
                        ),
                        readOnly: true,
                        enabled: !_isSending,
                        maxLines: 2,
                        minLines: 1,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _isSending || _isAttachingLocation
                              ? null
                              : _attachCurrentLocation,
                          icon: const Icon(Icons.my_location),
                          label: Text(
                            _isAttachingLocation
                                ? 'Fetching location...'
                                : 'Fetch current location',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.kPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _messageController,
                        decoration: _modernDecoration(
                          'Message',
                          Icons.message,
                          hint: 'Enter your field report or status update',
                        ),
                        maxLines: 4,
                        minLines: 3,
                        enabled: !_isSending,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSending ? null : _submitMessage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 2,
                          ),
                          child: _isSending
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text(
                                  'SEND TO HQ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Messages log section header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Message Log',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A2E),
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        color: AppTheme.kPrimary,
                        onPressed: () => messageProvider.fetchGSMessages(),
                      ),
                    ],
                  ),
                ),
              ),

              // Messages list or empty state
              if (messageProvider.gsMessages.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1A1A2E),
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Messages will appear here',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // Reverse order
                      final message = messageProvider.gsMessages[
                          messageProvider.gsMessages.length - 1 - index];
                      final formattedTime = message.displayTime;

                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: const Border(
                            left: BorderSide(
                                color: AppTheme.kPrimary, width: 5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    message.sender,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.kPrimary,
                                        ),
                                  ),
                                  Text(
                                    formattedTime,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Colors.grey.shade600,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                message.content,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF212121),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: messageProvider.gsMessages.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _modernDecoration(String label, IconData icon,
      {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF5F7FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.kPrimary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
