import 'dart:typed_data';

enum TipoNotificacion { personal, boleta }

enum PersonaNotificada {
  personaNatural,
  familiar,
  representanteLegal,
  trabajador,
}

extension TipoNotificacionX on TipoNotificacion {
  String get value => this == TipoNotificacion.personal ? 'personal' : 'boleta';

  String get label => this == TipoNotificacion.personal ? 'Personal' : 'Por boleta';
}

extension PersonaNotificadaX on PersonaNotificada {
  String get value {
    switch (this) {
      case PersonaNotificada.personaNatural:
        return 'persona_natural';
      case PersonaNotificada.familiar:
        return 'familiar';
      case PersonaNotificada.representanteLegal:
        return 'representante_legal';
      case PersonaNotificada.trabajador:
        return 'trabajador';
    }
  }

  String get label {
    switch (this) {
      case PersonaNotificada.personaNatural:
        return 'Persona natural';
      case PersonaNotificada.familiar:
        return 'Familiar';
      case PersonaNotificada.representanteLegal:
        return 'Representante legal';
      case PersonaNotificada.trabajador:
        return 'Trabajador';
    }
  }
}

class EncuestaLlegada {
  const EncuestaLlegada({
    required this.tipoNotificacion,
    required this.personaNotificada,
    required this.descripcionDiligencia,
    required this.fotoRegistroBytes,
    required this.fotoRegistroSecundariaBytes,
    this.nombreFamiliarTrabajador,
    this.cedulaFamiliarTrabajador,
  });

  final TipoNotificacion tipoNotificacion;
  final PersonaNotificada personaNotificada;
  final String descripcionDiligencia;
  final Uint8List fotoRegistroBytes;
  final Uint8List fotoRegistroSecundariaBytes;
  final String? nombreFamiliarTrabajador;
  final String? cedulaFamiliarTrabajador;
}

