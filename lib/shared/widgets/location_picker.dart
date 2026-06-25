import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../design_tokens.dart';
import '../i18n.dart';

class LocationPicker extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final ValueChanged<LatLng> onChanged;
  final double height;

  const LocationPicker({
    super.key,
    this.initialLat,
    this.initialLng,
    required this.onChanged,
    this.height = 220,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late final MapController _mapCtrl;
  LatLng? _marker;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    if (widget.initialLat != null && widget.initialLng != null) {
      _marker = LatLng(widget.initialLat!, widget.initialLng!);
    }
  }

  LatLng get _center =>
      _marker ?? const LatLng(-6.7924, 39.2083); // Default: Dar es Salaam

  Future<void> _getCurrentLocation() async {
    setState(() => _locating = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('ownerReg.locationDenied'))),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final latlng = LatLng(pos.latitude, pos.longitude);
      setState(() => _marker = latlng);
      _mapCtrl.move(latlng, 15);
      widget.onChanged(latlng);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ownerReg.locationError'))),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onTap(TapPosition tapPosition, LatLng latlng) {
    setState(() => _marker = latlng);
    widget.onChanged(latlng);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('ownerReg.mapHint'),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 13,
                    onTap: _onTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.fitflex.mobile',
                    ),
                    if (_marker != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _marker!,
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_pin,
                              color: Theme.of(context).colorScheme.primary,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'location_picker_gps',
                    onPressed: _locating ? null : _getCurrentLocation,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    child: _locating
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.my_location,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_marker != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${_marker!.latitude.toStringAsFixed(5)}, ${_marker!.longitude.toStringAsFixed(5)}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }
}
