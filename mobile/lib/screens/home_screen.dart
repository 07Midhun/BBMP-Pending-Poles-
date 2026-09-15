import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/pole_model.dart';
import '../services/api_service.dart';

class _ImageFormat {
  final String extension;
  final String mimeType;

  const _ImageFormat(this.extension, this.mimeType);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isBackendOnline = false;
  bool _loadingZones = false;
  String? _zoneLoadError;
  String? _loadingIoTPole;
  bool _loadingPoles = false;
  int _selectionGeneration = 0;
  int _distanceRequestId = 0;
  int _lampTypeRequestId = 0;

  final ImagePicker _imagePicker = ImagePicker();

  // Technician image upload state.
  final Map<String, bool> _uploadingImages = {};
  final Map<String, String> _uploadedImageUrls = {};
  final Map<String, String> _imageErrors = {};

  // Selected Filter States
  String? _selectedRegion;
  String? _selectedZone;
  String? _selectedWard;
  String? _selectedPoleOldLamp;
  String? _selectedLampType;
  String? _selectedStartingPole;

  // Options Lists
  List<String> _regions = [];
  List<String> _zones = [];
  List<String> _wards = [];
  List<String> _lampTypes = [];
  List<String> _startingPoles = [];

  // Latest backend result for the selected Region / Zone / Ward.
  // Lamp classification filters are then applied locally for instant updates.
  List<Pole> _baseFilteredPoles = [];

  // Filtered & Distance Ordered Results
  List<Pole> _filteredPoles = [];
  List<Pole> _orderedPoles = [];

  @override
  void initState() {
    super.initState();
    _initDataAndCheckBackend();
  }

  Future<void> _initDataAndCheckBackend() async {
    final online = await ApiService.checkHealth();

    if (!mounted) return;

    setState(() {
      _isBackendOnline = online;
    });

    await _loadRegions();
  }

  Future<void> _loadRegions() async {
    if (!_isBackendOnline) {
      if (!mounted) return;

      setState(() {
        _regions = [];
      });

      return;
    }

    try {
      // Only these two regions are allowed in this application.
      // The backend region values are uppercase and are used for
      // all subsequent zone and ward requests.
      const allowedRegions = <String>[
        'BOMMANAHALLI',
        'EAST',
      ];

      if (!mounted) return;

      setState(() {
        _regions = List<String>.from(allowedRegions);
      });
    } catch (e) {
      debugPrint('Unable to load regions: $e');

      if (!mounted) return;

      setState(() {
        _regions = [];
      });
    }
  }

  Future<void> _onRegionChanged(String? newRegion) async {
    final int generation = ++_selectionGeneration;
    ++_distanceRequestId;
    ++_lampTypeRequestId;

    if (!mounted) return;

    setState(() {
      _selectedRegion = newRegion;
      _selectedZone = null;
      _selectedWard = null;
      _selectedPoleOldLamp = null;
      _selectedLampType = null;
      _selectedStartingPole = null;

      _zones = [];
      _loadingZones = newRegion != null;
      _zoneLoadError = null;
      _wards = [];
      _lampTypes = [];
      _startingPoles = [];
      _baseFilteredPoles = [];
      _filteredPoles = [];
      _orderedPoles = [];
      _loadingPoles = false;
    });

    if (newRegion == null || !_isBackendOnline) {
      if (mounted && generation == _selectionGeneration) {
        setState(() {
          _loadingZones = false;
        });
      }
      return;
    }

    try {
      // Capture the exact value used for this request. Never read
      // _selectedRegion again after the await.
      final regionForRequest = newRegion.trim().toUpperCase();
      List<String> zones = [];

      // First use the central API service.
      try {
        zones = await ApiService.fetchZones(regionForRequest);
      } catch (e) {
        debugPrint('ApiService.fetchZones failed: $e');
      }

      // Fallback for older API-service builds or cached web builds. This
      // calls the same backend endpoint directly and accepts both a plain
      // list response and {"zones": [...]} response.
      if (zones.isEmpty) {
        try {
          final uri = Uri.parse(
            'https://bbmp-pending-poles-4.onrender.com/api/v1/zones'
            '?region=${Uri.encodeQueryComponent(regionForRequest)}',
          );
          final response = await http.get(uri).timeout(
            const Duration(seconds: 10),
          );

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final decoded = jsonDecode(response.body);
            final dynamic rawZones = decoded is Map<String, dynamic>
                ? decoded['zones']
                : decoded;

            if (rawZones is List) {
              zones = rawZones
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty)
                  .toSet()
                  .toList();
            }
          } else {
            debugPrint(
              'Direct zone request failed: ${response.statusCode} '
              '${response.body}',
            );
          }
        } catch (e) {
          debugPrint('Direct zone request failed: $e');
        }
      }

