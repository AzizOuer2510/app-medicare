# MediCare — Application mobile de suivi médical

<p align="center"><img src="logo.png" alt="MediCare — Protect Your Health" width="220"></p>

MediCare réunit dans une seule application mobile le parcours de soin d'un patient :
prise de rendez-vous, traitements médicamenteux, suivi de santé et de nutrition.
Médecins, secrétaires et administrateurs disposent chacun de leur espace.

| Couche | Technologie |
| --- | --- |
| Frontend | Flutter (Android, iOS, Web, Windows) — Riverpod, Dio |
| Backend | Spring Boot 3.5 / Java 21 — API REST |
| Base de données | H2 fichier en développement (profil `dev`), PostgreSQL en production |
| Sécurité | JWT, BCrypt, vérification email (OTP), double vérification, codes de récupération |
| IA (optionnelle) | Ollama en local : `llama3.2` (texte) et `llava` (photos) |
| OCR | Tesseract (lecture des ordonnances) |

## Sommaire

1. [Démarrage rapide](#démarrage-rapide)
2. [Comptes de test](#comptes-de-test)
3. [Acteurs et privilèges](#acteurs-et-privilèges)
4. [Fonctionnalités par module](#fonctionnalités-par-module)
5. [Scénarios de test](#scénarios-de-test)
6. [Documentation technique](#documentation-technique)

---

## Démarrage rapide

Le guide détaillé (Windows, téléphone physique, ports, problèmes fréquents) est dans [`RUN.md`](RUN.md).

```powershell
# 1. Backend (Java 21 requis) — base H2 locale + comptes de démonstration
cd backend
mvn spring-boot:run "-Dspring-boot.run.profiles=dev"

# 2. Frontend, dans un second terminal
cd frontend
flutter pub get
flutter run -d chrome
```

- **API :** `http://localhost:8082/api`.
- **Émulateur Android :** l'application utilise automatiquement `10.0.2.2:8082`.
- **Téléphone en USB :** lancer `adb reverse tcp:8082 tcp:8082`, puis
  `flutter run -d <appareil> --dart-define=API_BASE_URL=http://localhost:8082/api`.
- **Fonctions IA (facultatif) :** `ollama pull llama3.2`, `ollama pull llava`, puis `ollama serve`.
  Sans Ollama, les écrans IA passent en mode démonstration.

---

## Comptes de test

Ces comptes sont créés **automatiquement au démarrage du backend en profil `dev`**
(jamais en production). Ils sont déjà vérifiés et sans double vérification :
la connexion se fait directement, sans code email.

| Acteur | Email | Mot de passe | Rattachement | Données préremplies |
| --- | --- | --- | --- | --- |
| Patient | `patient@medicare.com` (Patient Test) | `Patient@2026` | Suivi par **Dr Ahmed** (traitement prescrit) | Constantes normales, poids en baisse |
| Patient | `patient2@medicare.com` (Amine Trabelsi) | `Patient@2026` | Suivi par **Dr Ahmed** (rendez-vous) | Hypertension, surpoids, une mesure prise en consultation par Dr Ahmed |
| Patient | `patient3@medicare.com` (Sonia Mejri) | `Patient@2026` | Suivie par **Dr Sarah** (traitement + rendez-vous) | Glycémie élevée et fièvre récente (alertes) |
| Médecin | `dr.ahmed@medicare.com` | `Doctor@2026` | Patients : Patient Test, Amine Trabelsi | — |
| Médecin | `dr.sarah@medicare.com` | `Doctor@2026` | Patiente : Sonia Mejri | — |
| Secrétaire | `secretaire.ahmed@medicare.com` | `Secret@2026` | Secrétaire de Dr Ahmed | — |
| Secrétaire | `secretaire.sarah@medicare.com` | `Secret@2026` | Secrétaire de Dr Sarah | — |
| Administrateur | `admin@medicare.com` | `Admin@2026` | — | — |

Chaque patient dispose de 30 jours de mesures, de 14 jours de repas et
d'hydratation, et d'objectifs de santé : les graphiques, statistiques, alertes
et l'export PDF sont visibles dès la première connexion.

> Ces mots de passe sont publics : ils servent uniquement aux tests en local.
> Pour réinitialiser toutes les données, arrêter le backend et supprimer `backend/data/`.

---

## Acteurs et privilèges

### Les acteurs

| Acteur | Rôle technique | Description |
| --- | --- | --- |
| **Visiteur** | — | Personne non connectée : inscription, connexion, récupération du compte. |
| **Patient** | `USER` | Gère ses rendez-vous, consulte ses traitements, tient son suivi santé et nutrition. |
| **Secrétaire** | `USER` + affectation à un médecin | Patient qui, en plus, gère l'agenda du médecin auquel un administrateur l'a affecté. |
| **Médecin** | `DOCTOR` | Prescrit, planifie les traitements et suit la santé de ses patients. |
| **Administrateur** | `ADMIN` | Gère les rôles, les affectations des secrétaires, les fusions de comptes, les incidents et l'audit. |

### Le lien médecin ↔ patient, partagé entre les modules

Un médecin **suit** un patient dès que l'une de ces deux conditions est remplie :

- **Médicaments :** il lui a prescrit un traitement (dépôt d'ordonnance) ;
- **Rendez-vous :** le patient a un rendez-vous non annulé avec lui.

Ce lien donne au médecin l'accès au **Suivi santé et nutrition** du patient.
Un médecin ne voit jamais les données d'un patient qu'il ne suit pas.

### Matrice des privilèges

Légende : ✅ autorisé · 👁 lecture seule · ❌ refusé · — sans objet

| Fonctionnalité | Visiteur | Patient | Secrétaire | Médecin | Admin |
| --- | :---: | :---: | :---: | :---: | :---: |
| **Authentification et compte** | | | | | |
| S'inscrire, se connecter, mot de passe oublié | ✅ | — | — | — | — |
| Profil, mot de passe, double vérification, codes de récupération | ❌ | ✅ | ✅ | ✅ | ✅ |
| Demander un rôle (Médecin attribué automatiquement, Administrateur sur validation) | ❌ | ✅ | ✅ | — | — |
| Demander le rapprochement de deux comptes | ❌ | ✅ | ✅ | ❌ | ❌ |
| Valider les rôles et les fusions, déclarer un incident, consulter l'audit | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Rendez-vous** | | | | | |
| Créer, modifier, annuler ses propres rendez-vous | ❌ | ✅ | ✅ | — | ✅ |
| Gérer les rendez-vous des patients de son médecin (espace secrétaire) | ❌ | ❌ | ✅ | ❌ | ✅ |
| Affecter une secrétaire à un médecin | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Médicaments** | | | | | |
| Consulter ses traitements, horaires de prise, historique et ordonnances | ❌ | 👁 | 👁 | — | — |
| Déposer une ordonnance (OCR) et créer le planning du patient | ❌ | ❌ | ❌ | ✅ | ✅ |
| Modifier ou arrêter un traitement, gérer le stock et les prises | ❌ | ❌ | ❌ | ✅ (ses prescriptions) | ✅ |
| Consulter les patients suivis et leur observance | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Suivi santé et nutrition** | | | | | |
| Tableau de bord, mesures, repas, hydratation, objectifs (ses données) | ❌ | ✅ | ✅ | — | ✅ |
| Statistiques, export PDF, analyse santé IA (ses données) | ❌ | ✅ | ✅ | — | ✅ |
| Reconnaissance des aliments par IA, NutriCoach | ❌ | ✅ | ✅ | — | ✅ |
| Liste de ses patients avec dernières constantes et alertes | ❌ | ❌ | ❌ | ✅ | ❌ |
| Consulter le suivi complet d'un patient suivi | ❌ | ❌ | ❌ | 👁 | ❌ |
| Ajouter une mesure de consultation à un patient suivi | ❌ | ❌ | ❌ | ✅ | ❌ |
| Modifier ou supprimer une mesure | ❌ | ✅ ses saisies | ✅ ses saisies | ✅ uniquement les siennes | ✅ ses saisies |
| Ajuster les objectifs d'un patient suivi | ❌ | ❌ | ❌ | ✅ | ❌ |
| Repas et hydratation d'un patient suivi | ❌ | ❌ | ❌ | 👁 | ❌ |
| Données de santé d'un autre utilisateur non suivi | ❌ | ❌ | ❌ | ❌ | ❌ |

Toutes ces règles sont vérifiées **côté serveur**. Une tentative interdite
renvoie `401` (non connecté), `403` (droit insuffisant) ou `404` (patient non suivi).

---

## Fonctionnalités par module

### 1. Authentification et sécurité du compte

- Inscription avec choix du rôle (Patient, Médecin, Administrateur sur validation) et vérification de l'email par code à 6 chiffres.
- Connexion par email ou identifiant, connexion sans mot de passe par code email, connexion avec un code de récupération.
- Double vérification par email, avec 10 codes de récupération à usage unique.
- Mot de passe oublié : code par email valable 10 minutes, 5 essais maximum.
- Politique de mots de passe : 12 caractères minimum, refus des mots de passe divulgués (Pwned Passwords), historique des 5 derniers.
- Limitation des tentatives par IP, par compte et par code.
- Profil : nom, téléphone, date de naissance, bio, photo ; changement de mot de passe.
- Écran « Sécurité et accès » : vérifier son email, activer la double vérification, renouveler ses codes, demander un rôle, rapprocher deux comptes.
- Administration : validation des demandes de rôle, examen des fusions de comptes et des doublons, déclaration d'incident (révocation des sessions), journal d'audit.
- Session expirée : retour automatique à la connexion, sans perte du jeton en cas de simple coupure réseau.

### 2. Rendez-vous

- Prise de rendez-vous avec un médecin inscrit : date, heure, motif, type de consultation.
- Agenda (vue calendrier) ou liste, recherche par médecin ou motif, filtres par statut (planifié, confirmé, terminé, annulé).
- Modification, annulation et suppression ; contrôle des conflits d'horaire.
- Synthèse : total, rendez-vous à venir, confirmés.
- Suggestion de spécialité selon le motif et proposition d'un créneau libre dans les 30 jours.
- Estimation du risque d'absence (non-confirmation, délai, historique d'annulations).
- Ajout de 10 rendez-vous d'exemple pour les démonstrations.
- **Espace secrétaire :** liste des patients, création, modification et suppression des rendez-vous du médecin affecté, envoi manuel des rappels.
- **Rappels automatiques** par email (et SMS si configuré) 24 h avant le rendez-vous.
- **Administration :** affectation des secrétaires aux médecins.

### 3. Médicaments

- **Médecin :** dépôt d'une ordonnance (photo ou PDF) pour un patient, lecture automatique (OCR) qui propose les médicaments, création du planning de prise.
- Fiche traitement : dosage, forme, fréquence, horaires de prise, jours, dates de début et de fin, instructions, notes.
- Modification, archivage et arrêt d'un traitement sans effacer l'historique.
- Gestion du stock : quantité, seuil d'alerte, réapprovisionnement, estimation des jours restants.
- Prises du jour : effectuée, manquée, ignorée ou reportée, avec historique par médicament.
- Statistiques d'observance (jour, semaine, mois) pour le patient et pour le médecin.
- Notifications locales de rappel de prise sur le téléphone.
- Assistant traitement : réponses aux questions sur le planning en cours.
- **Patient :** consultation de ses traitements, de son agenda de prises, de ses ordonnances et de son historique.
- **Médecin :** liste des patients suivis, prescriptions et observance par patient.

### 4. Suivi santé et nutrition

**Santé**
- Mesures : poids, fréquence cardiaque, tension artérielle, température, glycémie (g/L), avec date, heure et note.
- Historique filtré par période (7 j, 30 j, 3 mois, 6 mois, tout) et par type de mesure ; modification et suppression.
- Tableau de bord : dernières valeurs, flèches de tendance, IMC calculé avec sa catégorie, courbes du poids et de la fréquence cardiaque.
- Objectifs personnels : taille, poids cible, calories et eau quotidiennes, notes.

**Nutrition**
- Journal alimentaire : petit-déjeuner, déjeuner, dîner, collation, avec date, heure, aliments, quantités et commentaire.
- Base de 44 aliments : calories, protéines, glucides, lipides et fibres calculés selon la quantité.
- Synthèse du jour : nombre de repas, calories par rapport à l'objectif, macronutriments.
- Hydratation : ajout rapide ou quantité libre, progression par rapport à l'objectif, historique sur 7 jours.

**Analyse**
- Statistiques sur 7 j, 30 j, 3 mois ou 6 mois : courbe de chaque constante (minimum, moyenne, maximum, variation), calories par jour, répartition des macronutriments, hydratation moyenne.
- Santé et nutrition présentées côte à côte (poids, apports, hydratation), sans diagnostic.
- Export PDF du rapport (objectifs, statistiques, historique des mesures, journal alimentaire).

**Intelligence artificielle (Ollama, locale)**
- Analyse santé : état général, alertes automatiques (fièvre, hyper/hypoglycémie, hypertension, tachycardie…) et recommandations.
- Reconnaissance des aliments par photo ou description, avec correction possible avant enregistrement.
- NutriCoach : assistant nutritionnel conversationnel.

**Espace médecin**
- Liste des patients suivis, avec l'origine du lien (traitement ou rendez-vous), les dernières constantes et les alertes des 30 derniers jours.
- Consultation complète du suivi d'un patient ; repas et hydratation en lecture seule.
- Mesures de consultation signées du nom du médecin : le patient les voit sans pouvoir les modifier.
- Ajustement des objectifs du patient, analyse IA et export PDF à son nom.

---

## Scénarios de test

| # | Connexion | Étapes | Résultat attendu |
| --- | --- | --- | --- |
| 1 | `patient@medicare.com` | Menu → Suivi santé et nutrition | Tableau de bord rempli : IMC « corpulence normale », courbes, nutrition et hydratation du jour |
| 2 | `patient@medicare.com` | Mesures → Ajouter une mesure → température 38,6 | La mesure apparaît ; l'analyse santé IA affiche une alerte « Hyperthermie » |
| 3 | `patient@medicare.com` | Nutrition → Ajouter un repas → Base d'aliments → Riz blanc cuit 150 g | Calories et macronutriments calculés automatiquement |
| 4 | `patient@medicare.com` | Icône PDF → 30 derniers jours | Rapport PDF avec logo, statistiques et historiques |
| 5 | `patient2@medicare.com` | Mesures | La mesure du 12/11 porte « Mesure prise en consultation par Dr Ahmed » et un cadenas (non modifiable) |
| 6 | `dr.ahmed@medicare.com` | Suivi santé et nutrition des patients | Deux patients : Patient Test (traitement) et Amine Trabelsi (rendez-vous, alertes) |
| 7 | `dr.ahmed@medicare.com` | Ouvrir Amine Trabelsi → Mesure de consultation | La mesure est enregistrée et visible chez le patient |
| 8 | `dr.ahmed@medicare.com` | Ouvrir un patient → Nutrition | Journal et hydratation en lecture seule (aucun bouton d'ajout) |
| 9 | `dr.sarah@medicare.com` | Suivi santé et nutrition des patients | Uniquement Sonia Mejri : Dr Sarah ne voit pas les patients de Dr Ahmed |
| 10 | `dr.ahmed@medicare.com` | Déposer une ordonnance pour un patient | Le patient apparaît dans « Patients suivis » et ses médicaments dans son espace |
| 11 | `patient@medicare.com` | Rendez-vous → nouveau rendez-vous avec Dr Sarah | Le rendez-vous est créé ; Dr Sarah peut alors consulter le suivi santé de ce patient |
| 12 | `secretaire.ahmed@medicare.com` | Rendez-vous → Espace secrétaire | Gestion des rendez-vous des patients de Dr Ahmed uniquement |
| 13 | `admin@medicare.com` | Profil → Sécurité et accès → Administration | Demandes de rôle, fusions, doublons, incidents et journal d'audit |
| 14 | `admin@medicare.com` | Rendez-vous → Espace secrétaire → Affectations | Affecter ou retirer une secrétaire à un médecin |

Commandes de vérification automatique :

```bash
cd backend && mvn test
cd frontend && flutter analyze && flutter test
```

---

## Documentation technique

### Architecture

```text
Flutter (Android / iOS / Web / Windows)
   |  HTTP/JSON + JWT (Authorization: Bearer <token>)
   v
Spring Boot REST API  ──>  Ollama (IA locale, facultatif)
   |  JPA / Hibernate
   v
H2 (dev) / PostgreSQL (production)
```

### Routes du module Suivi santé et nutrition

| Ressource | Routes | Paramètre `patientId` (médecin) |
| --- | --- | --- |
| Mesures | `GET/POST /api/health-records`, `GET /api/health-records/history?days=`, `PUT/DELETE /api/health-records/{id}` | GET et POST |
| Objectifs | `GET/POST /api/health-goals` | Oui |
| Repas | `GET/POST /api/meals`, `GET /api/meals/today`, `/history`, `/stats/today`, `/stats/daily`, `PUT/DELETE /api/meals/{id}` | Lectures |
| Hydratation | `GET/POST /api/hydration`, `GET /api/hydration/today`, `/history`, `DELETE /api/hydration/{id}` | Lectures |
| Base d'aliments | `GET /api/foods?search=` | — |
| Patients du médecin | `GET /api/health/patients` | — |
| IA | `GET /api/health/ai/analyze`, `POST /api/nutrition/ai/analyze`, `POST /api/nutrition/chat` | Analyse santé |


### 1. Base de données de développement

Le profil `dev` utilise H2 dans un fichier local :
`backend/data/medicare.mv.db`. Les données restent disponibles après l'arrêt
du backend. Aucune installation de PostgreSQL ni aucun mot de passe de base de
données ne sont nécessaires. Hibernate crée/met à jour le schéma au démarrage
(`ddl-auto: update`).

La console H2 est disponible à `http://localhost:8082/h2-console` pendant que
le backend tourne. Utilisez l'URL JDBC
`jdbc:h2:file:./data/medicare;DB_CLOSE_ON_EXIT=FALSE`, l'utilisateur `sa` et
un mot de passe vide. Le chemin du fichier est relatif au dossier `backend`.

### 2. Backend

```bash
cd backend
mvn spring-boot:run
```

ou :

```bash
mvn spring-boot:run
```

API : http://localhost:8082

Le port API peut être modifié avec la variable d'environnement `SERVER_PORT`.
Pour Android Emulator, le frontend utilise `10.0.2.2:8082` pour atteindre le localhost de la machine.

### 3. Frontend

Le dossier Flutter contient le code applicatif. Générer les fichiers plateformes :

```bash
cd frontend
flutter pub get
flutter run
```

Pour un téléphone physique, préciser l'adresse IP locale de la machine :

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8082/api
```

Remplacer `192.168.1.10` par l'adresse du PC qui exécute le backend.

Si le port `8082` est déjà utilisé, démarrer le backend sur un autre port :

```bash
cd backend
java -jar target/medicare-backend-1.0.0.jar --spring.profiles.active=dev --server.port=8099
```

Puis lancer Flutter dans un second terminal depuis le dossier `frontend` :

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8099/api
```

L'adresse doit inclure `/api`. Pour l'émulateur Android, utiliser
`http://10.0.2.2:8099/api`. Après un changement de `--dart-define`, arrêter
l'application Flutter et la relancer avec la nouvelle commande.

### Comptes

Inscription via l'écran Register. Le mot de passe est hashé avec BCrypt.
Le token JWT est retourné après login et envoyé ensuite dans :

```text
Authorization: Bearer <token>
```

### Authentification et récupération du compte

Les écrans de connexion, d'inscription et de récupération s'adaptent au mobile
et au bureau. Ils proposent le remplissage automatique, l'affichage des mots de
passe, une validation immédiate et des messages d'erreur en français. L'indicateur
de robustesse est un conseil ; les nouveaux mots de passe acceptent au minimum
12 caractères et au maximum 72 octets UTF-8 (limite de BCrypt).

Pour activer la récupération par email, configurer le serveur SMTP du backend :

```text
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USERNAME=compte-smtp
MAIL_PASSWORD=mot-de-passe-smtp
MAIL_FROM=MediCare <noreply@example.com>
MAIL_SMTP_AUTH=true
MAIL_STARTTLS=true
```

Sans configuration SMTP, l'API renvoie `503` et l'interface signale que l'envoi
est indisponible. Aucun email n'est simulé. Pour un serveur SMTP local sans
authentification, définir `MAIL_SMTP_AUTH=false` et `MAIL_STARTTLS=false`.

#### Lancement Windows avec Gmail

Arrêter le backend en cours avec `Ctrl+C`, puis lancer depuis la racine du projet :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\start-dev-email.ps1
```

Le script cherche Java dans le PATH, `JAVA_HOME` ou les JDK du dossier utilisateur,
et Maven dans le PATH ou l'installation IntelliJ IDEA. Il reconstruit le JAR,
demande l'adresse du **compte Google qui a créé le mot de passe d'application**,
puis le code Google de 16 caractères en saisie masquée. Les espaces du code sont
retirés. Il transmet la configuration au processus Java et lance le profil `dev`
sur le port `8082`. Aucun identifiant n'est écrit dans un fichier ou le registre.
Le profil `dev` utilise H2 fichier (`backend/data/medicare.mv.db`) et conserve
les données après l'arrêt du backend. Aucune configuration PostgreSQL n'est
requise. Les tests automatisés utilisent leur propre base H2 isolée.

Le contrôle SMTP au démarrage établit la connexion et vérifie l'authentification,
sans envoyer d'email. En cas de refus, le backend s'arrête avec la cause dans
le terminal. Une `AuthenticationFailedException` indique un problème de compte
ou de mot de passe d'application ; un délai réseau indique un problème d'accès
SMTP. Pour utiliser un autre port, ajouter `-Port <port>` à la commande.

Dans un second terminal, lancer l'interface sur le même port API :

```powershell
cd frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8082/api
```

Les mots de passe d'application exigent la validation Google en deux étapes.
Le mot de passe d'application est distinct du mot de passe de connexion Gmail.
[Création du code Google](https://support.google.com/accounts/answer/185833?hl=fr).

#### Diagnostic des erreurs email

Le backend renvoie toujours `503` en cas d'indisponibilité email, avec un code
stable traduit dans l'interface. Les journaux indiquent la catégorie et les
réglages à vérifier, sans contenu d'email, OTP, identifiant SMTP ou mot de passe.

| Code | Vérification |
| --- | --- |
| `MAIL_NOT_CONFIGURED` | Variables `MAIL_HOST`, `MAIL_FROM`, et identifiants si l'authentification SMTP est activée ; redémarrer le backend dans le terminal configuré. |
| `MAIL_AUTHENTICATION_FAILED` | Même compte Google pour `MAIL_USERNAME` et le code dans `MAIL_PASSWORD` ; utiliser le mot de passe d'application. |
| `MAIL_CONNECTION_FAILED` | Accès réseau au serveur SMTP et port configuré ; `Test-NetConnection smtp.gmail.com -Port 587` sous Windows. |
| `MAIL_TLS_FAILED` | Réglages STARTTLS, horloge et certificats Java ; conserver la validation des certificats. |
| `MAIL_SEND_FAILED` | Adresse d'expédition, permissions et limites du fournisseur email. |

Les variables définies dans un terminal ne sont pas transmises à un backend déjà
lancé depuis IntelliJ ou un autre terminal. Il faut redémarrer ce backend avec
les nouveaux paramètres. Une erreur de connexion Flutter au serveur MediCare est
distincte : vérifier `http://localhost:8082/api/health` et `API_BASE_URL`.

Le parcours utilise deux routes publiques :

- `POST /api/auth/forgot-password` avec `email` : envoie un code à 6 chiffres si
  le compte existe. La réponse est identique pour une adresse inconnue. Un seul
  envoi par compte est autorisé par minute.
- `POST /api/auth/reset-password` avec `email`, `code` et `newPassword` : vérifie
  le code et change le mot de passe. Le code expire après 10 minutes, accepte
  au maximum 5 essais et devient inutilisable après validation. Il est stocké
  sous forme de hash BCrypt. Les JWT antérieurs sont invalidés et l'utilisateur
  doit se reconnecter.

Une panne réseau pendant la restauration de session conserve le jeton et permet
de réessayer. Une réponse `401` supprime la session locale et protège les écrans
privés.

Vérifications :

```bash
cd backend
mvn test
```

```bash
cd frontend
flutter analyze
flutter test
```

Les tests backend utilisent H2 et un service d'email simulé ; ils ne nécessitent
ni PostgreSQL ni identifiants SMTP et n'envoient aucun email réel.


### Authentification avancée

Après mise à jour, recompiler le backend (`mvn clean package`) et redémarrer
le JAR, puis relancer Flutter. Le nouveau frontend utilise de nouvelles routes.

#### Vérification de l’identité

- Une inscription crée un compte **Patient**, vérifie l’email par OTP et active
  la double vérification. Aucun JWT n’est délivré avant le code email.
- À la connexion, les comptes avec double vérification reçoivent un OTP après
  validation du mot de passe. Un code de récupération peut remplacer cet OTP.
- Le bouton « Connexion avec un code de récupération » vérifie le mot de passe
  et un code de secours, sans dépendre de l’envoi SMTP. Il permet de se connecter
  même lorsque la messagerie est indisponible.
- Les anciens comptes peuvent vérifier leur email et activer la double
  vérification depuis **Profil → Sécurité et accès → Protection**.
- Les OTP expirent après 10 minutes, sont limités à 5 essais et sont liés à
  un compte, une action, un email et une version de sécurité. Un renvoi attend
  au moins 60 secondes et invalide le code précédent.
- Dix codes de récupération de 128 bits sont affichés une seule fois. Chaque
  code est utilisable une fois et seul son hash est conservé. Leur renouvellement
  exige le mot de passe et une nouvelle preuve email ; les anciens codes et
  sessions sont alors invalidés.
- **Connexion sans mot de passe** : cliquer sur « Me connecter par code email ».
  Si la double vérification est active, un code de récupération est également
  exigé. Le parcours sans mot de passe ne contourne donc pas cette protection.
- Les demandes sans mot de passe emploient une réponse générique, sans renvoyer
  de profil ni de jeton avant validation. Les OTP de connexion ne peuvent pas servir à une fusion ou à une
  modification de sécurité.

L’envoi SMTP doit être configuré pour ces parcours. Aucun code n’est affiché
par le backend, écrit dans les journaux ou envoyé fictivement en développement.
Les codes sont transmis au service email configuré lors des actions de l’utilisateur.

#### Identifiants et rapprochement de comptes

L’email et l’identifiant facultatif sont normalisés et contrôlés sans distinction
majuscules/minuscules. Les contraintes uniques de base de données protègent
également les inscriptions concurrentes. Un identifiant ambigu est refusé.

**Mes comptes** permet de demander un rapprochement en fournissant l’email du
second compte et un motif. Il faut ensuite saisir les codes envoyés aux deux
adresses. La propriété des deux comptes doit être prouvée avant qu’un
administrateur puisse examiner la fusion.

Règles de fusion :

- Aucune fusion automatique. Les correspondances proposées utilisent les
  identifiants de comptes vérifiés ou une demande avec deux preuves. Les variantes
  publiques `@gmail.com` avec points ou suffixes `+` constituent aussi un signal
  de boîte commune, uniquement lorsque les deux emails sont vérifiés. Cette règle
  ne s’applique pas aux domaines d’organisation et ne prouve pas à elle seule
  que deux profils désignent la même personne. Voir la [documentation Gmail](https://support.google.com/mail/answer/7436150)
  et les [variantes avec suffixe](https://gmail.googleblog.com/2008/03/2-hidden-ways-to-get-more-from-your.html).
  Un nom,
  un téléphone déclaré ou une date de naissance ne constitue pas une preuve.
- Un administrateur distinct des comptes concernés doit confirmer la décision
  et son motif. Il vérifie que les comptes appartiennent bien à la même personne.
- La fusion est limitée à deux comptes Patient actifs. Les droits Médecin et
  Administrateur ne sont jamais combinés ni hérités.
- Chaque valeur de profil en conflit doit être choisie explicitement. Les champs
  vides du compte conservé peuvent être complétés avec ceux du second compte.
- L’email principal, le mot de passe et les codes de récupération du compte
  conservé restent les références. Tous les rendez-vous, médicaments et mesures
  sont transférés, sans déduplication destructive des dossiers médicaux.
- Le second compte devient une identité de connexion liée au compte conservé ;
  ses anciens identifiants restent réservés. Ses anciennes informations de
  connexion ne permettent plus d’ouvrir une session autonome.
- Les sessions des deux comptes sont révoquées. La double vérification reste
  active si elle était active sur l’un des deux comptes.
- Une preuve datant de plus de 24 heures, un changement d’email/de sécurité ou
  un incident invalide la demande. Les décisions sont enregistrées dans le journal.

Le remplacement de l’email d’authentification depuis l’édition ordinaire du
profil est bloqué : il ne doit pas permettre de rediriger les codes de sécurité.

#### Politique des mots de passe

Les nouveaux mots de passe exigent au moins 12 caractères et au maximum
72 octets UTF-8. La connexion aux anciens mots de passe n’impose pas rétroactivement
une nouvelle longueur. L’indicateur de robustesse est calculé localement ; aucun
mot de passe en clair n’est conservé dans la base ou dans l’historique.

La vérification des fuites utilise [Pwned Passwords](https://haveibeenpwned.com/API/v3#PwnedPasswords)
par k-anonymat : seuls les 5 premiers caractères du hash SHA-1 sont envoyés en
HTTPS avec `Add-Padding: true`. Le mot de passe et son hash complet restent locaux.
Cette recherche n’est effectuée que lors d’une création ou d’un changement,
pas à chaque caractère tapé. SHA-1 sert uniquement à cette requête ; les mots
de passe stockés et leur historique utilisent BCrypt.

```text
PASSWORD_COMPROMISE_CHECK_ENABLED=true
PASSWORD_HISTORY_SIZE=5
AUTH_RATE_LIMIT_ENABLED=true
```

La vérification des fuites est activée par défaut et refuse une création ou
modification si le service est indisponible. Le mot de passe courant et les quatre
précédents sont refusés avec la configuration par défaut. La taille d’historique
est configurable de 0 à 20 ; 0 désactive l’historique antérieur mais conserve
l’interdiction de choisir à nouveau le mot de passe courant.

Un administrateur peut déclarer un **incident confirmé**, avec justification.
Les sessions et codes de récupération sont révoqués ; les connexions par mot de
passe et sans mot de passe sont bloquées jusqu’à une réinitialisation réussie.
Aucune expiration périodique arbitraire n’est imposée.

Le limiteur autorise au maximum 60 requêtes d’authentification par adresse IP
sur 5 minutes, en plus des limites par compte et par OTP. Il est en mémoire,
par instance ; une installation distribuée doit partager cette limitation.

#### Rôles et administration

L’inscription propose Patient, Médecin et Administrateur. Le rôle Médecin est
attribué automatiquement lorsque l’utilisateur le demande ; l’adresse email doit
toujours être vérifiée pour accéder au compte. Les anciennes demandes Médecin en
attente sont automatiquement résolues au démarrage du backend. Les demandes de
rôle Administrateur restent soumises à l’approbation d’un autre administrateur.
L’auto-approbation administrateur est interdite et une décision ne peut pas être rejouée.
L’ancien endpoint d’attribution directe des rôles reste bloqué.

Pour initialiser un premier administrateur, un opérateur du serveur peut définir :

```text
BOOTSTRAP_ADMIN_EMAIL=<email dont vous contrôlez la boîte>
BOOTSTRAP_ADMIN_PASSWORD=<phrase de passe personnelle unique, 12 caractères minimum>
```

Au démarrage, un nouveau compte administrateur est créé si l’email n’existe pas.
Sa première connexion exige une vérification email. Un compte existant ne peut
être promu par cette configuration que si son email est déjà vérifié ; son mot
de passe n’est jamais remplacé. L’opération est auditée. Retirer les variables de
bootstrap après initialisation d’une base persistante pour éviter une nouvelle
promotion involontaire après un changement de rôle ultérieur.

Le journal d’administration conserve auteur, compte concerné, action, date et
motif, sans mots de passe, OTP ni codes de récupération. Les endpoints
`/api/security/admin/**` exigent un administrateur avec email vérifié.

Hors profil `dev`, `JWT_SECRET` est obligatoire et doit contenir au moins
32 octets. Le profil `dev` utilise H2 dans un fichier local
(`backend/data/medicare.mv.db`) et une clé locale de développement ; les données
restent après le redémarrage. Une base PostgreSQL et une clé secrète configurée
sont nécessaires pour l'environnement de production.

#### Routes principales

| Parcours | Routes |
| --- | --- |
| Inscription et connexion | `POST /api/auth/register`, `/login`, `/verify` |
| Sans mot de passe | `POST /api/auth/passwordless/request` puis `/api/auth/verify` |
| Code de récupération | `POST /api/auth/mfa/recover` après le mot de passe ou `/api/auth/login/recovery` sans envoi email |
| Renvoi de code | `POST /api/auth/challenges/{id}/resend` |
| Ordonnances et planning médecin | Analyser l'ordonnance localement sans patient, puis sélectionner un patient obligatoire avant l'envoi; les cartes du tableau de bord ouvrent les patients suivis et les prescriptions; modifier ou archiver ses ordonnances sans effacer le planning ni l'historique; le patient consulte son agenda en lecture seule |
| Patients suivis | `GET /api/prescriptions/patients/followed` (médecin) |
| Documents d’ordonnance | `GET /api/prescriptions/{id}/document` (patient concerné, médecin prescripteur ou administrateur) |
| Protection du compte | `GET /api/security`, `POST /api/security/challenge`, `/confirm` |
| Rôles | `GET/POST /api/security/role-requests` (Médecin attribué automatiquement ; Administrateur soumis à approbation) |
| Rapprochement | `GET/POST /api/security/merges`, `POST /api/security/merges/{id}/verify`, `/cancel` |
| Décisions | `POST /api/security/admin/role-requests/{id}/decision`, `/api/security/admin/merges/{id}/decision` |
| Résolution des identités | `GET /api/security/admin/duplicates` |
| Incidents et audit | `POST /api/security/admin/users/{id}/incident`, `GET /api/security/admin/audit` |

Les tests automatisés simulent SMTP et Pwned Passwords. Aucun email réel ni mot
de passe réel n’est envoyé pendant les tests. Les tests couvrent notamment les
preuves séparées, le rejeu, la concurrence, les refus de privilèges, la conservation
des dossiers et l’invalidation des sessions.
