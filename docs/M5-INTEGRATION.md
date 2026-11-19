# Intégration de M5 dans App-mobile-MediCare

Date : 19 novembre 2026.

**Source du module :** `D:\DevMobile\Medicare`.

**Destination de l'intégration :** `D:\DecMobilFinal\app-medicare` : backend dans `backend/`, interface dans `frontend/`.

Le code M5 existant de la source a été importé et adapté dans cette destination. Les médicaments, prescriptions, prises, stocks et statistiques du M3 de destination sont conservés. Les rappels M5 utilisent ces traitements; le CRUD simplifié Médicaments de la source ne remplace pas le M3 existant.

## 1. Fichiers ajoutés et modifications partagées

La [liste exhaustive des fichiers](m5-files.md) distingue les ajouts et les neuf fichiers existants modifiés. Aucun fichier existant n'a été supprimé.

Les packages backend `com.medicare.notification` et `com.medicare.document`, les ressources `document-share`, les fonctionnalités Flutter `features/notifications` et `features/documents` et leur thème local `core/widgets/care_workspace.dart` proviennent de M5. Les services, DTO et repositories restent dans la structure de la source et utilisent les services de sécurité et le client API de la destination.

Les adaptations principales sont :

- `CareRelationships` réutilise `AccountAccess` et `HealthAccessService`, ainsi que les liens existants de M2/M3. Un médecin ne peut pas s'approprier un nouveau patient par simple connaissance de son email : un suivi existant ou un rattachement explicite du patient est requis.
- Les partages de documents restent explicites. Le suivi clinique donne accès à la sélection du patient, pas à sa bibliothèque privée entière. Les liens cliniques sont affichés dans « Mes médecins » et ne sont pas supprimés depuis M5.
- `ModuleNotificationConfiguration`, `ModuleNotificationResponseAdvice` et `ModuleNotificationTargets` observent les mutations HTTP réussies et déterminent le destinataire à partir des données serveur. Une prescription, un médicament ou une mesure saisis par le médecin notifient le patient concerné. Aucun contrôleur M1–M4 n'est modifié.
- Les rappels M5 et les prises M3 sont distincts : `/api/reminders` pour M5, `/api/medications/...` pour les prises et stocks existants. Un traitement arrêté ne déclenche plus son rappel M5 associé.
- `DocumentConfiguration` conserve le resolver multipart et les limites de la destination; il ne remplace pas la configuration d'upload des ordonnances M3.
- `LocalDocumentModel` utilise le client HTTP Spring et les paramètres Ollama de la destination. L'intégration ne nécessite pas Spring AI.
- Les appels à `file_picker` ont été adaptés à la version 11 déjà utilisée dans la destination.

| Fichier partagé modifié | Justification |
| --- | --- |
| `.gitignore` | Ignore le stockage privé `backend/storage/`. |
| `RUN.md` | Indique explicitement le sens source → destination et renvoie vers ce rapport. |
| `backend/pom.xml` | Déclare PDFBox 3.0.5 pour la lecture des documents PDF M5; cette version était déjà apportée par Tess4J. Aucun changement de Spring Boot ou de sécurité. |
| `frontend/pubspec.yaml` | Ajoute `pdfrx` 2.3.4 pour l'aperçu PDF et `qr_flutter` 4.1.0 pour les QR locaux. Le SDK minimum devient Dart 3.10, requis par le lecteur; l'environnement installé utilise Dart 3.13. |
| `frontend/pubspec.lock` | Résolution des dépendances du lecteur PDF et des QR; les dépendances existantes M3 sont conservées. |
| `frontend/lib/features/home/home_page.dart` | Ajoute les accès Notifications/Rappels et Documents, et le badge personnel, sans remplacer les cartes M1–M4. |
| `frontend/lib/features/home/doctor_dashboard_page.dart` | Même accès M5 dans l'espace médecin, avec conservation des prescriptions et du suivi des patients. |
| `backend/src/test/java/com/medicare/auth/AuthenticationIntegrationTest.java` | Isole les tests dans un profil `test` sans comptes de démonstration, avec clé et base de test explicites; désactive les notifications automatiques pour les scénarios historiques M1. La sécurité réelle n'est pas changée. |
| `frontend/test/widget_test.dart` | Centre le bouton de dépôt d'ordonnance avant le clic du test, après l'ajout des cartes M5. Les assertions du parcours médecin sont conservées. |

`SecurityConfig`, l'authentification de production, les rôles, les routes globales, les fichiers de configuration de base, les entités et contrôleurs M1–M4 ne sont pas remplacés. Aucun appel de notification n'a été ajouté dans leur code : le pont est entièrement dans M5.

