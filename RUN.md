# Lancer le projet MediCare

## Module M5 intégré dans cette destination

Les notifications, rappels et documents de `D:\DevMobile\Medicare` sont intégrés dans
`D:\DecMobilFinal\app-medicare`, en conservant les modules M1–M4 de ce dépôt.
Le [rapport d'intégration](docs/M5-INTEGRATION.md) fournit le SQL, la matrice des rôles,
les fichiers concernés et les vérifications. Sur ce poste, lancer depuis
`D:\DecMobilFinal\app-medicare\backend` pour l'API sur **8082**, puis depuis
`D:\DecMobilFinal\app-medicare\frontend` pour Flutter.

Chemin du projet : `C:\Users\g701951\Downloads\App-mobile-MediCare-main\App-mobile-MediCare-main`

Prérequis : Java 21+, Maven, Flutter, Chrome ou un émulateur Android.

## 1. Backend (Spring Boot, port 8082)

### Mode dev (recommandé) : base H2 locale, aucune installation de base de données

```powershell
cd C:\Users\g701951\Downloads\App-mobile-MediCare-main\App-mobile-MediCare-main\backend
mvn clean spring-boot:run "-Dspring-boot.run.profiles=dev"
```

- API : http://localhost:8082/api
- Console H2 : http://localhost:8082/h2-console (JDBC URL `jdbc:h2:file:./data/medicare`, user `sa`, sans mot de passe)
- Les comptes de démonstration (secrétaires + médecins) sont créés **uniquement** en mode dev.

### Mode normal : PostgreSQL

La base `medicare` doit exister sur `localhost:5432`.

```powershell
cd C:\Users\g701951\Downloads\App-mobile-MediCare-main\App-mobile-MediCare-main\backend
$env:DB_USERNAME="postgres"
$env:DB_PASSWORD="postgres"
$env:JWT_SECRET="remplacer-par-une-longue-cle-secrete-de-32-caracteres-minimum"
mvn clean spring-boot:run
```

### Optionnel : créer un administrateur au démarrage

Avant `mvn spring-boot:run` :

```powershell
$env:BOOTSTRAP_ADMIN_EMAIL="admin@medicare.com"
$env:BOOTSTRAP_ADMIN_PASSWORD="choisir-un-mot-de-passe-fort"
```

## 2. Frontend (Flutter)

Dans un **deuxième** terminal :

```powershell
cd C:\Users\g701951\Downloads\App-mobile-MediCare-main\App-mobile-MediCare-main\frontend
flutter pub get
flutter run -d chrome
```

Autres cibles :

```powershell
flutter devices            # lister les appareils
flutter run -d windows     # application Windows
flutter run -d emulator-5554   # émulateur Android (l'API passe par 10.0.2.2:8082)
```

## 3. Comptes de test (mode dev)

| Rôle | Email | Mot de passe | Médecin rattaché |
|---|---|---|---|
| Secrétaire | secretaire.ahmed@medicare.com | Secret@2026 | Dr Ahmed |
| Secrétaire | secretaire.sarah@medicare.com | Secret@2026 | Dr Sarah |
| Médecin | dr.ahmed@medicare.com | Doctor@2026 | - |
| Médecin | dr.sarah@medicare.com | Doctor@2026 | - |
| Administrateur | admin@medicare.com | Admin@2026 | - |
| Patient | patient@medicare.com (Patient Test) | Patient@2026 | Dr Ahmed (traitement prescrit) |
| Patient | patient2@medicare.com (Amine Trabelsi) | Patient@2026 | Dr Ahmed (rendez-vous) |
| Patient | patient3@medicare.com (Sonia Mejri) | Patient@2026 | Dr Sarah (traitement + rendez-vous) |

Une secrétaire voit l'icône « Espace secrétaire » dans la page **Rendez-vous** et ne gère que les rendez-vous de son médecin.

Les trois patients sont préremplis (mode dev) avec 30 jours de mesures, 14 jours de repas et d'hydratation, et des objectifs, avec des profils différents :
- **Patient Test** : constantes normales, poids en baisse ;
- **Amine Trabelsi** : hypertension et surpoids, plus une mesure prise en consultation par Dr Ahmed ;
- **Sonia Mejri** : glycémie élevée et fièvre récente (alertes).

Un médecin voit le suivi santé d'un patient s'il lui a prescrit un traitement (Médicaments) ou s'il a un rendez-vous non annulé avec lui (Rendez-vous) : tableau de bord médecin → « Suivi santé et nutrition des patients ». Dr Ahmed voit Patient Test et Amine Trabelsi, mais pas Sonia Mejri.

## 4. Module « Suivi santé et nutrition » — IA (optionnelle)

Les fonctions IA (analyse santé, reconnaissance des aliments, NutriCoach) utilisent **Ollama** en local, gratuit :

```powershell
ollama pull llama3.2     # analyse santé, analyse texte des repas, NutriCoach
ollama pull llava        # analyse des photos de repas
ollama serve
```

Sans Ollama, l'application fonctionne : les écrans IA passent en « mode démonstration » (valeurs d'exemple modifiables, alertes automatiques toujours calculées).
Variables facultatives : `OLLAMA_URL`, `OLLAMA_CHAT_MODEL`, `OLLAMA_VISION_MODEL`.

## 5. Tests

```powershell
cd backend
mvn test

cd ..\frontend
flutter test
```

## Problèmes fréquents

- `mvn` introuvable : ajouter le dossier `bin` de Maven au `PATH`.
- Port 8082 occupé : `$env:SERVER_PORT="8083"` (et adapter l'URL de l'API côté frontend).
- Erreur `JWT_SECRET` au démarrage hors mode dev : définir `$env:JWT_SECRET` (voir plus haut).
