package com.medicare.document;

import java.sql.SQLException;
import java.util.Locale;
import javax.sql.DataSource;
import org.springframework.boot.autoconfigure.orm.jpa.HibernatePropertiesCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Migration additive de la synchronisation ordonnances → documents.
 * M5SchemaConfiguration empêche Hibernate de modifier les tables existantes : la colonne
 * prescription.document_id (lien vers la copie dans les documents du patient) est donc ajoutée
 * ici, avant le démarrage de JPA. Sans effet si la colonne existe déjà ou si la base est vide.
 * Même script : backend/db/migrations/sync-prescriptions-documents.sql
 */
@Configuration
public class SyncSchemaConfiguration {
    @Bean
    HibernatePropertiesCustomizer addPrescriptionDocumentColumn(DataSource dataSource) {
        return properties -> {
            try (var connection = dataSource.getConnection()) {
                boolean tableExists = false;
                try (var tables = connection.getMetaData().getTables(null, connection.getSchema(), null, new String[]{"TABLE"})) {
                    while (tables.next()) {
                        if ("prescription".equals(tables.getString("TABLE_NAME").toLowerCase(Locale.ROOT))) tableExists = true;
                    }
                }
                if (!tableExists) return;
                try (var statement = connection.createStatement()) {
                    statement.execute("ALTER TABLE prescription ADD COLUMN IF NOT EXISTS document_id BIGINT");
                }
            } catch (SQLException error) {
                throw new IllegalStateException("Impossible d'ajouter la colonne prescription.document_id", error);
            }
        };
    }
}
