import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/widgets/care_workspace.dart';
import '../providers/document_repository.dart';

class DocumentSharesPage extends StatefulWidget {
  const DocumentSharesPage({
    super.key,
    required this.document,
    required this.repository,
  });
  final Map<String, dynamic> document;
  final DocumentRepository repository;
  @override
  State<DocumentSharesPage> createState() => _DocumentSharesPageState();
}

class _DocumentSharesPageState extends State<DocumentSharesPage> {
  final _label = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _shares = [];
  Map<String, dynamic>? _created;
  bool _loading = true, _busy = false, _refreshing = false;
  String? _error;
  int _duration = 15;
  int _revision = 0;
  Timer? _timer;
  int get _documentId => widget.document['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true && !_busy) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _label.dispose();
    super.dispose();
  }

  String _message(Object error) =>
      error is DioException && error.response?.data is Map
      ? error.response!.data['message']?.toString() ?? 'Action impossible.'
      : 'Impossible de joindre le serveur. Réessayez.';

  Future<void> _load() async {
    if (_refreshing) return;
    _refreshing = true;
    final revision = _revision;
    try {
      final shares = await widget.repository.shares(_documentId);
      if (!mounted || revision != _revision) return;
      setState(() {
        _shares = shares;
        _error = null;
        if (_created != null) {
          final id = (_created!['share'] as Map)['id'];
          final current = shares
              .where((share) => share['id'] == id)
              .firstOrNull;
          if (current == null || _status(current) != 'ACTIVE') _created = null;
        }
      });
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = _message(error));
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  String _status(Map<String, dynamic> share) {
    if (share['status'] == 'REVOKED') return 'REVOKED';
    if (!DateTime.parse(share['expiresAt'] as String).isAfter(DateTime.now())) {
      return 'EXPIRED';
    }
    return share['status'] as String;
  }

  Future<void> _create() async {
    if (_busy || !_form.currentState!.validate()) return;
    ++_revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.createShare(
        _documentId,
        durationMinutes: _duration,
        label: _label.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _created = result;
        _shares.insert(0, Map<String, dynamic>.from(result['share'] as Map));
      });
      _label.clear();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Révoquer ce partage ?'),
        content: const Text(
          'Le lien et le QR code ne permettront plus d’obtenir le document. Les copies déjà téléchargées restent chez le destinataire.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conserver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    ++_revision;
    setState(() => _busy = true);
    try {
      await widget.repository.revokeShare(_documentId, share['id'] as int);
      if (!mounted) return;
      setState(() {
        share['status'] = 'REVOKED';
        if ((_created?['share'] as Map?)?['id'] == share['id']) _created = null;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Partage révoqué.')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _history(Map<String, dynamic> share) => showDialog<void>(
    context: context,
    builder: (context) => Theme(
      data: careTheme(context),
      child: _ShareHistory(
        share: share,
        load: () =>
            widget.repository.shareAccesses(_documentId, share['id'] as int),
      ),
    ),
  );

  Future<void> _copy(String value, String message) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Copie impossible. Sélectionnez le texte pour le copier.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: careTheme(context),
    child: Scaffold(
      backgroundColor: CareColors.canvas,
      appBar: AppBar(
        title: const Text('Partage sécurisé'),
        actions: [
          IconButton(
            tooltip: 'Actualiser les partages',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CareHero(
                  eyebrow: 'DOCUMENTS · PARTAGE PAR QR CODE',
                  title: 'Partagez en confiance.',
                  description:
                      'Un accès temporaire à votre document, protégé par un code PIN. Vous décidez quand il prend fin.',
                  icon: Icons.qr_code_2_rounded,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      color: CareColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.document['title'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: CareError(message: _error!, onRetry: _load),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compose =
                        _created == null ||
                            _status(
                                  Map<String, dynamic>.from(
                                    _created!['share'] as Map,
                                  ),
                                ) !=
                                'ACTIVE'
                        ? _createPanel()
                        : _qrPanel();
                    final history = _sharesPanel();
                    if (constraints.maxWidth < 800) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          compose,
                          const SizedBox(height: 20),
                          history,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: compose),
                        const SizedBox(width: 24),
                        Expanded(child: history),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _createPanel() => CarePanel(
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Créer un accès temporaire',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Le destinataire ouvre le document dans son navigateur, sans créer de compte.',
            style: TextStyle(color: CareColors.muted, height: 1.6),
          ),
          const SizedBox(height: 24),
          TextFormField(
            key: const ValueKey('share-label'),
            controller: _label,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Nom du partage (facultatif)',
              hintText: 'Ex. Consultation Dr Martin',
            ),
            validator: (value) => (value?.trim().length ?? 0) > 80
                ? '80 caractères maximum.'
                : null,
          ),
          const SizedBox(height: 16),
          const Text(
            'Durée de validité',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in {
                15: '15 minutes',
                60: '1 heure',
                1440: '24 heures',
              }.entries)
                ChoiceChip(
                  label: Text(option.value),
                  selected: _duration == option.key,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _duration = option.key),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const _SecurityNote(),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('create-share'),
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Générer le QR code'),
          ),
        ],
      ),
    ),
  );

  Widget _qrPanel() {
    final created = _created!;
    final share = Map<String, dynamic>.from(created['share'] as Map);
    final url = created['url'] as String;
    final host = Uri.parse(url).host;
    return CarePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CareBadge('Votre partage est prêt', color: CareColors.primary),
          const SizedBox(height: 16),
          Text(
            share['label'] as String,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            'Valable jusqu’au ${careDate(share['expiresAt'])}',
            style: const TextStyle(color: CareColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Center(
            child: Semantics(
              label: 'QR code du lien de partage, sans code PIN',
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 216,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CareColors.canvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const Text(
                  'CODE PIN À TRANSMETTRE SÉPARÉMENT',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: CareColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  created['pin'] as String,
                  key: const ValueKey('share-pin'),
                  style: const TextStyle(
                    fontSize: 30,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w800,
                    color: CareColors.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    _copy(url, 'Lien copié. Transmettez le PIN séparément.'),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Copier le lien'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _copy(created['pin'] as String, 'Code PIN copié.'),
                icon: const Icon(Icons.key_rounded, size: 18),
                label: const Text('Copier le PIN'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Afficher le lien',
                style: TextStyle(fontSize: 13),
              ),
              children: [
                SelectableText(
                  url,
                  style: const TextStyle(fontSize: 12, color: CareColors.muted),
                ),
              ],
            ),
          ),
          const Text(
            'Le QR code et le PIN sont affichés uniquement ici, jusqu’à la fermeture de cet écran. Vous pourrez toujours révoquer le partage depuis l’historique.',
            style: TextStyle(
              fontSize: 12,
              color: CareColors.muted,
              height: 1.6,
            ),
          ),
          if (['localhost', '127.0.0.1', '::1', '10.0.2.2'].contains(host)) ...[
            const SizedBox(height: 12),
            const Text(
              'Ce lien utilise l’adresse locale du PC. Pour un scan depuis un téléphone, configurez l’adresse réseau du serveur (voir la documentation du module).',
              style: TextStyle(
                fontSize: 12,
                color: CareColors.amber,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _busy ? null : () => _revoke(share),
            icon: const Icon(Icons.link_off_rounded),
            label: const Text('Révoquer cet accès'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Créer un autre partage ?'),
                        content: const Text(
                          'Conservez d’abord le lien et le PIN actuels : ils ne pourront plus être affichés. Ce partage restera actif jusqu’à son expiration ou sa révocation.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Conserver cet écran'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Continuer'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      setState(() => _created = null);
                    }
                  },
            child: const Text('Créer un autre partage'),
          ),
        ],
      ),
    );
  }

  Widget _sharesPanel() => CarePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Vos partages',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Suivez les accès et gardez le contrôle.',
          style: TextStyle(color: CareColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_shares.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Aucun partage pour ce document.',
              style: TextStyle(color: CareColors.muted),
            ),
          )
        else
          for (final share in _shares) _shareCard(share),
        const SizedBox(height: 8),
        const Text(
          'Chaque ouverture réussie est datée et génère une notification. L’historique ne vérifie pas l’identité du destinataire.',
          style: TextStyle(color: CareColors.muted, fontSize: 12, height: 1.6),
        ),
      ],
    ),
  );

  Widget _shareCard(Map<String, dynamic> share) {
    final status = _status(share);
    final (label, color) = switch (status) {
      'ACTIVE' => ('Actif', CareColors.primary),
      'REVOKED' => ('Révoqué', CareColors.muted),
      'LOCKED' => ('Bloqué · PIN', CareColors.amber),
      _ => ('Expiré', CareColors.muted),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: CareColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                share['label'] as String,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              CareBadge(label, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Créé le ${careDate(share['createdAt'])}\nExpiration : ${careDate(share['expiresAt'])}',
            style: const TextStyle(
              color: CareColors.muted,
              fontSize: 12,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${share['accessCount']} consultation(s)',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if (share['lastAccessAt'] != null)
            Text(
              'Dernière : ${careDate(share['lastAccessAt'])}',
              style: const TextStyle(color: CareColors.muted, fontSize: 12),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _history(share),
                icon: const Icon(Icons.history_rounded, size: 17),
                label: const Text('Historique'),
              ),
              if (status == 'ACTIVE' || status == 'LOCKED')
                TextButton.icon(
                  key: ValueKey('revoke-share-${share['id']}'),
                  onPressed: _busy ? null : () => _revoke(share),
                  icon: const Icon(Icons.link_off_rounded, size: 17),
                  label: const Text('Révoquer'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: CareColors.primary.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, size: 22, color: CareColors.primary),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'PIN à 6 chiffres · révocation immédiate\nLe QR code ne contient aucune donnée médicale. Transmettez le PIN séparément au destinataire.',
            style: TextStyle(
              color: CareColors.primary,
              fontSize: 12,
              height: 1.7,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ShareHistory extends StatefulWidget {
  const _ShareHistory({required this.share, required this.load});
  final Map<String, dynamic> share;
  final Future<List<Map<String, dynamic>>> Function() load;
  @override
  State<_ShareHistory> createState() => _ShareHistoryState();
}

class _ShareHistoryState extends State<_ShareHistory> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Historique des consultations'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return CareError(
              message: 'Impossible de charger l’historique.',
              onRetry: () => setState(() {
                _future = widget.load();
              }),
            );
          }
          final accesses = snapshot.data ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.share['label'] as String,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (accesses.isEmpty)
                const Text('Aucune consultation pour le moment.')
              else ...[
                const Text(
                  'Les 50 dernières ouvertures réussies.',
                  style: TextStyle(color: CareColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                for (final access in accesses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.visibility_outlined,
                      color: CareColors.primary,
                    ),
                    title: const Text('Document consulté'),
                    subtitle: Text(careDate(access['accessedAt'])),
                  ),
              ],
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
    ],
  );
}
