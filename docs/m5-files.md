# Fichiers integration M5

Source : D:\DevMobile\Medicare. Destination : D:\DecMobilFinal\app-medicare.

Liste relative a la destination, comparee a son etat avant import. Le stockage prive ignore par Git est exclu.

## Fichiers existants modifies

| Fichier | Justification |
| --- | --- |
| `.gitignore` | Stockage prive M5 ignore par Git |
| `backend/pom.xml` | PDFBox pour les PDF M5, version existante conservee |
| `backend/src/test/java/com/medicare/auth/AuthenticationIntegrationTest.java` | Isolation des comptes et du schema de test; production inchangee |
| `frontend/lib/features/home/doctor_dashboard_page.dart` | Entrees M5 et badge dans le menu medecin |
| `frontend/lib/features/home/home_page.dart` | Entrees M5 et badge, cartes M1-M4 conservees |
| `frontend/pubspec.lock` | Resolution des dependances M5 |
| `frontend/pubspec.yaml` | Lecteur PDF, QR et version minimale du SDK |
| `frontend/test/widget_test.dart` | Clic du test centre sur le bouton du parcours medecin conserve |
| `RUN.md` | Orientation source/destination et guide M5 |

## Fichiers ajoutes

| Fichier | Fonction |
| --- | --- |
| `backend/db/migrations/m5-create-tables.sql` | Installation SQL des seules tables M5 |
| `backend/src/main/java/com/medicare/common/NotificationDocumentExceptionHandler.java` | Erreurs limitees aux controles M5 |
| `backend/src/main/java/com/medicare/document/controller/DocumentAnalysisController.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/controller/DocumentController.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/controller/DocumentShareController.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/controller/SharedDocumentController.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/DocumentConfiguration.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/DocumentShareSecurityConfiguration.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/dto/AnalysisDtos.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/dto/DocumentDtos.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/dto/DocumentShareDtos.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/entity/DocumentAnalysis.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/entity/DocumentCategory.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/entity/DocumentShare.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/entity/DocumentShareAccess.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/entity/MedicalDocument.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/repository/DocumentAnalysisRepository.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/repository/DocumentRepository.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/repository/DocumentShareAccessRepository.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/repository/DocumentShareRepository.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/service/DocumentAccess.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/service/DocumentAnalysisService.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/service/DocumentAnalysisWorker.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/service/DocumentService.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/service/DocumentShareService.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/service/DocumentStorageService.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/service/DocumentTextReader.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/document/service/LocalDocumentModel.java` | Documents M5, stockage, partage et analyse |
| `backend/src/main/java/com/medicare/notification/controller/CareRelationshipController.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/controller/NotificationAdminController.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/controller/NotificationController.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/controller/ReminderController.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/dto/NotificationDtos.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/entity/Notification.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/entity/NotificationType.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/entity/PatientDoctor.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/entity/Reminder.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/entity/ReminderChange.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/entity/ReminderStatus.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/M5SchemaConfiguration.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/ModuleNotificationConfiguration.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/ModuleNotificationResponseAdvice.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/NotificationConfiguration.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/repository/NotificationRepository.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/repository/PatientDoctorRepository.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/repository/ReminderChangeRepository.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/repository/ReminderRepository.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/service/CareRelationships.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/service/ModuleNotificationTargets.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/service/NotificationService.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/java/com/medicare/notification/service/ReminderScheduler.java` | Notifications et rappels M5, permissions, pont M2-M4 |
| `backend/src/main/resources/document-share/app.js` | Page publique avec jeton et PIN |
| `backend/src/main/resources/document-share/index.html` | Page publique avec jeton et PIN |
| `backend/src/main/resources/document-share/style.css` | Page publique avec jeton et PIN |
| `backend/src/test/java/com/medicare/document/DocumentShareApiTest.java` | Tests M5 adaptes a la destination |
| `backend/src/test/java/com/medicare/document/service/DocumentFollowUpTest.java` | Tests M5 adaptes a la destination |
| `backend/src/test/java/com/medicare/notification/M5IntegrationRolesApiTest.java` | Tests M5 adaptes a la destination |
| `docs/m5-files.md` | Rapport ou liste de fichiers |
| `docs/M5-INTEGRATION.md` | Rapport ou liste de fichiers |
| `frontend/lib/core/widgets/care_workspace.dart` | Theme et composants locaux M5 |
| `frontend/lib/features/documents/pages/document_analysis_page.dart` | Documents, lecteur, partage et analyse M5 |
| `frontend/lib/features/documents/pages/document_preview_page.dart` | Documents, lecteur, partage et analyse M5 |
| `frontend/lib/features/documents/pages/document_shares_page.dart` | Documents, lecteur, partage et analyse M5 |
| `frontend/lib/features/documents/pages/documents_page.dart` | Documents, lecteur, partage et analyse M5 |
| `frontend/lib/features/documents/providers/document_repository.dart` | Documents, lecteur, partage et analyse M5 |
| `frontend/lib/features/documents/widgets/document_card.dart` | Documents, lecteur, partage et analyse M5 |
| `frontend/lib/features/documents/widgets/document_upload_form.dart` | Documents, lecteur, partage et analyse M5 |
| `frontend/lib/features/notifications/pages/notification_admin_page.dart` | Interface M5 et API authentifiees |
| `frontend/lib/features/notifications/pages/notifications_page.dart` | Interface M5 et API authentifiees |
| `frontend/lib/features/notifications/providers/notification_repository.dart` | Interface M5 et API authentifiees |
| `frontend/lib/features/notifications/widgets/activity_cards.dart` | Interface M5 et API authentifiees |
| `frontend/lib/features/notifications/widgets/care_contacts.dart` | Interface M5 et API authentifiees |
| `frontend/lib/features/notifications/widgets/notification_badge.dart` | Interface M5 et API authentifiees |
| `frontend/lib/features/notifications/widgets/reminder_form.dart` | Interface M5 et API authentifiees |
| `frontend/test/care_roles_test.dart` | Tests Flutter et donnees simulees M5 |
| `frontend/test/care_workspace_test.dart` | Tests Flutter et donnees simulees M5 |
| `frontend/test/document_analysis_test.dart` | Tests Flutter et donnees simulees M5 |
| `frontend/test/document_sharing_test.dart` | Tests Flutter et donnees simulees M5 |
| `frontend/test/m5_integration_test.dart` | Tests Flutter et donnees simulees M5 |
| `frontend/test/m5_test_fixtures.dart` | Tests Flutter et donnees simulees M5 |
