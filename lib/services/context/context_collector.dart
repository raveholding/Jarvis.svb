import 'dart:async';
import 'dart:math' as math;

import 'package:device_calendar/device_calendar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/context_snapshot.dart';

/// Reúne GPS + movimiento + agenda con caché agresiva para cuidar batería.
class ContextCollector {
  final DeviceCalendarPlugin _calendar = DeviceCalendarPlugin();
  StreamSubscription<UserAccelerometerEvent>? _accelSub;

  double _motionEnergy = 0;
  Position? _lastPosition;
  DateTime? _lastFixAt;
  List<CalendarItem> _calendarCache = const [];
  DateTime? _calendarAt;

  bool locationEnabled = false;
  bool calendarEnabled = false;

  void startSensors() {
    _accelSub ??= userAccelerometerEventStream(samplingPeriod: SensorInterval.normalInterval).listen(
      (e) {
        final m = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
        _motionEnergy = _motionEnergy * 0.9 + m * 0.1; // media móvil exponencial
      },
      onError: (Object e) => JLog.e('ctx', e),
    );
  }

  Future<void> stopSensors() async {
    await _accelSub?.cancel();
    _accelSub = null;
  }

  Future<ContextSnapshot> snapshot() async {
    final now = DateTime.now();
    final pos = await _position();
    final speed = pos == null || pos.speed < 0 ? null : pos.speed * 3.6;
    final events = await _upcomingEvents(now);
    return ContextSnapshot(
      now: now,
      latitude: pos?.latitude,
      longitude: pos?.longitude,
      speedKmh: speed,
      motion: _classifyMotion(speed),
      upcoming: events,
    );
  }

  String _classifyMotion(double? speedKmh) {
    if (speedKmh != null && speedKmh > 18) return 'en_vehiculo';
    if (_accelSub == null) return 'desconocido';
    if (_motionEnergy > 1.2) return 'caminando';
    if (_motionEnergy < 0.25) return 'quieto';
    return 'en_movimiento_leve';
  }

  Future<Position?> _position() async {
    if (!locationEnabled) return null;
    final fresh = _lastFixAt != null && DateTime.now().difference(_lastFixAt!) < const Duration(minutes: 2);
    if (fresh) return _lastPosition;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      _lastPosition = pos;
      _lastFixAt = DateTime.now();
      return pos;
    } catch (_) {
      try {
        return _lastPosition ?? await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<CalendarItem>> _upcomingEvents(DateTime now) async {
    if (!calendarEnabled) return const [];
    if (_calendarAt != null && now.difference(_calendarAt!) < const Duration(minutes: 10)) {
      return _calendarCache;
    }
    try {
      final cals = await _calendar.retrieveCalendars();
      final items = <CalendarItem>[];
      for (final cal in cals.data ?? const <Calendar>[]) {
        final id = cal.id;
        if (id == null) continue;
        final res = await _calendar.retrieveEvents(
          id,
          RetrieveEventsParams(
            startDate: now.subtract(const Duration(hours: 1)),
            endDate: now.add(const Duration(hours: 12)),
          ),
        );
        for (final e in res.data ?? const <Event>[]) {
          final start = e.start;
          if (start == null || (e.allDay ?? false)) continue;
          items.add(CalendarItem(
            title: (e.title ?? 'Evento').trim(),
            start: start.toLocal(),
            end: e.end?.toLocal(),
            location: e.location,
          ));
        }
      }
      items.sort((a, b) => a.start.compareTo(b.start));
      _calendarCache = items;
      _calendarAt = now;
      return items;
    } catch (e) {
      JLog.e('ctx', e);
      return _calendarCache;
    }
  }
}
