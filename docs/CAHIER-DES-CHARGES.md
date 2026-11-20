# Cahier des charges · MediCare

**Application mobile de suivi médical**

- **Projet :** MediCare
- **Cours :** Développement mobile (Flutter)
- **Équipe :** Eya Rahmeni, Mohamed Dhia Cherni, Ameni Rahmeni, Mohamed Aziz Ouerfelli, Iyed Gammar
- **Version :** 20/11/2026

## Sommaire

- [1. Présentation du projet](#1-présentation-du-projet)
- [2. Équipe et répartition des modules](#2-équipe-et-répartition-des-modules)
- [3. Acteurs et droits](#3-acteurs-et-droits)
- [4. Besoins fonctionnels](#4-besoins-fonctionnels)
- [5. Besoins non fonctionnels](#5-besoins-non-fonctionnels)
- [6. Contraintes techniques](#6-contraintes-techniques)
- [7. Architecture et données](#7-architecture-et-données)
- [8. Livrables](#8-livrables)
- [9. Critères de validation (recette)](#9-critères-de-validation-recette)
- [10. Phases de réalisation](#10-phases-de-réalisation)

---

## 1. Présentation du projet

| Élément | Description |
|---|---|
| Nom | MediCare |
| Type | Application mobile de suivi médical (Android, également utilisable dans un navigateur) |
| Cadre | Projet du cours de développement mobile (Flutter) |
| Utilisateurs | Patients, médecins, secrétaires médicales, administrateur |
| Principe | Un compte unique, cinq modules complémentaires, une API sécurisée et une base de données commune |

**Contexte.** Le suivi d'un patient est aujourd'hui dispersé : rendez-vous par téléphone, ordonnances papier, traitements oubliés, mesures notées à la main, documents égarés. Le médecin n'a pas de vue d'ensemble entre deux consultations.

**Objectif général.** Réunir dans une seule application tout ce qui relie un patient à ses médecins : comptes et sécurité, rendez-vous, traitements, suivi de santé et de nutrition, documents et notifications, avec une **synchronisation permanente** entre le médecin et ses patients.

**Objectifs mesurables**

- Le patient retrouve en un seul endroit ses rendez-vous, son planning de prises, ses mesures et ses ordonnances.
- Toute action du médecin (ordonnance, planning, mesure de consultation) est visible par le patient sans délai, avec une notification.
- Toute action du patient (prise confirmée, mesure, repas, document) est visible par les médecins qui le suivent.
- Aucune donnée d'un patient n'est accessible à un médecin qui ne le suit pas.

## 2. Équipe et répartition des modules

| Membre | Module | Responsabilités |
|---|---|---|
| **Eya Rahmeni** | M1 · Authentification et sécurité | Inscription, connexion, double vérification, codes de récupération, profil, rôles, fusion de comptes, journal d'audit |
| **Mohamed Dhia Cherni** | M2 · Rendez-vous | Prise et gestion des rendez-vous, agenda, espace secrétaire, rappels automatiques, risque d'absence |
| **Ameni Rahmeni** | M3 · Médicaments | Ordonnances, préremplissage du planning, planning de prises, confirmation des prises, observance, stock |
| **Mohamed Aziz Ouerfelli** | M4 · Suivi santé et nutrition | Mesures, IMC, objectifs, nutrition, hydratation, IA santé, dossier patient côté médecin, règle commune de suivi |
| **Iyed Gammar** | M5 · Notifications et documents | Notifications, rappels, documents médicaux, partage, analyse de documents, synchronisation des ordonnances |

Chaque membre est responsable de la conception, du développement (Flutter et Spring Boot), des tests et de la documentation de son module, ainsi que de son intégration avec les autres.

## 3. Acteurs et droits

| Acteur | Droits principaux |
|---|---|
| Visiteur | Créer un compte, se connecter, récupérer son mot de passe |
| Patient (`USER`) | Gérer ses rendez-vous, confirmer ses prises, saisir ses mesures, repas et eau, gérer ses documents et ses médecins, recevoir ses notifications |
| Secrétaire (`USER` affecté) | Gérer l'agenda des médecins qui lui sont affectés |
| Médecin (`DOCTOR`) | Envoyer des ordonnances, créer le planning de prises, consulter le dossier complet de ses patients suivis, enregistrer des mesures de consultation, créer des rappels pour eux |
| Administrateur (`ADMIN`) | Valider rôles et fusions, affecter les secrétaires, consulter l'audit, administrer les notifications |

## 4. Besoins fonctionnels

Priorité : **Essentielle** (indispensable à la livraison) ou **Importante** (forte valeur ajoutée).

**M1 · Authentification et sécurité (Eya Rahmeni)**

| Réf. | Besoin | Priorité |
|---|---|---|
| F1.1 | Créer un compte avec vérification de l'email par code | Essentielle |
| F1.2 | Se connecter par mot de passe, par code email ou par code de récupération | Essentielle |
| F1.3 | Réinitialiser un mot de passe oublié (code valable 10 min, 5 essais) | Essentielle |
| F1.4 | Activer la double vérification et obtenir 10 codes de récupération | Importante |
| F1.5 | Modifier son profil et son mot de passe | Essentielle |
| F1.6 | Demander un rôle ou une fusion de comptes ; validation par l'administrateur | Importante |
| F1.7 | Consulter le journal d'audit et déclarer un incident (administrateur) | Importante |

**M2 · Rendez-vous (Mohamed Dhia Cherni)**

| Réf. | Besoin | Priorité |
|---|---|---|
| F2.1 | Prendre, modifier, annuler et supprimer un rendez-vous avec un médecin | Essentielle |
| F2.2 | Voir ses rendez-vous en agenda ou en liste, avec recherche et filtres | Essentielle |
| F2.3 | Refuser les conflits d'horaire | Essentielle |
| F2.4 | Gérer l'agenda d'un médecin depuis l'espace secrétaire | Importante |
| F2.5 | Suggérer une spécialité selon le motif et estimer le risque d'absence | Importante |
| F2.6 | Envoyer automatiquement un rappel avant le rendez-vous | Importante |

**M3 · Médicaments (Ameni Rahmeni)**

| Réf. | Besoin | Priorité |
|---|---|---|
| F3.1 | Envoyer une ordonnance (photo ou PDF) à un patient suivi | Essentielle |
| F3.2 | Préremplir le planning du patient à partir de l'ordonnance, avec vérification du médecin | Importante |
| F3.3 | Ajouter un médicament et ses horaires au planning d'un patient | Essentielle |
| F3.4 | Afficher au patient son traitement et ses prises du jour | Essentielle |
| F3.5 | Permettre au patient de confirmer chaque prise (effectuée, manquée, ignorée, reportée) | Essentielle |
| F3.6 | Suivre l'observance par patient (médecin) et ses statistiques (patient) | Essentielle |
| F3.7 | Gérer le stock et alerter quand il est bas | Importante |
| F3.8 | Rappeler les prises par notification sur le téléphone | Importante |

**M4 · Suivi santé et nutrition (Mohamed Aziz Ouerfelli)**

| Réf. | Besoin | Priorité |
|---|---|---|
| F4.1 | Saisir, modifier et supprimer des mesures (poids, tension, pouls, température, glycémie) | Essentielle |
| F4.2 | Lire une mesure par photo de l'appareil, avec validation du patient | Importante |
| F4.3 | Afficher le tableau de bord, l'IMC (catégories OMS), les tendances et les courbes | Essentielle |
| F4.4 | Définir des objectifs (taille, poids cible, calories, eau) | Essentielle |
| F4.5 | Tenir un journal alimentaire et suivre l'hydratation | Essentielle |
| F4.6 | Analyser la santé par IA avec alertes, et reconnaître les aliments par photo ou description | Importante |
| F4.7 | Exporter un rapport PDF et des statistiques sur 7 jours à 6 mois | Importante |
| F4.8 | Donner au médecin un dossier patient (santé, médicaments, documents) et les mesures de consultation | Essentielle |

**M5 · Notifications et documents (Iyed Gammar)**

| Réf. | Besoin | Priorité |
|---|---|---|
| F5.1 | Recevoir des notifications après chaque action qui concerne l'utilisateur | Essentielle |
| F5.2 | Créer, reporter et annuler des rappels ; le médecin pour ses patients | Importante |
| F5.3 | Déposer, consulter, classer et supprimer ses documents médicaux | Essentielle |
| F5.4 | Retrouver toutes les ordonnances envoyées par ses médecins dans Documents → Ordonnances | Essentielle |
| F5.5 | Donner aux médecins qui suivent le patient l'accès en lecture à ses documents | Essentielle |
| F5.6 | Partager un document par lien QR protégé par PIN, avec expiration et révocation | Importante |
| F5.7 | Analyser un document par IA et proposer un rappel de suivi, à confirmer | Importante |

**Synchronisation médecin ↔ patient (transverse)**

| Réf. | Besoin | Priorité |
|---|---|---|
| S.1 | Une seule règle de suivi médecin ↔ patient pour tous les modules (traitement, rendez-vous ou « Mes médecins ») | Essentielle |
| S.2 | Ordonnance envoyée → visible chez le patient avec notification | Essentielle |
| S.3 | Planning créé par le médecin → visible chez le patient avec notification | Essentielle |
| S.4 | Prises confirmées par le patient → visibles dans l'observance du médecin | Essentielle |

## 5. Besoins non fonctionnels

| Domaine | Exigence |
|---|---|
| Sécurité | Jeton JWT sur chaque requête ; mots de passe de 12 caractères minimum, hachés (BCrypt), refus des mots de passe divulgués ; secrets jamais stockés en clair ; limitation des tentatives ; révocation des sessions |
| Confidentialité | Un médecin ne voit que ses patients suivis ; un patient ne voit que ses données ; les photos analysées par l'IA ne sont pas conservées ; l'IA tourne en local (aucune donnée de santé envoyée à un service externe) |
| Fiabilité | Rien n'est enregistré à partir de l'IA sans validation humaine ; une notification qui échoue n'annule jamais l'action d'origine |
| Performance | Réponse de l'API sous 1 s pour les écrans courants ; réponses IA en quelques secondes une fois le modèle chargé |
| Ergonomie | Interface en français, messages d'erreur clairs, confirmations avant les actions importantes, utilisable sur téléphone et en navigateur |
| Disponibilité | Fonctionnement en Wi-Fi local ; mode démonstration si l'IA n'est pas disponible |
| Maintenabilité | Code organisé par module (`features/…` côté Flutter, `com.medicare.…` côté serveur), tests automatisés, documentation à jour |
| Portabilité | Un seul code Flutter pour Android et le web |

## 6. Contraintes techniques

| Élément | Choix imposé ou retenu |
|---|---|
| Application | Flutter (Dart), Riverpod, Dio, `flutter_secure_storage` |
| Serveur | Spring Boot 3.5, Java 21, Spring Security, JWT, JPA/Hibernate |
| Base de données | PostgreSQL 18 (`app_medicare`), H2 pour la démonstration |
| IA | Ollama en local (`llama3.2`, `llava`), Tesseract pour l'OCR |
| Appareil de test | Téléphone Android CRT NX1, connecté au PC par Wi-Fi |
| Gestion du code | Git, dépôt GitHub `app-medicare` |

## 7. Architecture et données

```text
Téléphone Android ou navigateur  ──Wi-Fi──►  API Spring Boot (port 8082)  ──►  PostgreSQL app_medicare
Application Flutter (jeton JWT)               Sécurité, règles d'accès         29 tables reliées à users
                                              ├─► IA locale Ollama (llama3.2, llava)
                                              ├─► OCR local Tesseract (ordonnances)
                                              └─► Fichiers des documents médicaux
```

| Module | Tables principales |
|---|---|
| M1 · Authentification | `users`, `email_challenge`, `recovery_code`, `password_history`, `role_change_request`, `account_merge_request`, `security_audit_event` |
| M2 · Rendez-vous | `appointment`, `appointment_secretary_doctors` |
| M3 · Médicaments | `prescription`, `medication`, `medication_reminder`, `medication_stock_entry`, `doctor_patient_assignments` |
| M4 · Suivi santé et nutrition | `health_record`, `health_goal`, `meal`, `hydration`, `food` |
| M5 · Notifications et documents | `notifications`, `reminders`, `patient_doctor`, `medical_documents`, `document_shares`, `document_analyses` |

**Règle commune de suivi :** un médecin suit un patient s'il lui a prescrit un traitement, s'il a un rendez-vous non annulé avec lui, ou si le patient l'a ajouté dans « Mes médecins ». Cette règle unique protège les données de tous les modules.

## 8. Livrables

| Livrable | Contenu |
|---|---|
| Code source | Dépôt GitHub (`frontend/` Flutter, `backend/` Spring Boot) |
| Application Android | APK installable (`app-release.apk`) |
| Application web | Version compilée (`frontend/build/web`) |
| Base de données | Schéma créé automatiquement, script de migration `backend/db/migrations/` |
| Documentation | Ce cahier des charges, le document de vision technique (modules, données, compilation), `README.md`, `RUN.md` |
| Tests | 80 tests backend et 61 tests Flutter |

## 9. Critères de validation (recette)

| Critère | Comment le vérifier |
|---|---|
| Tous les tests passent | `mvn test` (80/80) et `flutter test` (61/61) |
| Parcours patient complet | Inscription → rendez-vous → prise confirmée → mesure → document, sur le téléphone en Wi-Fi |
| Parcours médecin complet | Patients suivis → dossier patient → envoi d'une ordonnance → ajout au planning → observance |
| Synchronisation | L'ordonnance et le médicament envoyés par le médecin apparaissent chez le patient avec une notification ; la prise confirmée par le patient apparaît dans l'observance du médecin |
| Confidentialité | Un médecin qui ne suit pas un patient reçoit `404` sur ses données ; un patient ne peut pas toucher aux prises d'un autre |
| Persistance | Chaque action faite sur le téléphone est retrouvée dans PostgreSQL `app_medicare` |
| IA | Les valeurs proposées par l'IA ne sont enregistrées qu'après validation ; une photo sans appareil est refusée |

## 10. Phases de réalisation

1. **Analyse** : besoins par module, acteurs, règles d'accès.
2. **Conception** : modèle de données, API, maquettes des écrans.
3. **Développement par module** : chaque membre réalise son module (Flutter et serveur).
4. **Intégration** : regroupement des cinq modules, règle commune de suivi, synchronisation médecin ↔ patient.
5. **Tests et recette** : tests automatisés, tests sur le téléphone en Wi-Fi, vérification dans PostgreSQL.
6. **Livraison** : APK, version web, documentation et présentation.
