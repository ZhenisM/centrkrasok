import 'package:flutter/material.dart';
import 'package:centrkrasok/catalog/search/search_screen.dart';

/// Компактная строка поиска в AppBar каталога.
/// В свёрнутом виде — маленькая иконка. При нажатии открывает SearchScreen.
class CatalogSearchBar extends StatelessWidget {
  const CatalogSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      ),
      child: Container(
        width: 140,
        height: 36,
        margin: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, color: Colors.white70, size: 18),
            SizedBox(width: 4),
            Text('Поиск', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Оригинальный AnimatedSearchBar — анимированное поле ввода в AppBar.
/// Используется в client_cabinet_screen и client_orders_screen.
class AnimatedSearchBar extends StatefulWidget {
  const AnimatedSearchBar({super.key, this.onChanged});
  final ValueChanged<String>? onChanged;

  @override
  State<AnimatedSearchBar> createState() => _AnimatedSearchBarState();
}

class _AnimatedSearchBarState extends State<AnimatedSearchBar>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _animCtrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _focus.addListener(() {
      if (!_focus.hasFocus && _ctrl.text.isEmpty) _collapse();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _expanded = true);
    _animCtrl.forward();
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _focus.requestFocus();
    });
  }

  void _collapse() {
    _focus.unfocus();
    _ctrl.clear();
    widget.onChanged?.call('');
    _animCtrl.reverse().then((_) {
      if (mounted) setState(() => _expanded = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width - 60;
    const minW = 120.0;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final w = minW + (maxW - minW) * _anim.value;
        return SizedBox(
          width: w,
          child: GestureDetector(
            onTap: _expanded ? null : _expand,
            child: Container(
              height: 36,
              margin: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              decoration: BoxDecoration(
                color: _expanded
                    ? Colors.white.withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _expanded
                  ? Row(children: [
                      const SizedBox(width: 10),
                      const Icon(Icons.search, color: Colors.grey, size: 18),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          style: const TextStyle(color: Colors.black87, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Поиск',
                            hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: widget.onChanged,
                        ),
                      ),
                      GestureDetector(
                        onTap: _collapse,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.close, color: Colors.grey, size: 16),
                        ),
                      ),
                    ])
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, color: Colors.white70, size: 18),
                        SizedBox(width: 4),
                        Text('Поиск', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
