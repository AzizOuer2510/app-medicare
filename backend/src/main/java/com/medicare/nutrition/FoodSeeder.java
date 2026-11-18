package com.medicare.nutrition;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** Données de référence : aliments courants (valeurs moyennes pour 100 g / 100 ml). */
@Component
@RequiredArgsConstructor
public class FoodSeeder implements ApplicationRunner {
    private final FoodRepository foods;

    // nom, catégorie, unité, kcal, protéines, glucides, lipides, fibres
    private static final Object[][] DATA = {
        {"Poulet grillé", "Viandes & poissons", "g", 165, 31, 0, 3.6, 0},
        {"Bœuf haché 5 %", "Viandes & poissons", "g", 137, 21, 0, 5, 0},
        {"Dinde (blanc)", "Viandes & poissons", "g", 135, 30, 0, 1, 0},
        {"Saumon", "Viandes & poissons", "g", 208, 20, 0, 13, 0},
        {"Thon en conserve (au naturel)", "Viandes & poissons", "g", 116, 26, 0, 1, 0},
        {"Sardines à l'huile", "Viandes & poissons", "g", 208, 25, 0, 11, 0},
        {"Œuf", "Œufs & laitiers", "g", 155, 13, 1.1, 11, 0},
        {"Lait demi-écrémé", "Œufs & laitiers", "ml", 46, 3.3, 4.8, 1.6, 0},
        {"Yaourt nature", "Œufs & laitiers", "g", 61, 3.5, 4.7, 3.3, 0},
        {"Fromage blanc 0 %", "Œufs & laitiers", "g", 48, 7.5, 4, 0.2, 0},
        {"Fromage (emmental)", "Œufs & laitiers", "g", 380, 28, 0, 29, 0},
        {"Riz blanc cuit", "Féculents", "g", 130, 2.7, 28, 0.3, 0.4},
        {"Riz complet cuit", "Féculents", "g", 123, 2.7, 25.6, 1, 1.6},
        {"Pâtes cuites", "Féculents", "g", 131, 5, 25, 1.1, 1.8},
        {"Couscous (semoule cuite)", "Féculents", "g", 112, 3.8, 23, 0.2, 1.4},
        {"Pain blanc (baguette)", "Féculents", "g", 270, 9, 55, 1.5, 2.7},
        {"Pain complet", "Féculents", "g", 247, 13, 41, 3.4, 7},
        {"Pomme de terre cuite", "Féculents", "g", 87, 1.9, 20, 0.1, 1.8},
        {"Flocons d'avoine", "Féculents", "g", 389, 17, 66, 7, 10.6},
        {"Lentilles cuites", "Légumineuses", "g", 116, 9, 20, 0.4, 7.9},
        {"Pois chiches cuits", "Légumineuses", "g", 164, 8.9, 27, 2.6, 7.6},
        {"Haricots rouges cuits", "Légumineuses", "g", 127, 8.7, 22.8, 0.5, 6.4},
        {"Salade verte", "Légumes", "g", 15, 1.4, 2.9, 0.2, 1.3},
        {"Tomate", "Légumes", "g", 18, 0.9, 3.9, 0.2, 1.2},
        {"Carotte", "Légumes", "g", 41, 0.9, 10, 0.2, 2.8},
        {"Brocoli", "Légumes", "g", 34, 2.8, 7, 0.4, 2.6},
        {"Courgette", "Légumes", "g", 17, 1.2, 3.1, 0.3, 1},
        {"Concombre", "Légumes", "g", 15, 0.7, 3.6, 0.1, 0.5},
        {"Haricots verts", "Légumes", "g", 31, 1.8, 7, 0.2, 2.7},
        {"Pomme", "Fruits", "g", 52, 0.3, 14, 0.2, 2.4},
        {"Banane", "Fruits", "g", 89, 1.1, 23, 0.3, 2.6},
        {"Orange", "Fruits", "g", 47, 0.9, 12, 0.1, 2.4},
        {"Fraises", "Fruits", "g", 32, 0.7, 7.7, 0.3, 2},
        {"Dattes", "Fruits", "g", 282, 2.5, 75, 0.4, 8},
        {"Amandes", "Fruits secs & oléagineux", "g", 579, 21, 22, 50, 12.5},
        {"Noix", "Fruits secs & oléagineux", "g", 654, 15, 14, 65, 6.7},
        {"Huile d'olive", "Matières grasses", "ml", 884, 0, 0, 100, 0},
        {"Beurre", "Matières grasses", "g", 717, 0.9, 0.1, 81, 0},
        {"Miel", "Produits sucrés", "g", 304, 0.3, 82, 0, 0.2},
        {"Chocolat noir 70 %", "Produits sucrés", "g", 598, 7.8, 46, 43, 10.9},
        {"Jus d'orange", "Boissons", "ml", 45, 0.7, 10.4, 0.2, 0.2},
        {"Soda", "Boissons", "ml", 42, 0, 10.6, 0, 0},
        {"Café noir", "Boissons", "ml", 2, 0.3, 0, 0, 0},
        {"Eau", "Boissons", "ml", 0, 0, 0, 0, 0},
    };

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        for (Object[] row : DATA) {
            String name = (String) row[0];
            if (foods.existsByNameIgnoreCase(name)) continue;
            foods.save(Food.builder()
                .name(name).category((String) row[1]).unit((String) row[2])
                .calories(num(row[3])).protein(num(row[4])).carbohydrates(num(row[5]))
                .fat(num(row[6])).fiber(num(row[7])).build());
        }
    }

    private static Double num(Object value) { return ((Number) value).doubleValue(); }
}
