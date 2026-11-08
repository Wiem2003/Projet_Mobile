# Module 3 — Alimentation (`FeedingRecord`)

Suivre ce que mangent les animaux et ce que cela coûte : historique des repas, quantité consommée par mois, dépense alimentaire, moyenne quotidienne et évolution des dépenses.

**Architecture :** MVC. **Données :** table SQLite `feeding_records` dans la base partagée `smart_pet.db`. Tout fonctionne hors ligne.

## Fichiers (MVC)

```
lib/
├── models/
│   ├── feeding_record.dart             entité + FoodType + règles de validation (FeedingRecord.validate)
│   ├── feeding_repository.dart         interface d'accès aux données
│   ├── sqlite_feeding_repository.dart  implémentation SQLite (CRUD, import groupé)
│   ├── feeding_stats.dart              calculs automatiques du mois
│   ├── feeding_model.dart              état de l'écran : repas, animaux, filtres (animal, mois)
│   ├── feeding_form_model.dart         repas en cours de saisie, validation, prix au kilo
│   └── validation.dart                 RecordException, lecture des nombres « 12,5 »
├── controllers/
│   ├── feeding_controller.dart         chargement, filtres, ajout, modification, suppression, exemples
│   └── feeding_form_controller.dart    saisie du formulaire, « Reprendre le dernier repas »
└── views/
    ├── screens/feeding_screen.dart     indicateurs, graphique, historique groupé par jour
    ├── screens/feeding_form_screen.dart
    ├── feeding_actions.dart            ouverture du formulaire, confirmation de suppression, SnackBar
    └── feeding_style.dart              icône et couleur de chaque type de nourriture
```

## Données

| Champ | Colonne | Règle |
|---|---|---|
| Date | `date` | jour du repas (minuit), pas dans le futur |
| Animal | `pet_id` | obligatoire |
| Type de nourriture | `food_type` | croquettes, pâtée, friandises, fait maison, autre |
| Quantité | `quantity_g` | en grammes, > 0 et ≤ 20 kg |
| Prix | `price` | ≥ 0 (en DT, constante `Units.currency`) |
| Nombre de repas | `meals` | 1 à 10 |
| Marque | `brand` | facultative, 60 caractères max |

## CRUD

| Action | Où |
|---|---|
| ➕ Ajouter | bouton « Ajouter un repas » ; « Reprendre le dernier repas » recopie le dernier repas de l'animal |
| 👁️ Historique | liste du mois choisi, groupée par jour, avec le total du jour |
| ✏️ Modifier | toucher une ligne, ou menu ⋮ → Modifier |
| 🗑️ Supprimer | menu ⋮ → Supprimer (confirmation, puis « Annuler » dans la SnackBar) |

## Calculs (`FeedingStats.compute`)

Ils portent sur le mois affiché (flèches ‹ ›) et l'animal choisi (« Tous » par défaut).

| Indicateur | Formule |
|---|---|
| 🍖 Quantité consommée / mois | somme des quantités du mois |
| 💰 Dépense alimentaire | somme des prix du mois |
| 📊 Moyenne quotidienne | quantité du mois ÷ jours (jours écoulés pour le mois en cours, tous les jours pour un mois passé) |
| 📈 Évolution des dépenses | (dépense du mois − mois précédent) ÷ mois précédent ; pour le mois en cours, le mois précédent est pris du 1er au même jour ; graphique des 6 derniers mois |

Une hausse des dépenses s'affiche en rouge, une baisse en vert.

## Nutrition

Règles dans [nutrition.dart](../lib/models/nutrition.dart) (fonctions pures, testées dans `test/feeding/nutrition_test.dart`). Elles sont affichées dans la section « Nutrition » de l'écran, sous le graphique ([nutrition_section.dart](../lib/views/widgets/nutrition_section.dart)) :
- **vue « Tous » :** seulement les alertes ;
- **un animal choisi :** sa ration, ses alertes et ses horaires.

**Calories :** chaque repas peut porter les calories de l'emballage (kcal pour 100 g, de 1 à 900). Sans saisie, l'app utilise une valeur typique, signalée « valeur typique » :

| Type | kcal / 100 g |
|---|---|
| Croquettes | 370 |
| Pâtée | 90 |
| Friandises | 350 |
| Fait maison | 150 |
| Autre | 200 |

### Ration conseillée (indicative, à confirmer avec le vétérinaire)

- **Besoin au repos :** 70 × poids^0,75. Rex (28 kg) : 852 kcal.
- **Besoin du jour :** besoin au repos × facteur, +0,2 si l'objectif d'activité de la semaine est atteint (module Activités).

| Chien | Facteur | Chat | Facteur |
|---|---|---|---|
| chiot de moins de 4 mois | 3,0 | chaton (moins de 12 mois) | 2,5 |
| chiot de 4 à 12 mois | 2,0 | adulte | 1,2 |
| adulte | 1,6 | adulte stérilisé | 1,0 |
| adulte stérilisé | 1,4 | senior (10 ans) | 1,1 |
| senior (7 ans) | 1,4 | | |

- **Grammes conseillés :** besoin du jour ÷ calories de l'aliment principal (le plus donné sur 14 jours, hors friandises).
- **Comparaison :** elle porte sur la moyenne réelle des jours saisis. Exemple : « Rex mange 454 g par jour, la ration conseillée est de 359 g (+27 %) ».
- **Stérilisation :** la case « Stérilisé(e) » est sur la fiche animal.

### Friandises sous contrôle

Sur les 7 derniers jours, les friandises ne doivent pas dépasser **10 % des calories**. Exemple d'alerte : « Mia : 18 % de ses calories en friandises cette semaine (10 % maximum) ».