## 2. Même base et SQL

La configuration de destination reste : PostgreSQL `medicare` sur `localhost:5432`, API sur le port 8082. Le profil `dev` H2 existant reste disponible; il n'est pas utilisé pour remplacer la base PostgreSQL en cours.

Le [script SQL M5](../backend/db/migrations/m5-create-tables.sql) contient uniquement `CREATE TABLE IF NOT EXISTS` pour :

`notifications`, `reminders`, `patient_doctor`, `reminder_change`, `medical_documents`, `document_shares`, `document_share_accesses`, `document_analyses`.

Il ne modifie aucune table existante. Les métadonnées M5 déjà présentes dans cette base sont réutilisées. Les huit fichiers médicaux de la source ont été copiés dans `backend/storage/documents` sans écraser un fichier différent. Ils sont ignorés par Git; aucune copie de document privé n'est nécessaire pour compiler le code.

`M5SchemaConfiguration` protège toutes les tables déjà installées contre les modifications automatiques de Hibernate en mode `update`. Sur une base vierge, les entités existantes peuvent toujours créer leurs tables. Les futures évolutions d'une table déjà installée doivent passer par une migration explicite. Aucun ancien script de modification de clé n'est exécuté automatiquement.

Exécution du script avec les identifiants PostgreSQL déjà configurés :

```powershell
Set-Location D:\DecMobilFinal\app-medicare\backend
$env:PGPASSWORD = $env:DB_PASSWORD
try {
  psql -h localhost -U $env:DB_USERNAME -d medicare -X -v ON_ERROR_STOP=1 `
    -f .\db\migrations\m5-create-tables.sql
} finally {
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
}
```

Une sauvegarde préalable et un export de schéma ont été placés dans `D:\DecMobilFinal\.medicare-runtime\m5-import`, hors du dépôt.

## 3. Matrice rôles × fonctionnalités

Les noms exacts sont `USER`, `DOCTOR`, `ADMIN`; Spring utilise `ROLE_USER`, `ROLE_DOCTOR`, `ROLE_ADMIN`. L'identité vient du principal construit par le filtre JWT de la destination. Aucun rôle supplémentaire n'est créé. Un administrateur doit avoir son email vérifié, conformément à M1.

| Fonction | ADMIN | USER | DOCTOR |
| --- | --- | --- | --- |
| Notifications reçues, lecture/non-lu, archives et badge | Sa boîte | Sa boîte | Sa boîte |
| Liste et CRUD administratifs des notifications | Tous les utilisateurs | Refusé | Refusé |
| Rappels personnels | CRUD | CRUD | CRUD |
| Rappels pour autrui | Tous les utilisateurs | Refusé | Patients suivis, pour les rappels dont il est l'auteur |
| Consigne d'un rappel de suivi reçu | Gestion administrative | Heure de son alerte et report; pas de réécriture de la consigne médicale | Auteur ou destinataire selon le cas |
| Relance d'un échec et historique des rappels | Oui | Refusé | Refusé |
| Documents : ajout, lecture, téléchargement | Tous les propriétaires | Ses documents | Ses documents et les documents explicitement partagés de ses patients |
| Dépôt de document pour autrui | Tous les utilisateurs | Refusé | Patient suivi ou rattaché explicitement |
| Édition, suppression, QR d'un document | Tous | Ses documents, fonctions conservées de la source | Ses documents personnels; pas ceux d'autrui |
| Médicaments, prescriptions, stock, prises | Règles M3 existantes | Consultation selon M3 | Gestion selon M3, limitée à ses prescriptions |

Les boutons et menus Flutter suivent ces droits. Le backend vérifie séparément le rôle, l'identité, le propriétaire, le suivi et le partage. La page QR publique conserve son mécanisme jeton + PIN avec expiration, révocation et limite d'essais; elle ne rend pas publiques les autres routes.

API serveur réutilisable :

```java
notificationService.notify(userId, NotificationType.MEDICATION, "Une information sur votre traitement.");
notificationService.notify(userId, NotificationType.GENERAL, "Document médical", "Votre document est disponible.");
```

Les endpoints administratifs sont sous `/api/notifications/admin`. Les boîtes personnelles restent sous `/api/notifications`, les rappels sous `/api/reminders`, les documents sous `/api/documents`.

## 4. Lancement et checklist

Charger Java 21, Maven, Flutter et les variables PostgreSQL/JWT déjà configurées. Sur ce poste, le fichier d'environnement existant `D:\DevMobile\.medicare-env\env.ps1` peut fournir les outils et identifiants; les commandes doivent ensuite se placer explicitement dans la destination ci-dessous.

Backend :

```powershell
Set-Location D:\DecMobilFinal\app-medicare\backend
mvn spring-boot:run
```

Frontend, second terminal :

```powershell
Set-Location D:\DecMobilFinal\app-medicare\frontend
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 7358 `
  --dart-define=API_BASE_URL=http://localhost:8082/api
```

