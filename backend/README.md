# Backend MediCare
Spring Boot + JWT + PostgreSQL + JPA.

Le profil `dev` utilise H2 en fichier dans `backend/data/medicare.mv.db`, afin
de conserver les données entre les redémarrages sans dépendre de PostgreSQL.
Console H2 : `http://localhost:8082/h2-console`, JDBC URL
`jdbc:h2:file:./data/medicare;DB_CLOSE_ON_EXIT=FALSE`, utilisateur `sa`,
mot de passe vide. Le profil de production reste configurable avec PostgreSQL.

Endpoints principaux : `/api/auth`, `/api/appointments`, `/api/medications`,
`/api/prescriptions` et `/api/health-records`.

## Médicaments et prescriptions

Les routes sont protégées par l'authentification JWT existante. Un médecin
crée et gère le planning associé à ses propres ordonnances; le patient concerné
peut consulter les traitements, horaires, prises et stocks, sans les modifier.
L'administrateur conserve les opérations de gestion.

- `GET /api/medications` et `GET /api/medications/{id}` sont limités aux
  médicaments du patient connecté ou aux ordonnances du médecin connecté.
- `POST /api/medications` et `PUT /api/medications/{id}` sont réservés au
  médecin et à l'administrateur. Un médecin doit fournir le `prescriptionId`
  d'une ordonnance dont il est le prescripteur et au moins un horaire.
- `DELETE /api/medications/{id}` marque le traitement comme `DISCONTINUED` ;
  les prises et le stock historique sont conservés. Cette opération est
  réservée au médecin prescripteur et à l'administrateur.
- `GET /api/medications/today` renvoie les prises prévues aujourd'hui.
- `GET /api/medications/{id}/schedule?date=YYYY-MM-DD` ou
  `?from=YYYY-MM-DD&to=YYYY-MM-DD` génère les prises manquantes de la période.
  Les plages sont limitées à 366 jours; les doublons (médicament/date/heure)
  sont empêchés en base.
- `GET /api/medications/{id}/history?from=...&to=...` (alias
  `GET /api/medications/{id}/intakes`) renvoie l'historique généré.
- Les patients peuvent consulter les prises, mais toutes les mutations de
  statut (`taken`, `pending`, `missed`, `skipped`, `snooze` et `PATCH`) sont
  réservées au médecin prescripteur et à l'administrateur.
- `POST /api/medications/reminders/{id}/taken` et `/pending` restent disponibles.
  Les actions `/missed`, `/skipped` et `/snooze` (avec `{"minutes":15}`) sont
  également disponibles; le report conserve l’heure initiale et retourne
  `snoozedUntil`.
  `PATCH /api/medications/reminders/{id}` accepte
  `{"status":"TAKEN|MISSED|SKIPPED|PENDING|SNOOZED","note":"..."}`.
- `GET /api/medications/{id}/stock` retourne le stock, l'indicateur `lowStock`
  et son journal d'audit. `PUT /api/medications/{id}/stock` corrige la quantité
  avec `{"quantity":12,"unit":"comprimés","lowStockThreshold":5,"note":"..."}`;
  `POST .../{id}/stock/refill` (alias `/refills`) ajoute
  une quantité positive au stock.
- `GET /api/medications/adherence?period=DAILY|WEEKLY|MONTHLY&date=YYYY-MM-DD`
  (alias `/statistics`, périodes `day|week|month` également acceptées) retourne
  les comptes, `adherencePercent` et les agrégats journaliers dans `days`.
  Le médecin peut ajouter `patientId` pour consulter uniquement l'observance
  d'un patient activement suivi; `/today?patientId={id}` retourne son résumé
  des prises du jour.
- `GET /api/prescriptions` et `GET /api/prescriptions/{id}`
- `GET /api/prescriptions/patients/followed` (médecin) retourne les patients
  actifs suivis par ce médecin.
