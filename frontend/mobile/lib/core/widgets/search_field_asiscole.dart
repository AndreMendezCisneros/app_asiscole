import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Campo de búsqueda estilo píldora (fondo claro, borde al tono de la lupa).
class SearchFieldAsiscole extends StatefulWidget {
  const SearchFieldAsiscole({
    super.key,
    required this.controller,
    this.hint = 'Buscar',
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  State<SearchFieldAsiscole> createState() => _SearchFieldAsiscoleState();
}

class _SearchFieldAsiscoleState extends State<SearchFieldAsiscole> {
  static const _radio = BorderRadius.all(Radius.circular(24));
  static const _bordeLupa = BorderSide(
    color: AppTheme.moradoSecundario,
    width: 1.2,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTexto);
  }

  @override
  void didUpdateWidget(covariant SearchFieldAsiscole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTexto);
      widget.controller.addListener(_onTexto);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTexto);
    super.dispose();
  }

  void _onTexto() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      cursorColor: AppTheme.moradoPrincipal,
      style: const TextStyle(color: AppTheme.texto, fontSize: 15),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: const TextStyle(color: AppTheme.textoSecundario),
        filled: true,
        fillColor: AppTheme.blanco,
        prefixIcon: const Icon(Icons.search, color: AppTheme.moradoSecundario),
        suffixIcon: widget.controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textoSecundario),
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged?.call('');
                },
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: const OutlineInputBorder(
          borderRadius: _radio,
          borderSide: _bordeLupa,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: _radio,
          borderSide: _bordeLupa,
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: _radio,
          borderSide: BorderSide(color: AppTheme.moradoPrincipal, width: 1.8),
        ),
      ),
    );
  }
}
