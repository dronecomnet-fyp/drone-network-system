import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';

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
        throw Exception('Location services are disabled on this device.');
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location attached.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach location: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isAttachingLocation = false);
      }
    }
  }

  void _submitMessage() async {
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent to HQ!')),
      );
    } catch (e) {
      final provider = Provider.of<MessageProvider>(context, listen: false);
      final authMessage = (provider.apiError?.isCredentialFailure ?? false)
          ? 'Not authorized. Log in again or check Settings.'
          : 'Error: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authMessage)),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HQ Uplink'),
        backgroundColor: Colors.blue.shade700,
        elevation: 4,
      ),
      body: Consumer<MessageProvider>(
        builder: (context, messageProvider, child) {
          return Column(
            children: [
              // Message input section
              Container(
                color: Colors.blue.shade50,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send Message to HQ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _senderController,
                      decoration: InputDecoration(
                        labelText: 'Sender Name',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      enabled: !_isSending,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: 'Location',
                        prefixIcon: const Icon(Icons.place),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'Attach your current GPS location',
                      ),
                      readOnly: true,
                      enabled: !_isSending,
                      maxLines: 2,
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
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        labelText: 'Message',
                        prefixIcon: const Icon(Icons.message),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'Enter your field report or status update',
                      ),
                      maxLines: 4,
                      enabled: !_isSending,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSending ? null : _submitMessage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              // Messages log section
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Message Log',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () => messageProvider.fetchGSMessages(),
                          ),
                        ],
                      ),
                    ),
                    if (messageProvider.gsMessages.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                  size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Messages will appear here',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () => messageProvider.fetchGSMessages(),
                          child: ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(8),
                            itemCount: messageProvider.gsMessages.length,
                            itemBuilder: (context, index) {
                              final message = messageProvider.gsMessages[
                                  messageProvider.gsMessages.length -
                                      1 -
                                      index];
                              final formattedTime = message.displayTime;

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 4),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                                ),
                                          ),
                                          Text(
                                            formattedTime,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        message.content,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