- `POST /api/prescriptions` (rôle médecin ou administrateur)
- `POST /api/prescriptions/extract-medications` (médecin ou administrateur,
  multipart `file`) analyse localement un document sans exiger de `patientId`;
  elle ne crée ni ordonnance ni médicament.
- `POST /api/prescriptions/{id}/extract-medications` (médecin prescripteur ou
  administrateur) analyse localement le document enregistré et retourne des
  propositions à vérifier; cette route ne crée aucun médicament.
- `PUT /api/prescriptions/{id}` (médecin propriétaire ou administrateur,
  multipart `prescriptionDate`, `diagnosis`, `notes` en query parameters, fichier
  `file` facultatif) modifie l'ordonnance sans changer son patient.
- `DELETE /api/prescriptions/{id}` archive l'ordonnance de la liste sans effacer
  son document, son planning associé ni l'historique des prises.

L'OCR est exécuté sur le backend avec Tesseract et les modèles français/anglais
embarqués; le contenu des ordonnances n'est pas envoyé à un service externe.
L'extraction est volontairement conservatrice : les données non détectées
restent vides, et l'enregistrement exige une vérification explicite par le
médecin. Les modèles `tessdata_fast` sont sous licence Apache 2.0 (voir
`src/main/resources/tessdata/LICENSE`). Sous Windows, le runtime Microsoft
Visual C++ v14 peut être nécessaire au moteur OCR. Le médecin peut aussi saisir un traitement manuellement. La création
ou la modification d'un médicament accepte `frequencyPerDay`,
`startDate`, `endDate`, `reminderTimes` et, le cas échéant, `prescriptionId`.
Les dates doivent respecter l'ordre début/fin, les heures doivent être uniques
et le nombre de rappels doit correspondre à la fréquence quotidienne lorsqu'il
est renseigné. Les autres champs sont `pharmaceuticalForm`, `notes`,
`unitsPerDose`, `weekdays` (noms Java tels que `MONDAY`; liste vide = tous les
jours), `status` (`ACTIVE`, `SUSPENDED`, `DISCONTINUED`), `remindersEnabled`,
`stockQuantity`, `stockUnit`, `lowStockThreshold` et `packageQuantity`.
La réponse ne contient ni entité JPA ni identifiant utilisateur.

Les rappels ont un statut explicite. Une transition vers `TAKEN` confirme
l'heure et déduit `unitsPerDose` du stock, une seule fois par transition; une
transition ultérieure de `TAKEN` vers `PENDING` rembourse cette quantité. Le
verrouillage transactionnel du médicament et du rappel protège les modifications
concurrentes. Les transitions vers `MISSED`, `SKIPPED` ou `SNOOZED` ne touchent
pas au stock. Un stock insuffisant renvoie `409 Conflict`. Les corrections,
recharges, stock initial, déductions et remboursements sont conservés dans le
journal du stock.
Le stock est considéré suivi dès qu'une unité par prise, une unité de stock ou
une quantité initiale non nulle est renseignée; les médicaments historiques sans
suivi de stock gardent leur comportement précédent.

La génération ignore les médicaments suspendus, arrêtés ou dont les rappels
sont désactivés, ainsi que les jours absents de `weekdays`. Une modification
supprime uniquement les prises futures `PENDING`; les prises passées et les
statuts non en attente ne sont pas supprimés. `DELETE` est donc une
discontinuation logique et non une suppression d'historique.

Pour les statistiques, le dénominateur est le nombre de doses planifiées
éligibles dont l'heure est passée (dates précédentes complètes, jour courant
jusqu'à l'heure actuelle). `TAKEN / eligibleDoses` donne le pourcentage
d'adhérence. Les doses `MISSED`, `SKIPPED`, `SNOOZED` et `PENDING` restent au
dénominateur et sont renvoyées dans leurs compteurs respectifs; les doses
futures, les médicaments suspendus/arrêtés et les rappels désactivés en sont
exclus. Une période sans dose éligible a un pourcentage de `0`.
