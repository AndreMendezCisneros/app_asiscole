import 'package:flutter/material.dart';

import '../theme/asis_colors.dart';

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
    final bordeLupa = BorderSide(color: context.asis.moradoSecundario, width: 1.2);
    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      cursorColor: context.asis.morado,
      style: TextStyle(color: context.asis.texto, fontSize: 15),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(color: context.asis.textoSecundario),
        filled: true,
        fillColor: context.asis.superficie,
        prefixIcon: Icon(Icons.search, color: context.asis.moradoSecundario),
        suffixIcon: widget.controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, color: context.asis.textoSecundario),
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged?.call('');
                },
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: _radio,
          borderSide: bordeLupa,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: _radio,
          borderSide: bordeLupa,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: _radio,
          borderSide: BorderSide(color: context.asis.morado, width: 1.8),
        ),
      ),
    );
  }
}
