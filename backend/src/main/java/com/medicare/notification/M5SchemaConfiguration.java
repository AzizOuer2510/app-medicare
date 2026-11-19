package com.medicare.notification;

import java.sql.SQLException;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import javax.sql.DataSource;
import org.hibernate.boot.model.relational.Namespace;
import org.hibernate.boot.model.relational.Sequence;
import org.hibernate.mapping.Table;
import org.hibernate.tool.schema.spi.SchemaFilter;
import org.hibernate.tool.schema.spi.SchemaFilterProvider;
import org.springframework.boot.autoconfigure.orm.jpa.HibernatePropertiesCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Keeps the existing ddl-auto setting while making M5 installation additive only. */
@Configuration
public class M5SchemaConfiguration {
    @Bean
    HibernatePropertiesCustomizer preserveExistingSchema(DataSource dataSource) {
        return properties -> {
            if (!"update".equals(properties.get("hibernate.hbm2ddl.auto"))) return;
            Set<String> existing = new HashSet<>();
            try (var connection = dataSource.getConnection();
                 var tables = connection.getMetaData().getTables(null, connection.getSchema(), null, new String[]{"TABLE"})) {
                while (tables.next()) existing.add(tables.getString("TABLE_NAME").toLowerCase(Locale.ROOT));
            } catch (SQLException error) {
                throw new IllegalStateException("Cannot verify the existing schema before installing M5", error);
            }
            SchemaFilter additive = new SchemaFilter() {
                @Override public boolean includeNamespace(Namespace namespace) { return true; }
                @Override public boolean includeTable(Table table) {
                    String name = table.getName().toLowerCase(Locale.ROOT);
                    // Preserve every installed table. On an empty development/test
                    // database, let the application's existing entities bootstrap normally.
                    return !existing.contains(name);
                }
                @Override public boolean includeSequence(Sequence sequence) { return false; }
            };
            properties.put("hibernate.hbm2ddl.schema_filter_provider", new SchemaFilterProvider() {
                @Override public SchemaFilter getMigrateFilter() { return additive; }
                @Override public SchemaFilter getCreateFilter() { return SchemaFilter.ALL; }
                @Override public SchemaFilter getDropFilter() { return SchemaFilter.ALL; }
                @Override public SchemaFilter getTruncatorFilter() { return SchemaFilter.ALL; }
                @Override public SchemaFilter getValidateFilter() { return SchemaFilter.ALL; }
            });
        };
    }
}
