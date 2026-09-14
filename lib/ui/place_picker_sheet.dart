import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../main.dart';
import 'sheet.dart';
import 'theme.dart';

/// What the picker hands back.
class PickedPlace {
  const PickedPlace({required this.centre, required this.radiusMeters});

  final GeoPoint centre;
  final double radiusMeters;
}

/// Pick the zone for a place condition on a map.
///
/// OpenStreetMap tiles rather than Google Maps: no API key, no billing account,
/// and no third party learning which places someone is trying to build a habit
/// around. Tiles are fetched only while this sheet is open.
///
/// The map is a convenience, not a requirement. Tiles need a network, so the
/// "use my location" button and the plain coordinates stay usable when the
/// tiles do not load at all.
class PlacePickerSheet extends StatefulWidget {
  const PlacePickerSheet({
    required this.initialCentre,
    required this.initialRadius,
    super.key,
  });

  final GeoPoint? initialCentre;
  final double initialRadius;

  static Future<PickedPlace?> show(
    BuildContext context, {
    GeoPoint? centre,
    required double radius,
  }) {
    return showModalBottomSheet<PickedPlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => PlacePickerSheet(
        initialCentre: centre,
        initialRadius: radius,
      ),
    );
  }

  @override
  State<PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends State<PlacePickerSheet> {
  final _map = MapController();

  late LatLng _centre;
  late double _radius;
  bool _locating = false;
  bool _hasFix = false;

  /// Somewhere neutral, used only until a real position arrives. Zoomed out, so
  /// it reads as "no location yet" rather than as a wrong answer.
  static const _fallback = LatLng(20, 0);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCentre;
    _centre = initial == null
        ? _fallback
        : LatLng(initial.latitude, initial.longitude);
    _hasFix = initial != null;
    _radius = widget.initialRadius;

    if (initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToMyLocation());
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    final store = StoreScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _locating = true);
    final reading = await store.currentLocation();
    if (!mounted) return;

    setState(() {
      _locating = false;
      if (reading != null) {
        _centre = LatLng(reading.point.latitude, reading.point.longitude);
        _hasFix = true;
      }
    });

    if (reading == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No location fix yet. You can still drop a pin.'),
        ),
      );
      return;
    }
    _map.move(_centre, 16);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Column(
        children: [
            const SheetGrabber(),
          _header(),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _centre,
                    initialZoom: _hasFix ? 16 : 2,
                    // Tapping moves the pin; that is the whole interaction.
                    onTap: (_, point) => setState(() {
                      _centre = point;
                      _hasFix = true;
                    }),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      // The OSM tile policy requires an identifying agent.
                      userAgentPackageName: 'com.example.control',
                      maxZoom: 19,
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _centre,
                          radius: _radius,
                          useRadiusInMeter: true,
                          color: colors.light.withValues(alpha: 0.18),
                          borderColor: colors.light,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _centre,
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.place,
                            size: 36,
                            color: colors.heavy,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'place-picker-locate',
                    onPressed: _locating ? null : _goToMyLocation,
                    child: _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: colors.background.withValues(alpha: 0.7),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 9, color: colors.textMuted),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _controls(),
        ],
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const Spacer(),
            const Text(
              'Pick the place',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: _hasFix
                  ? () => Navigator.pop(
                        context,
                        PickedPlace(
                          centre: GeoPoint(
                            _centre.latitude,
                            _centre.longitude,
                          ),
                          radiusMeters: _radius,
                        ),
                      )
                  : null,
              child: const Text('Save'),
            ),
          ],
        ),
      );

  Widget _controls() {
    final colors = ControlColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      color: colors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _hasFix
                ? 'Tap the map to move the pin'
                : 'Tap the map to drop a pin, or use the location button',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            'Within ${_radius.round()} m',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Slider(
            value: _radius,
            min: 50,
            max: 500,
            divisions: 18,
            label: '${_radius.round()} m',
            onChanged: (value) => setState(() => _radius = value),
          ),
          Text(
            'A tight radius is the point of the habit, but GPS needs room to be '
            'sure. Below about 100 m a check-in often fails outdoors, and almost '
            'always indoors.',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          if (_hasFix) ...[
            const SizedBox(height: 10),
            SelectableText(
              '${_centre.latitude.toStringAsFixed(5)}, '
              '${_centre.longitude.toStringAsFixed(5)}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
