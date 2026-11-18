import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'health_api.dart';
import 'health_theme.dart';

/// NutriCoach : assistant nutritionnel IA (conversation).
class NutritionChatPage extends ConsumerStatefulWidget {
  const NutritionChatPage({super.key});

  @override
  ConsumerState<NutritionChatPage> createState() => _NutritionChatPageState();
}

class _Message {
  const _Message(this.text, {required this.fromUser, this.error = false});
  final String text;
  final bool fromUser;
  final bool error;
}

class _NutritionChatPageState extends ConsumerState<NutritionChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [
    const _Message(
      'Bonjour ! Je suis **NutriCoach**, votre assistant nutritionnel.\n\n'
      'Je peux vous aider à :\n• améliorer votre alimentation\n• planifier vos repas\n'
      '• comprendre les macronutriments\n• atteindre vos objectifs\n\n'
      'Que puis-je faire pour vous ?',
      fromUser: false,
    ),
  ];
  final List<Map<String, String>> _history = [];
  bool _sending = false;

  static const _suggestions = [
    'Que manger pour perdre du poids ?',
    'Aliments riches en protéines',
    'Idées de dîner léger',
    'Que manger avant le sport ?',
    'Collations saines',
    'Pourquoi bien s’hydrater ?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _messages.add(_Message(message, fromUser: true));
      _sending = true;
    });
    _scrollDown();
    try {
      final response = await aiDio(ref).post(
            '/nutrition/chat',
            data: {'message': message, 'history': _history},
          );
      final reply = asMap(response.data)['reply']?.toString() ?? 'Pas de réponse.';
      _history
        ..add({'role': 'user', 'content': message})
        ..add({'role': 'assistant', 'content': reply});
      if (_history.length > 20) _history.removeRange(0, _history.length - 20);
      if (!mounted) return;
      setState(() {
        _messages.add(_Message(reply, fromUser: false));
        _sending = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Message(healthErrorMessage(error), fromUser: false, error: true));
        _sending = false;
      });
    }
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealthColors.background,
      appBar: AppBar(
        backgroundColor: HealthColors.deepTeal,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: const Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: HealthColors.accent,
              child: Icon(Icons.eco_outlined, color: HealthColors.deepTeal),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NutriCoach',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text('Assistant nutritionnel IA',
                    style: TextStyle(fontSize: 12, color: HealthColors.heroText)),
              ],
            ),
          ],
        ),
      ),
      body: HealthBody(
        maxWidth: 760,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (_, i) => i == _messages.length
                    ? const _Bubble(
                        _Message('NutriCoach écrit…', fromUser: false),
                        typing: true)
                    : _Bubble(_messages[i]),
              ),
            ),
            if (_messages.length <= 1)
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final s in _suggestions)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(s),
                          onPressed: () => _send(s),
                          backgroundColor: Colors.white,
                          side: BorderSide(
                              color: HealthColors.brightTeal.withValues(alpha: .3)),
                        ),
                      ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        decoration: InputDecoration(
                          hintText: 'Posez une question nutritionnelle…',
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Envoyer',
                      style: IconButton.styleFrom(
                          backgroundColor: HealthColors.brightTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(14)),
                      onPressed: _sending ? null : () => _send(_input.text),
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.message, {this.typing = false});

  final _Message message;
  final bool typing;

  @override
  Widget build(BuildContext context) {
    final user = message.fromUser;
    final background = message.error
        ? const Color(0xFFFDECEE)
        : user
            ? HealthColors.brightTeal
            : Colors.white;
    final color = message.error
        ? const Color(0xFFB3261E)
        : user
            ? Colors.white
            : HealthColors.ink;
    return Padding(
      padding: EdgeInsets.only(
          bottom: 10, left: user ? 48 : 0, right: user ? 0 : 48),
      child: Row(
        mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!user) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: HealthColors.accent,
              child: Icon(Icons.eco_outlined, size: 16, color: HealthColors.deepTeal),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(user ? 18 : 4),
                  bottomRight: Radius.circular(user ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .04),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: typing
                  ? const SizedBox(
                      width: 40,
                      child: LinearProgressIndicator(color: HealthColors.brightTeal),
                    )
                  : _richText(message.text, color),
            ),
          ),
        ],
      ),
    );
  }

  /// Gère le gras Markdown simple (**texte**).
  Widget _richText(String text, Color color) {
    final parts = text.split('**');
    return SelectableText.rich(
      TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: TextStyle(
                color: color,
                height: 1.4,
                fontWeight: i.isOdd ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }
}
