# Frontend MediCare
Flutter + Dio + Riverpod + flutter_secure_storage.

Lancer `flutter create .` puis `flutter pub get` avant `flutter run`.

Le module Médicaments permet au patient de consulter son agenda en lecture
seule. Le médecin peut choisir un document et lancer l'OCR local français/anglais
avant de sélectionner le patient; un patient reste obligatoire pour envoyer
l'ordonnance. Il doit vérifier chaque champ et confirmer le planning avant
l'envoi; les valeurs incertaines restent à compléter. Plusieurs médicaments
peuvent être ajoutés à la même ordonnance. Dans la liste des prescriptions du
médecin, chaque ordonnance peut être modifiée (sans réaffecter le patient),
archivée, téléchargée ou utilisée pour compléter le planning. L'archivage
retire l'ordonnance de la liste tout en conservant son document, son planning et
l'historique. Sur le tableau de bord médecin, les cartes « Patients suivis » et
« Prescriptions » ouvrent leurs listes; la liste des patients permet aussi de
consulter les prescriptions de chacun. Son arrière-plan utilise l'illustration
locale `assets/images/doctor_dashboard_background.png`; le logo utilise
`assets/images/medicare_logo_transparent.png` sans fond opaque. La section
« Prescriptions récentes » a été supprimée. Les appels utilisent le client API
authentifié existant.

## Assistant traitement

L'assistant est une aide locale à réponses guidées, sans appel à un service d'IA
externe. Il peut expliquer les champs d'une prescription, répondre aux questions
d'organisation et retrouver les informations déjà enregistrées pour le compte
connecté. Il ne modifie aucun traitement et refuse les demandes de décision
médicale, de dose ou de changement de prescription. Ses réponses ne remplacent
pas l'avis d'un professionnel de santé.

## Médicaments et prises

Le formulaire médecin, le stock et les statistiques appellent le client Dio
authentifié sur les routes suivantes. Les patients consultent leurs traitements
et leurs horaires, mais ne peuvent modifier le planning, le stock ou l'état des
prises; le backend applique également cette restriction.

- `GET /medications/today`
- `GET /medications/{id}/stock` et `PUT /medications/{id}/stock`
- `POST /medications/{id}/stock/refill` avec `quantity` et `note`
- `GET /medications/statistics?period=day|week|month`
- `POST /medications/reminders/{id}/{missed|skipped}` et
  `POST /medications/reminders/{id}/snooze` avec `{ "minutes": n }`

Le DTO médicament attendu ajoute `pharmaceuticalForm`, `notes`,
`unitsPerDose`, `weekdays` (ISO 1–7), `status`, `remindersEnabled`,
`stockQuantity`, `stockUnit`, `lowStockThreshold` et `packageQuantity`.
Le lecteur accepte les champs optionnels, les nombres sous forme de texte et
quelques variantes de stock/statistiques; il garde aussi la compatibilité avec
les rappels hérités qui ne fournissent que `taken`. Les statistiques affichent le nombre de prises éligibles, prises, manquées,
ignorées, reportées et le taux `adherencePercent` renvoyés par le backend.

Les notifications locales natives sont planifiées selon le fuseau local, après
autorisation, pour les jours et horaires choisis. Elles ne valident jamais une
prise. Leur gestion nécessite un identifiant renvoyé par le serveur lors de la
création; sur le Web, les notifications locales planifiées ne sont pas activées.
La permission Android 13+ est demandée au premier enregistrement de rappel.
Les traitements sans date de fin utilisent une répétition hebdomadaire; les
traitements avec une date de fin planifient 14 jours glissants, actualisés à
l’ouverture de la liste des médicaments. Cette fenêtre tient compte de la date
de fin afin de ne pas émettre de rappel au-delà. Les notifications planifiées
ne sont activées que sur Android, iOS et macOS (pas sur le Web, Linux ou Windows).
La correction du stock envoie `quantity`, `unit`, `lowStockThreshold` et
`packageQuantity`; le backend conserve chaque correction dans le journal.
L’API de réapprovisionnement ajoute la quantité fournie au stock; la quantité
par boîte préremplit ce mouvement.