### Baisse d'appétit

- **Règle :** les grammes par jour de repas saisi sur les 7 derniers jours sont inférieurs d'au moins **25 %** à ceux des 30 jours précédents.
- **Données suffisantes :** il faut au moins 3 jours saisis cette semaine et 7 avant. Un oubli de saisie n'est pas une baisse d'appétit ; l'accueil le signale séparément (« Repas non saisis »).
- **Exemple :** « Mia mange 35 % de moins depuis une semaine (65 g par jour au lieu de 100 g) : surveillez son état ou consultez ».
- **Dossier Santé :** le bouton « Créer un dossier Santé » ouvre une consultation pré-remplie.
- **Différence avec l'accueil :** l'alerte de l'accueil détecte une prise de poids, celle-ci un signe possible de maladie.

### Nombre de repas selon l'âge (chiens et chats)

| Âge | Repas par jour |
|---|---|
| moins de 6 mois | 3 à 4 |
| adulte | 2 |
| senior (chien 7 ans, chat 10 ans) | 2 à 3, plus petits |

Le formulaire affiche un conseil si le nombre saisi s'en écarte, par exemple « Conseil pour Mia (chaton de 4 mois) : 3 à 4 repas par jour ». Le repas peut quand même être enregistré.

### Horaires des repas

- **Réglage :** pour l'animal choisi, « Ajouter un horaire » (6 au plus). Les horaires sont enregistrés par compte.
- **Notification :** une notification arrive chaque jour, par exemple « Repas de Mia, 19 h ».
- **Pas de rappel :** les horaires ne créent pas de rappels, pour qu'un repas non coché ne passe jamais « en retard » ni ne fasse baisser l'indice Smart Pet.
- **Déconnexion :** les notifications sont annulées.

## Stock de croquettes et date de rachat

- **Saisie :** carte « Stock de nourriture » → **Ouvrir un sac**. On indique les animaux qui mangent le sac, l'aliment, la marque (facultative), le poids, le prix et la date d'ouverture.
- **Reste :** poids du sac − repas saisis depuis l'ouverture (mêmes animaux, même type d'aliment et, si les deux sont connues, même marque).
- **Sac partagé :** la consommation de tous les animaux du sac est additionnée.
- **Jours restants :** reste ÷ consommation moyenne par jour saisi sur les 14 derniers jours.
- **Alerte :** à 7 jours ou moins, par exemple « Sac de Rex vide dans environ 5 jours ».
- **Rappel automatique :** « Racheter : croquettes (Rex) » (type Achat) est créé 3 jours avant la date où le sac sera vide, à 9 h. Il se déplace quand la consommation change.
- **Fin du sac :** menu du sac → **Sac terminé**, ce qui retire aussi le rappel. Un rappel déjà marqué fait n'est pas recréé : on enregistre alors le nouveau sac.

## Programme de perte de poids (chiens et chats)

- **Démarrage :** section Nutrition de l'animal → **Démarrer**. On choisit le poids cible et le rythme (1 %, 1,5 % ou 2 % du poids par semaine).
- **Limites :** le poids cible doit être inférieur au poids actuel, et la perte ne peut pas dépasser 40 %.
- **Durée :** semaines = ln(cible ÷ départ) ÷ ln(1 − rythme). Exemple : 28 → 25 kg à 1 % par semaine donne 12 semaines.
- **Ration :** elle est calculée sur le poids cible, pas sur le poids actuel.
- **Suivi :** les pesées viennent des soins du module Santé (champ poids).
  - Le rythme mesuré compare la dernière pesée à la plus récente pesée faite au moins 7 jours avant.
  - La position sur la courbe est « dans les temps », « en retard » ou « en avance », avec une tolérance de 1 %.
- **Alerte :** au-delà de 2 % par semaine. Chez le chat, elle est rouge, car le risque est la lipidose (maladie du foie).
- **Courbe :** la courbe prévue est en pointillés, les pesées réelles en trait plein.
- **Arrêt :** la croix « Arrêter le programme » remet la ration sur le poids actuel.

## Budget alimentaire et prévision de fin de mois

- **Plafond :** carte « Budget alimentaire » → **+**. Il s'applique à tous les animaux (vue « Tous ») ou à l'animal choisi en haut de l'écran. Un champ vide retire le plafond.
- **Projection (mois en cours) :** dépense ÷ jours écoulés × jours du mois, par exemple « Vous finirez le mois à environ 19,00 DT ».
- **Alertes :** « le plafond sera dépassé d'environ X DT » en orange, « Plafond dépassé » en rouge.
- **Comparaison corrigée :** pour le mois en cours, l'« Évolution des dépenses » compare au **même nombre de jours** du mois précédent (du 1er au jour d'aujourd'hui), et non au mois complet.

## Tester

```powershell
flutter test test/feeding
```

Sur l'émulateur : onglet **Repas** → menu ⋮ → **Charger des exemples** (5 mois de repas pour Rex et Mia), puis :

1. **Budget :** carte « Budget alimentaire » → **+** → saisir un plafond plus bas que la projection, pour voir l'alerte.
2. **Stock :** **Ouvrir un sac** → Rex, 5 kg, ouvert il y a 10 jours. Le reste, la date où il sera vide et le rappel « Racheter » apparaissent ; ce dernier est dans l'onglet Rappels.
3. **Perte de poids :** choisir Rex en haut → section Nutrition → **Démarrer** → poids cible. Ajoutez ensuite un soin avec un poids dans le module Santé pour faire avancer la courbe.
