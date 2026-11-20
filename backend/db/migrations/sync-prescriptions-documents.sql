-- Synchronisation médecin ↔ patient : chaque ordonnance (table prescription) est recopiée
-- dans les documents du patient (medical_documents, catégorie PRESCRIPTION).
-- document_id = identifiant de la copie ; NULL tant que la copie n'est pas faite.
-- Appliquée automatiquement au démarrage par SyncSchemaConfiguration.
ALTER TABLE prescription ADD COLUMN IF NOT EXISTS document_id BIGINT;
