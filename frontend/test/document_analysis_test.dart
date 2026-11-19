import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/core/network/api_client.dart';
import 'package:medicare/core/storage/token_storage.dart';
import 'package:medicare/features/documents/pages/document_analysis_page.dart';
import 'package:medicare/features/documents/providers/document_repository.dart';

class AnalysisRepository extends DocumentRepository {
  AnalysisRepository() : super(ApiClient(TokenStorage()));

  Map<String, dynamic>? review;

  @override
  Future<Map<String, dynamic>> analysis(int id, {bool start = false}) async => {
    'status': 'READY',
    'draft': {
      'fields': {'title': 'Titre proposé', 'category': 'OTHER'},
      'sourceText': 'Compte rendu fictif.',
      'followUpDate': null,
    },
  };

  @override
  Future<void> confirmAnalysis(int id, Map<String, dynamic> data) async {
    review = data;
  }
}

void main() {
  testWidgets('relire la source et valider un titre corrigé sans rappel', (
    tester,
  ) async {
    final repo = AnalysisRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentAnalysisPage(
          document: const {'id': 1, 'title': 'Fichier de démonstration'},
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Texte lu sur le document'));
    await tester.pumpAndSettle();
    expect(find.text('Compte rendu fictif.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Titre corrigé');
    final confirm = find.text('Valider et enregistrer');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(repo.review?['fields']['title'], 'Titre corrigé');
    expect(repo.review?.containsKey('reminderAt'), false);
  });
}