      if (!mounted || generation != _selectionGeneration) return;

      setState(() {
        _zones = zones;
        _loadingZones = false;
        _zoneLoadError = zones.isEmpty
            ? 'No zones returned for $regionForRequest'
            : null;
      });
    } catch (e) {
      debugPrint('Unable to load zones: $e');
      if (!mounted || generation != _selectionGeneration) return;

      setState(() {
        _zones = [];
        _loadingZones = false;
        _zoneLoadError = 'Unable to load zones';
      });
    }
  }

  Future<void> _onZoneChanged(String? newZone) async {
    final int generation = ++_selectionGeneration;
    ++_distanceRequestId;
    ++_lampTypeRequestId;
    final String? regionForRequest = _selectedRegion;

    if (!mounted) return;

    setState(() {
      _selectedZone = newZone;
      _selectedWard = null;
      _selectedPoleOldLamp = null;
      _selectedLampType = null;
      _selectedStartingPole = null;

      _wards = [];
      _lampTypes = [];
      _startingPoles = [];
      _baseFilteredPoles = [];
      _filteredPoles = [];
      _orderedPoles = [];
      _loadingPoles = false;
    });

    if (newZone == null ||
        regionForRequest == null ||
        !_isBackendOnline) {
      return;
    }

    try {
      final wards = await ApiService.fetchWards(
        regionForRequest,
        newZone,
      );

      if (!mounted || generation != _selectionGeneration) return;

      setState(() {
        _wards = wards;
      });
    } catch (_) {
      if (!mounted || generation != _selectionGeneration) return;

      setState(() {
        _wards = [];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load wards.')),
      );
    }
  }

  Future<void> _onWardChanged(String? newWard) async {
    final int generation = ++_selectionGeneration;
    ++_distanceRequestId;
    ++_lampTypeRequestId;

    if (!mounted) return;

    setState(() {
      _selectedWard = newWard;
      _selectedPoleOldLamp = null;
      _selectedLampType = null;
      _selectedStartingPole = null;

      _lampTypes = [];
      _startingPoles = [];
      _baseFilteredPoles = [];
      _filteredPoles = [];
      _orderedPoles = [];
      _loadingPoles = newWard != null;
    });

    if (newWard == null) {
      if (mounted && generation == _selectionGeneration) {
        setState(() {
          _loadingPoles = false;
        });
      }
      return;
    }

    await _applyFilters(generation: generation);
  }

  Future<void> _onPoleOldLampChanged(String? newOldLamp) async {
    final int generation = ++_selectionGeneration;
    ++_distanceRequestId;
    ++_lampTypeRequestId;

    if (!mounted) return;

    final String? region = _selectedRegion;
    final String? zone = _selectedZone;
    final String? ward = _selectedWard;

    setState(() {
      _selectedPoleOldLamp = newOldLamp;
      _selectedLampType = null;
      _selectedStartingPole = null;
      _lampTypes = [];
      _startingPoles = [];
      _filteredPoles = [];
      _orderedPoles = [];
      _loadingPoles = newOldLamp != null;
    });

    if (newOldLamp == null) {
      return;
    }

    if (!_isBackendOnline) {
      if (mounted && generation == _selectionGeneration) {
        setState(() {
          _loadingPoles = false;
        });
      }
      return;
    }

    // The pole-filter request is authoritative for the Starting Pole list.
    // It must never be discarded just because loading the lamp-type options
    // fails or takes longer.
    final polesFuture = ApiService.filterPendingPoles(
      region: region,
      zone: zone,
      ward: ward,
      poleOldLamp: newOldLamp,
      lampType: null,
    );

    try {
      final poles = await polesFuture;

      if (!mounted || generation != _selectionGeneration) return;

      _baseFilteredPoles = List<Pole>.from(poles);

      final startingPoles = <String>[];
      final seen = <String>{};
      for (final pole in poles) {
        final poleNumber = pole.poleNumber.trim();
        if (poleNumber.isNotEmpty && seen.add(poleNumber)) {
          startingPoles.add(poleNumber);
        }
      }

      setState(() {
        _filteredPoles = List<Pole>.from(poles);
        _startingPoles = startingPoles;
        _loadingPoles = false;
      });
    } catch (e) {
      if (!mounted || generation != _selectionGeneration) return;

      setState(() {
        _baseFilteredPoles = [];
        _filteredPoles = [];
        _startingPoles = [];
        _orderedPoles = [];
        _loadingPoles = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load pending poles: $e')),
      );
    }

    // Lamp-type options are loaded independently. A failure here must not
    // clear a successful pending-pole result.
    try {
      final types = await ApiService.fetchLampTypes(
        region: _selectedRegion,
        zone: _selectedZone,
        ward: _selectedWard,
        poleOldLamp:newOldLamp,
      );

      if (!mounted ||
          generation != _selectionGeneration ||
          _selectedPoleOldLamp != newOldLamp) {
        return;
      }

      setState(() {
        _lampTypes = types;
      });
    } catch (e) {
      if (!mounted ||
          generation != _selectionGeneration ||
          _selectedPoleOldLamp != newOldLamp) {
        return;
      }

      // Keep the already loaded poles visible. For Empty, the backend's
      // canonical lamp type is "-".
      if (newOldLamp == 'Empty') {
        setState(() {
          _lampTypes = ['-'];
        });
      } else {
        setState(() {
          _lampTypes = [];
        });
      }
    }
  }

  Future<void> _onLampTypeChanged(String? newLampType) async {
    final int generation = ++_selectionGeneration;
    ++_distanceRequestId;

    if (!mounted) return;

    setState(() {
      _selectedLampType = newLampType;
      _selectedStartingPole = null;
      _startingPoles = [];
      _filteredPoles = [];
      _orderedPoles = [];
      _loadingPoles = true;
    });

    if (newLampType == null) {
      // Re-query the current Old Lamp classification, if any. This keeps
      // backend filtering authoritative and deterministic.
      if (_selectedPoleOldLamp != null) {
        await _onPoleOldLampChanged(_selectedPoleOldLamp);
      } else {
        final nextGeneration = ++_selectionGeneration;
        await _applyFilters(generation: nextGeneration);
      }
      return;
    }

    if (!_isBackendOnline) {
      if (mounted && generation == _selectionGeneration) {
        setState(() {
          _loadingPoles = false;
        });
      }
      return;
    }

    try {
      final poles = await ApiService.filterPendingPoles(
        region: _selectedRegion,
        zone: _selectedZone,
        ward: _selectedWard,
        poleOldLamp: _selectedPoleOldLamp,
        lampType: newLampType,
      );

      if (!mounted || generation != _selectionGeneration) return;

      _baseFilteredPoles = List<Pole>.from(poles);

      final startingPoles = <String>[];
      final seen = <String>{};
      for (final pole in poles) {
        final poleNumber = pole.poleNumber.trim();
        if (poleNumber.isNotEmpty && seen.add(poleNumber)) {
          startingPoles.add(poleNumber);
        }
      }

      setState(() {
        _filteredPoles = List<Pole>.from(poles);
        _startingPoles = startingPoles;
        _loadingPoles = false;
      });
    } catch (e) {
      if (!mounted || generation != _selectionGeneration) return;

      setState(() {
        _baseFilteredPoles = [];
        _filteredPoles = [];
        _startingPoles = [];
        _orderedPoles = [];
        _loadingPoles = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to apply lamp type filter: $e')),
      );
    }
  }

  Future<void> _onStartingPoleChanged(String? newStartingPole) async {
    final int distanceRequestId = ++_distanceRequestId;
    final int generation = _selectionGeneration;

    if (!mounted) return;

    setState(() {
      _selectedStartingPole = newStartingPole;
      _orderedPoles = [];
    });

    if (newStartingPole == null) return;

    await _calculateDistances(
      requestId: distanceRequestId,
      generation: generation,
    );
  }

  Future<void> _showStartingPolePicker() async {
    if (_loadingPoles || _startingPoles.isEmpty) return;

    final controller = TextEditingController();

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final query = controller.text.trim().toLowerCase();
            final visiblePoles = query.isEmpty
                ? _startingPoles
                : _startingPoles
                    .where((pole) => pole.toLowerCase().contains(query))
                    .toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text(
                'Select Starting Pole',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 500,
                height: 500,
                child: Column(
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: (_) => setDialogState(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search pole number...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF38BDF8),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${visiblePoles.length} poles',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: visiblePoles.isEmpty
                          ? const Center(
                              child: Text(
                                'No matching poles',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: visiblePoles.length,
                              itemBuilder: (context, index) {
                                final pole = visiblePoles[index];
                                final isSelected =
                                    pole == _selectedStartingPole;
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    pole,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          color: Color(0xFF38BDF8),
                                        )
                                      : null,
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(pole),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (selected != null && mounted) {
      await _onStartingPoleChanged(selected);
    }
  }

  Future<void> _applyFilters({required int generation}) async {
    if (!mounted || generation != _selectionGeneration) return;

    if (!_isBackendOnline) {
      setState(() {
        _baseFilteredPoles = [];
        _filteredPoles = [];
        _startingPoles = [];
        _orderedPoles = [];
        _loadingPoles = false;
      });
      return;
    }

    // Capture the complete selection before awaiting. The response can only
    // update the UI if this generation is still current.
    final String? region = _selectedRegion;
    final String? zone = _selectedZone;
    final String? ward = _selectedWard;
    final String? poleOldLamp = _selectedPoleOldLamp;
    final String? lampType = _selectedLampType;

    try {
      final matches = await ApiService.filterPendingPoles(
        region: region,
        zone: zone,
        ward: ward,
        poleOldLamp: poleOldLamp,
        lampType: lampType,
      );

      if (!mounted || generation != _selectionGeneration) return;

      _baseFilteredPoles = List<Pole>.from(matches);

      setState(() {
        _filteredPoles = matches;
        _startingPoles = matches.map((p) => p.poleNumber).toList();
        _loadingPoles = false;
        _orderedPoles = [];

        if (_selectedStartingPole != null &&
            !_startingPoles.contains(_selectedStartingPole)) {
          _selectedStartingPole = null;
        }
      });
    } catch (e) {
      if (!mounted || generation != _selectionGeneration) return;

      setState(() {
        _baseFilteredPoles = [];
        _filteredPoles = [];
        _startingPoles = [];
        _orderedPoles = [];
        _loadingPoles = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load pending poles: $e')),
      );
    }
  }

  Future<void> _calculateDistances({
    required int requestId,
    required int generation,
  }) async {
    if (_selectedStartingPole == null || _filteredPoles.isEmpty) {
      if (mounted &&
          generation == _selectionGeneration &&
          requestId == _distanceRequestId) {
        setState(() {
          _orderedPoles = [];
        });
      }
      return;
    }

    if (!_isBackendOnline) return;

    final String startingPole = _selectedStartingPole!;
    final String? region = _selectedRegion;
    final String? zone = _selectedZone;
    final String? ward = _selectedWard;
    final String? poleOldLamp = _selectedPoleOldLamp;
    final String? lampType = _selectedLampType;

    try {
      final sorted = await ApiService.calculateDistance(
        startingPoleNumber: startingPole,
        region: region,
        zone: zone,
        ward: ward,
        poleOldLamp: poleOldLamp,
        lampType: lampType,
      );

      if (!mounted ||
          generation != _selectionGeneration ||
          requestId != _distanceRequestId ||
          startingPole != _selectedStartingPole) {
        return;
      }

      setState(() {
        _orderedPoles = sorted;
      });
    } catch (e) {
      if (!mounted ||
          generation != _selectionGeneration ||
          requestId != _distanceRequestId) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to calculate pole distances: $e')),
      );
    }
  }

  Future<void> _clearFilters() async {
    ++_selectionGeneration;
    ++_distanceRequestId;
    ++_lampTypeRequestId;

    if (!mounted) return;

    setState(() {
      _selectedRegion = null;
      _selectedZone = null;
      _selectedWard = null;
      _selectedPoleOldLamp = null;
      _selectedLampType = null;
      _selectedStartingPole = null;

      _zones = [];
      _loadingZones = false;
      _zoneLoadError = null;
      _wards = [];
      _lampTypes = [];
      _startingPoles = [];
      _baseFilteredPoles = [];
      _filteredPoles = [];
      _orderedPoles = [];
      _loadingPoles = false;
    });

    await _initDataAndCheckBackend();
  }

  String _imageKey(String poleNumber, int slot) =>
      '$poleNumber::$slot';

  _ImageFormat? _detectImageFormat(List<int> bytes, String? reportedMimeType) {
    bool startsWith(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (int i = 0; i < signature.length; i++) {
        if (bytes[i] != signature[i]) return false;
      }
      return true;
    }

    // JPEG: FF D8 FF
    if (startsWith(const [0xFF, 0xD8, 0xFF])) {
      return const _ImageFormat('jpg', 'image/jpeg');
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return const _ImageFormat('png', 'image/png');
    }

    // GIF: GIF87a or GIF89a
    if (startsWith(const [0x47, 0x49, 0x46, 0x38])) {
      return const _ImageFormat('gif', 'image/gif');
    }

    // WEBP: RIFF....WEBP
    if (bytes.length >= 12 &&
        startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return const _ImageFormat('webp', 'image/webp');
    }

    // Fallback to the picker MIME type only when it is an accepted image type.
    final mime = reportedMimeType?.toLowerCase().trim();
    switch (mime) {
      case 'image/jpeg':
      case 'image/jpg':
        return const _ImageFormat('jpg', 'image/jpeg');
      case 'image/png':
        return const _ImageFormat('png', 'image/png');
      case 'image/gif':
        return const _ImageFormat('gif', 'image/gif');
      case 'image/webp':
        return const _ImageFormat('webp', 'image/webp');
      default:
        return null;
    }
  }

  Future<void> _uploadPoleImage({
    required Pole pole,
    required int slot,
    required XFile image,
    required VoidCallback refreshDialog,
  }) async {
    final key = _imageKey(pole.poleNumber, slot);

    setState(() {
      _uploadingImages[key] = true;
      _imageErrors.remove(key);
    });
    refreshDialog();

    try {
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Selected image is empty. Please choose another image.');
      }

      // Determine the real image format from the file bytes first. This is
      // more reliable than image.name, especially for Android gallery files.
      final imageFormat = _detectImageFormat(bytes, image.mimeType);
      if (imageFormat == null) {
        throw Exception(
          'Uploaded file must be an image. Please choose a JPG, PNG, WEBP, or GIF file.',
        );
      }

      final extension = imageFormat.extension;
      final mimeType = imageFormat.mimeType;

      final baseUrl = ApiService.activeBaseUrl;
      final uri = Uri.parse(
        '$baseUrl/poles/${Uri.encodeComponent(pole.poleNumber)}/images/$slot',
      );

      final request = http.MultipartRequest('POST', uri);
      request.headers['Accept'] = 'application/json';
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'image_$slot.$extension',
          contentType: MediaType.parse(mimeType),
        ),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = 'Upload failed (${response.statusCode})';
        try {
          final decoded = jsonDecode(responseBody);
          if (decoded is Map && decoded['detail'] != null) {
            message = decoded['detail'].toString();
          }
        } catch (_) {}
        throw Exception(message);
      }

      try {
        final decoded = jsonDecode(responseBody);
        if (decoded is Map && decoded['image_url'] != null) {
          _uploadedImageUrls[key] = decoded['image_url'].toString();
        }
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image $slot uploaded for ${pole.poleNumber}')),
        );
      }
    } catch (e) {
      _imageErrors[key] = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingImages[key] = false;
        });
        refreshDialog();
      }
    }
  }

  Future<void> _showPoleImages(Pole pole) async {
    final images = <int, XFile>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text(
                'Pole Images',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pole.poleNumber,
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${pole.latitude}, ${pole.longitude}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (int slot = 1; slot <= 3; slot++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildImageSlot(
                            context: context,
                            pole: pole,
                            slot: slot,
                            image: images[slot],
                            uploading: _uploadingImages[
                                    _imageKey(pole.poleNumber, slot)] ??
                                false,
                            uploadedUrl: _uploadedImageUrls[
                                _imageKey(pole.poleNumber, slot)],
                            error: _imageErrors[
                                _imageKey(pole.poleNumber, slot)],
                            onImageChanged: (image) {
                              if (image == null) {
                                images.remove(slot);
                              } else {
                                images[slot] = image;
                              }
                              setDialogState(() {});
                            },
                            onUpload: (image) async {
                              await _uploadPoleImage(
                                pole: pole,
                                slot: slot,
                                image: image,
                                refreshDialog: () => setDialogState(() {}),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 4),
                      const Text(
                        'Images are uploaded to the backend and linked to this exact pole number.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildImageSlot({
    required BuildContext context,
    required Pole pole,
    required int slot,
    required XFile? image,
    required bool uploading,
    required String? uploadedUrl,
    required String? error,
    required ValueChanged<XFile?> onImageChanged,
    required Future<void> Function(XFile image) onUpload,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 86,
                height: 70,
                child: image == null
                    ? const Icon(
                        Icons.add_a_photo_outlined,
                        color: Color(0xFF64748B),
                        size: 28,
                      )
                    : FutureBuilder<List<int>>(
                        future: image.readAsBytes(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              Uint8List.fromList(snapshot.data!),
                              fit: BoxFit.cover,
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Image $slot',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Take photo',
                icon: const Icon(
                  Icons.camera_alt_outlined,
                  color: Color(0xFF38BDF8),
                ),
                onPressed: uploading
                    ? null
                    : () async {
                        final picked = await _imagePicker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 85,
                        );
                        if (picked != null) onImageChanged(picked);
                      },
              ),
              IconButton(
                tooltip: 'Choose from gallery',
                icon: const Icon(
                  Icons.photo_library_outlined,
                  color: Color(0xFF94A3B8),
                ),
                onPressed: uploading
                    ? null
                    : () async {
                        final picked = await _imagePicker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                        );
                        if (picked != null) onImageChanged(picked);
                      },
              ),
              if (image != null)
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFF43F5E),
                  ),
                  onPressed: uploading ? null : () => onImageChanged(null),
                ),
            ],
          ),
          if (image != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: uploading ? null : () => onUpload(image),
                icon: uploading
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined, size: 17),
                label: Text(uploading ? 'Uploading...' : 'Save Image $slot'),
              ),
            ),
          ],
          if (uploadedUrl != null) ...[
            const SizedBox(height: 5),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle,
                  color: Color(0xFF10B981),
                  size: 15,
                ),
                SizedBox(width: 5),
                Text(
                  'Uploaded successfully',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 5),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFF43F5E),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showIoTPoleDetails(Pole pole) async {
    if (!_isBackendOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backend is offline. Schnell IoT data is unavailable.'),
        ),
      );
      return;
    }

    setState(() {
      _loadingIoTPole = pole.poleNumber;
    });

    final iotPole = await ApiService.fetchSchnellIoTPole(
      pole.poleNumber,
    );

    if (!mounted) return;

    setState(() {
      _loadingIoTPole = null;
    });

    if (iotPole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pole ${pole.poleNumber} was not found in Schnell IoT.',
          ),
        ),
      );
      return;
    }

    final lampProfiles = iotPole['lamp_profiles'];
    final lampText = lampProfiles is List && lampProfiles.isNotEmpty
        ? lampProfiles
            .map((profile) {
              if (profile is Map) {
                final type = profile['type'] ?? 'Unknown';
                final watts = profile['watts'];
                return watts == null ? '$type' : '$type ($watts W)';
              }
              return profile.toString();
            })
            .join(', ')
        : 'No lamp profile available';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Schnell IoT Pole Details',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIoTDetailRow('Pole Number', pole.poleNumber),
              _buildIoTDetailRow(
                'ThingsBoard ID',
                iotPole['id']?.toString() ?? 'Unavailable',
              ),
              _buildIoTDetailRow(
                'Entity Type',
                iotPole['entity_type']?.toString() ?? 'Unavailable',
              ),
              _buildIoTDetailRow('Lamp Profile', lampText),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIoTDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGoogleMaps(String url) async {
    final Uri uri = Uri.parse(url);

    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not launch Google Maps for $url',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 4,
        centerTitle: true,
        title: Column(
          children: [
            const Text(
              'BBMP PENDING POLES',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isBackendOnline
                      ? Icons.bolt
                      : Icons.storage_outlined,
                  size: 12,
                  color: _isBackendOnline
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 4),
                Text(
                  _isBackendOnline
                      ? 'Backend Connected'
                      : 'Backend Unavailable',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _isBackendOnline
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Connection',
            icon: const Icon(
              Icons.refresh,
              color: Color(0xFF38BDF8),
            ),
            onPressed: _initDataAndCheckBackend,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFilterCard(),
              const SizedBox(height: 16),
              if (_filteredPoles.isNotEmpty)
                _buildResultsSummaryBar(),
              const SizedBox(height: 12),
              _buildTableSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF334155),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'FILTER HIERARCHY',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(
                  Icons.clear_all,
                  size: 16,
                  color: Color(0xFFF43F5E),
                ),
                label: const Text(
                  'Clear Filters',
                  style: TextStyle(
                    color: Color(0xFFF43F5E),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Region & Zone
          Row(
            children: [
              Expanded(
                child: _buildDropdownField<String>(
                  label: 'Region',
                  value: _selectedRegion,
                  hint: 'Select Region',
                  items: _regions
                  .map(
                    (region) => DropdownMenuItem<String>(
                      value: region,
                      child: Text(
                        region.trim().toUpperCase() == 'BOMMANAHALLI'
                            ? 'Bommanahalli'
                            : region.trim().toUpperCase() == 'EAST'
                                ? 'East'
                                : region,
                      ),
                    ),
                  )
                  .toList(),
                  onChanged: _onRegionChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField<String>(
                  label: 'Zone',
                  value: _selectedZone,
                  hint: _selectedRegion == null
                      ? 'Select Region First'
                      : _loadingZones
                          ? 'Loading Zones...'
                          : _zoneLoadError != null
                              ? _zoneLoadError!
                              : 'Select Zone',
                  enabled:
                      _selectedRegion != null &&
                          !_loadingZones &&
                          _zones.isNotEmpty,
                  items: _zones
                      .map(
                        (zone) => DropdownMenuItem(
                          value: zone,
                          child: Text(zone),
                        ),
                      )
                      .toList(),
                  onChanged: _onZoneChanged,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Ward & Pole With Old Lamp
          Row(
            children: [
              Expanded(
                child: _buildDropdownField<String>(
                  label: 'Ward',
                  value: _selectedWard,
                  hint: _selectedZone == null
                      ? 'Select Zone First'
                      : 'Select Ward',
                  enabled:
                      _selectedZone != null &&
                          _wards.isNotEmpty,
                  items: _wards
                      .map(
                        (ward) => DropdownMenuItem(
                          value: ward,
                          child: Text(ward),
                        ),
                      )
                      .toList(),
                  onChanged: _onWardChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField<String>(
                  label: 'Pole With Old Lamp',
                  value: _selectedPoleOldLamp,
                  hint: 'Select Classification',
                  items: const [
                    DropdownMenuItem(
                      value: 'LED',
                      child: Text('LED'),
                    ),
                    DropdownMenuItem(
                      value: 'Non-LED',
                      child: Text('Non-LED'),
                    ),
                    DropdownMenuItem(
                      value: 'Empty',
                      child: Text('Empty'),
                    ),
                  ],
                  onChanged: _onPoleOldLampChanged,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Lamp Type
          _buildDropdownField<String>(
            label: 'Lamp Type',
            value: _selectedLampType,
            hint: _selectedPoleOldLamp == null
                ? 'Select Pole With Old Lamp First'
                : 'Select Lamp Type',
            enabled:
                _selectedPoleOldLamp != null &&
                    _lampTypes.isNotEmpty,
            items: _lampTypes
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  ),
                )
                .toList(),
            onChanged: _onLampTypeChanged,
          ),

          const SizedBox(height: 12),

          // Starting Pole
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Starting Pole (Geographical Proximity Reference)',
                style: TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: !_loadingPoles && _filteredPoles.isNotEmpty
                    ? _showStartingPolePicker
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _filteredPoles.isNotEmpty
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _filteredPoles.isNotEmpty
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF334155),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedStartingPole ??
                              (_loadingPoles
                                  ? 'Loading ${_filteredPoles.isEmpty ? 'pending poles' : 'updated poles'}...'
                                  : (_filteredPoles.isEmpty
                                      ? 'No Pending Poles Available'
                                      : 'Select Starting Pole to Order Nearest â†’ Farthest')),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _selectedStartingPole != null
                                ? Colors.white
                                : const Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_loadingPoles)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF38BDF8),
                          ),
                        )
                      else
                        const Icon(
                          Icons.search,
                          color: Color(0xFF38BDF8),
                          size: 19,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    bool enabled = true,
    Color? accentColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: enabled
                ? (accentColor ??
                    const Color(0xFFCBD5E1))
                : const Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled
                ? const Color(0xFF0F172A)
                : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? (accentColor ??
                      const Color(0xFF475569))
                  : const Color(0xFF334155),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: Text(
                hint,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                ),
              ),
              isExpanded: true,
              dropdownColor:
                  const Color(0xFF1E293B),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
              items: enabled ? items : [],
              onChanged:
                  enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsSummaryBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              const Color(0xFF38BDF8).withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pin_drop,
                color: Color(0xFF38BDF8),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Filtered Pending Poles: ${_filteredPoles.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (_selectedStartingPole != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0369A1),
                borderRadius:
                    BorderRadius.circular(20),
              ),
              child: Text(
                'Start: $_selectedStartingPole',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableSection() {
    if (_loadingPoles) {
      return _buildInstructionState(
        icon: Icons.sync,
        message:
            'Loading live pending poles from Schnell IoTâ€¦\nPlease wait.',
      );
    }

    if (_selectedRegion == null) {
      return _buildInstructionState(
        icon: Icons.filter_alt_outlined,
        message:
            'Please select a Region (e.g. East, Bommanahalli) to begin filtering pending poles.',
      );
    }

    if (_filteredPoles.isEmpty) {
      return _buildInstructionState(
        icon: Icons.search_off,
        message:
            'No pending poles match your selected filtering criteria.',
      );
    }

    if (_selectedStartingPole == null) {
      return _buildInstructionState(
        icon: Icons.near_me,
        message:
            'Select a Starting Pole above to calculate distance-based ordering.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF334155),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          // Table Header
          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF334155),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '#',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'POLE NO.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'DISTANCE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'IMAGES',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: AlignmentTextRight(
                    'LOCATION',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Table Rows
          SizedBox(
            height: 520,
            child: ListView.separated(
            itemCount: _orderedPoles.length,
            separatorBuilder:
                (context, index) =>
                    const Divider(
              height: 1,
              color: Color(0xFF334155),
            ),
            itemBuilder:
                (context, index) {
              final pole =
                  _orderedPoles[index];

              final isStartingPole =
                  pole.poleNumber ==
                      _selectedStartingPole;

              return Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                color: isStartingPole
                    ? const Color(0xFF0284C7)
                        .withOpacity(0.15)
                    : null,
                child: Row(
                  children: [
                    // Order #
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${pole.order}',
                        style: TextStyle(
                          color: isStartingPole
                              ? const Color(
                                  0xFF38BDF8)
                              : const Color(
                                  0xFF94A3B8),
                          fontWeight:
                              FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),

                    // Pole Number
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () => _showIoTPoleDetails(pole),
                            borderRadius: BorderRadius.circular(4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    pole.poleNumber,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                if (_loadingIoTPole == pole.poleNumber)
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.bolt,
                                    color: Color(0xFF10B981),
                                    size: 14,
                                  ),
                              ],
                            ),
                          ),
                          if (isStartingPole) ...[
                            const SizedBox(
                              width: 4,
                            ),
                            const Icon(
                              Icons.star,
                              color:
                                  Color(0xFFF59E0B),
                              size: 14,
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Distance
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        alignment:
                            Alignment.centerLeft,
                        child: Text(
                          pole.distanceFormatted,
                          style: TextStyle(
                            color:
                                pole.distanceMeters ==
                                        0
                                    ? const Color(
                                        0xFF34D399)
                                    : const Color(
                                        0xFFE2E8F0),
                            fontWeight:
                                pole.distanceMeters ==
                                        0
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),

                    // Technician Images
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.center,
                        child: InkWell(
                          onTap: () => _showPoleImages(pole),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF38BDF8),
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              color: Color(0xFF38BDF8),
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Google Maps
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment:
                            Alignment.centerRight,
                        child: InkWell(
                          onTap: () =>
                              _openGoogleMaps(
                            pole.googleMapsUrl,
                          ),
                          borderRadius:
                              BorderRadius.circular(
                            6,
                          ),
                          child: Container(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration:
                                BoxDecoration(
                              color:
                                  const Color(
                                0xFF0F172A,
                              ),
                              borderRadius:
                                  BorderRadius
                                      .circular(6),
                              border: Border.all(
                                color:
                                    const Color(
                                  0xFF38BDF8,
                                ).withOpacity(0.5),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize:
                                  MainAxisSize.min,
                              children: [
                                Text(
                                  'ðŸ“',
                                  style:
                                      TextStyle(
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(
                                  width: 4,
                                ),
                                Text(
                                  'Map',
                                  style:
                                      TextStyle(
                                    color:
                                        Color(
                                      0xFF38BDF8,
                                    ),
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionState({
    required IconData icon,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF334155),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: const Color(0xFF64748B),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class AlignmentTextRight extends StatelessWidget {
  final String text;
  final TextStyle style;

  const AlignmentTextRight(
    this.text, {
    super.key,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        text,
        style: style,
      ),
    );
  }
}

