import 'package:intl/intl.dart';

class CalendarItem {
  const CalendarItem({required this.title, required this.start, this.end, this.location});

  final String title;
  final DateTime start;
  final DateTime? end;
  final String? location;

  bool isHappeningAt(DateTime t) =>
      !start.isAfter(t) && (end == null ? t.difference(start).inMinutes < 60 : end!.isAfter(t));

  Map<String, dynamic> toJson() => {
        'title': title,
        'start': DateFormat('HH:mm').format(start),
        if (end != null) 'end': DateFormat('HH:mm').format(end!),
        if (location != null && location!.isNotEmpty) 'location': location,
      };
}

/// Fotografía del contexto en el instante de evaluar una interrupción.
class ContextSnapshot {
  const ContextSnapshot({
    required this.now,
    this.latitude,
    this.longitude,
    this.speedKmh,
    this.motion = 'desconocido',
    this.upcoming = const [],
  });

  final DateTime now;
  final double? latitude;
  final double? longitude;
  final double? speedKmh;

  /// quieto | caminando | en_vehiculo | desconocido
  final String motion;
  final List<CalendarItem> upcoming;

  bool get isDriving => motion == 'en_vehiculo';
  CalendarItem? get currentEvent {
    for (final e in upcoming) {
      if (e.isHappeningAt(now)) return e;
    }
    return null;
  }

  bool get inMeeting => currentEvent != null;

  static const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

  Map<String, dynamic> toPromptJson() => {
        'fecha_hora': DateFormat('yyyy-MM-dd HH:mm').format(now),
        'dia_semana': _days[now.weekday - 1],
        'movimiento': motion,
        if (speedKmh != null) 'velocidad_kmh': speedKmh!.round(),
        if (latitude != null && longitude != null)
          'ubicacion': {'lat': double.parse(latitude!.toStringAsFixed(3)), 'lng': double.parse(longitude!.toStringAsFixed(3))},
        'en_reunion': inMeeting,
        if (currentEvent != null) 'evento_actual': currentEvent!.title,
        'agenda_proxima': upcoming.where((e) => e.start.isAfter(now)).take(5).map((e) => e.toJson()).toList(),
      };
}
