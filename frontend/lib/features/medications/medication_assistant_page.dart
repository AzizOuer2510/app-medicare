import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'medication.dart';
import 'medication_assistant.dart';

Future<void> showMedicationAssistantPanel(BuildContext context) {
  final screenSize = MediaQuery.sizeOf(context);
  final panelWidth = screenSize.width < 460
      ? screenSize.width * .92
      : 420.0;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fermer l’assistant de traitement',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: panelWidth,
        height: screenSize.height,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(22),
          ),
          child: MedicationAssistantPage(
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final slide = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(
        position: animation.drive(slide),
        child: child,
      );
    },
  );
}

class MedicationAssistantPage extends ConsumerStatefulWidget {
  const MedicationAssistantPage({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  ConsumerState<MedicationAssistantPage> createState() =>
      _MedicationAssistantPageState();
}

class _MedicationAssistantPageState
    extends ConsumerState<MedicationAssistantPage> {
  final _controller = TextEditingController();
  final _assistant = const MedicationAssistant();
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      text: 'Bonjour ! Je peux vous aider à organiser vos traitements, '
          'expliquer les champs d’une prescription et retrouver les informations '
          'enregistrées dans votre dossier.',
      fromAssistant: true,
    ),
  ];
  List<Medication> _medications = const [];
  List<Prescription> _prescriptions = const [];
  bool _loading = true;
  bool _sending = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final responses = await Future.wait([
        dio.get('/medications'),
        dio.get('/prescriptions'),
      ]);
      if (!mounted) return;
      setState(() {
        _medications = _asList(responses[0].data)
            .map(Medication.fromJson)
            .toList();
        _prescriptions = _asList(responses[1].data)
            .map(Prescription.fromJson)
            .toList()
          ..sort((a, b) => b.prescriptionDate.compareTo(a.prescriptionDate));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Impossible de charger vos informations enregistrées. '
            'Vous pouvez tout de même poser une question générale.';
      });
    }
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final value = data['items'] ?? data['medications'] ?? data['data'];
      if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
    }
    return const [];
  }

  void _send([String? suggestion]) {
    final question = (suggestion ?? _controller.text).trim();
    if (question.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _messages.add(_ChatMessage(text: question, fromAssistant: false));
      _controller.clear();
    });
    final response = _assistant.answer(
      question,
      medications: _medications,
      prescriptions: _prescriptions,
    );
    setState(() {
      _messages.add(_ChatMessage(text: response, fromAssistant: true));
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onClose == null
            ? null
            : IconButton(
                tooltip: 'Fermer',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
        title: const Text('Assistant traitement'),
        actions: [
          IconButton(
            tooltip: 'Actualiser les informations',
            onPressed: _loading ? null : _loadRecords,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: const Color(0xFFE9F7F6),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.privacy_tip_outlined, color: Color(0xFF087F83)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Assistant local : vos questions ne sont pas envoyées à '
                    'une IA externe. Il ne modifie pas vos traitements et ne '
                    'remplace pas un professionnel de santé.',
                    style: TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_loadError != null)
            MaterialBanner(
              content: Text(_loadError!),
              actions: [
                TextButton(onPressed: _loadRecords, child: const Text('Réessayer')),
              ],
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              children: [
                if (_messages.length == 1) ...[
                  const Text(
                    'Suggestions',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _suggestion('Comment organiser mes rappels ?'),
                      _suggestion('Que signifie le champ posologie ?'),
                      _suggestion('Quelles prescriptions sont enregistrées ?'),
                      if (_medications.isNotEmpty)
                        _suggestion(
                          'Quels sont les horaires de ${_medications.first.name} ?',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                for (final message in _messages)
                  _MessageBubble(message: message),
                if (_sending)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Écrivez votre question…',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestion(String text) => ActionChip(
        label: Text(text),
        onPressed: () => _send(text),
      );
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.fromAssistant});

  final String text;
  final bool fromAssistant;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final assistant = message.fromAssistant;
    return Align(
      alignment: assistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: assistant ? const Color(0xFFE9F7F6) : const Color(0xFF087F83),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(assistant ? 4 : 18),
            bottomRight: Radius.circular(assistant ? 18 : 4),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            height: 1.35,
            color: assistant ? const Color(0xFF173E42) : Colors.white,
          ),
        ),
      ),
    );
  }
}
