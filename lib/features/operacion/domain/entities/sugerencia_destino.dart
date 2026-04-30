class SugerenciaDestino {
  const SugerenciaDestino({
    required this.placeId,
    required this.descripcion,
    required this.textoPrincipal,
    this.textoSecundario,
  });

  factory SugerenciaDestino.fromAutocompleteJson(Map<String, dynamic> json) {
    final Map<String, dynamic> structured =
        json['structured_formatting'] as Map<String, dynamic>? ?? <String, dynamic>{};

    return SugerenciaDestino(
      placeId: (json['place_id'] as String? ?? '').trim(),
      descripcion: (json['description'] as String? ?? '').trim(),
      textoPrincipal: (structured['main_text'] as String? ?? '').trim(),
      textoSecundario: (structured['secondary_text'] as String?)?.trim(),
    );
  }

  final String placeId;
  final String descripcion;
  final String textoPrincipal;
  final String? textoSecundario;
}