Android : le client conserve `10.0.2.2:8082/api` sur émulateur. Pour un téléphone USB : `adb reverse tcp:8082 tcp:8082`, puis `flutter run -d <appareil> --dart-define=API_BASE_URL=http://localhost:8082/api`.

Vérifications :

```powershell
cd D:\DecMobilFinal\app-medicare\backend
mvn clean compile test package
cd D:\DecMobilFinal\app-medicare\frontend
flutter pub get
flutter analyze
flutter test
flutter build web --debug --no-pub
```

Checklist couverte par les tests :

- [x] Authentification M1, MFA, récupération, sessions, rôles et fusion : suite existante conservée.
- [x] Rendez-vous M2, prescriptions/médicaments M3 et mesures M4 : mutations et lectures existantes, notifications au bon patient.
- [x] USER ne lit pas les notifications ou fichiers d'autrui et ne programme pas un rappel pour autrui.
- [x] DOCTOR utilise les patients suivis via M2 ou M3; un rattachement supplémentaire exige le consentement du patient.
- [x] ADMIN crée/modifie/supprime les notifications pour patient, médecin et admin; gère les documents et rappels d'autrui.
- [x] Un rappel n'est envoyé qu'une fois; il est annulé si le traitement M3 est arrêté.
- [x] Partages : PIN, expiration, révocation, concurrence et cloisonnement.
- [x] Flutter : formulaires, menus de rôle, lecteur, partage, badge et déconnexion; parcours existants conservés.

Les résultats finaux et contrôles de démarrage sont consignés à la fin de ce document.

## 5. Hypothèses et points à valider

- La mention « médicaments » est intégrée en reliant M5 au M3 complet de destination. Le remplacer par le CRUD simplifié de la source aurait retiré des fonctions et des restrictions existantes.
- Les documents médicaux restent inclus conformément à la demande initiale et au contenu du M5 source.
- Les types SQL existants `GENERAL`, `APPOINTMENT`, `MEDICATION` sont conservés. Santé et documents utilisent `GENERAL` avec un titre explicite; aucun changement de contrainte SQL n'est nécessaire.
- Les notifications sont internes à l'application, actualisées périodiquement. Aucun nouveau service de push, SMS ou email n'est installé.
- Le pont automatique couvre les mutations HTTP. Les traitements serveur directs peuvent appeler `NotificationService`; il n'effectue pas de rattrapage rétroactif des anciennes données.
- Une erreur secondaire de notification est journalisée et ne transforme pas une opération M1–M4 déjà réussie en échec.
- L'analyse de document utilise l'Ollama configuré dans la destination et requiert un modèle disponible. L'OCR des scans nécessite un exécutable Tesseract avec `fra` et `eng`, configurable avec `APP_ANALYSIS_TESSERACT`. Le reste de M5 fonctionne sans ces outils optionnels.
- Les parcours sur téléphone physique, les notifications système et l'accessibilité réseau d'un QR depuis un autre appareil restent à vérifier sur l'appareil choisi. `APP_DOCUMENTS_SHARE_BASE_URL` permet de définir une adresse accessible au téléphone.

## Résultats finaux

- `mvn clean compile test package` : **79 tests réussis**, aucune erreur ni échec; JAR construit dans le backend de destination.
- `flutter pub get` : réussi; `flutter analyze` : aucun problème; `flutter test` : **60 tests réussis**.
- `flutter build web --debug --no-pub` : réussi. La compilation JavaScript utilisée par Chrome fonctionne; le contrôle facultatif de compatibilité WebAssembly signale des limitations des dépendances web préexistantes.
- Backend de destination démarré sur **8082**, route `/api/health` fonctionnelle.
- Frontend de destination démarré dans Chrome sur **http://localhost:7358**, relié à cette API; réponse HTTP 200 et démarrage Flutter confirmés.
- Connexion de l'administrateur existant vérifiée; `/api/notifications/admin` répond HTTP 200.
- Les **huit documents existants** sont visibles; le téléchargement d'un document repris répond HTTP 200 depuis le stockage de destination.
- Script SQL exécuté avec succès sur la base existante. Les exports complets de schéma PostgreSQL avant et après intégration sont **identiques**; aucune table existante n'a été modifiée.
- L'ancien backend source sur 8080 a été arrêté afin que le module soit désormais exécuté dans la destination, avec la même base PostgreSQL.
