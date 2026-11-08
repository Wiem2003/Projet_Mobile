# Module 4 — Activités (`Activity`)

Suivre l'exercice physique de l'animal (promenade, course, jeu, natation) : durée, distance, calories estimées, indicateurs hebdomadaires. Bonus : enregistrement des promenades au GPS.

**Architecture :** MVC. **Données :** table SQLite `activities` dans la base partagée `smart_pet.db`. Le GPS fonctionne sans connexion Internet.

## Fichiers (MVC)

```
lib/
├── models/
│   ├── activity.dart                    entité + ActivityType (MET) + règles de validation
│   ├── activity_repository.dart         interface d'accès aux données
│   ├── sqlite_activity_repository.dart  implémentation SQLite ; calcule les calories à l'enregistrement
│   ├── activity_stats.dart              calories, périodes, semaines glissantes, indicateurs
│   ├── activities_model.dart            état de l'écran : activités, filtres (animal, type, période)
│   ├── activity_form_model.dart         activité en cours de saisie, aperçu des calories
│   └── gps/
│       ├── geo_point.dart               point GPS, distance (haversine), stockage du trajet en JSON
│       ├── location_source.dart         accès au GPS (paquet geolocator), autorisations
│       └── walk_session_model.dart      promenade en cours : trajet, distance, durée
├── controllers/
│   ├── activities_controller.dart       chargement, filtres, ajout, modification, suppression, exemples
│   ├── activity_form_controller.dart    saisie ; le poids suit l'animal choisi
│   └── walk_tracking_controller.dart    démarrer / pause / reprendre / terminer, filtrage des mesures
└── views/
    ├── screens/activities_screen.dart   indicateurs, graphique « Distance hebdomadaire », historique
    ├── screens/activity_form_screen.dart
    ├── screens/walk_tracking_screen.dart  promenade GPS en direct
    ├── sheets/activity_detail_sheet.dart  détail, tracé du trajet, modifier / supprimer
    ├── widgets/route_trace.dart         tracé du trajet (dessiné, sans fond de carte)
    └── activity_actions.dart, activity_style.dart
```

## Données

| Champ | Colonne | Règle |
|---|---|---|
| Date | `date` | date et heure de début, pas dans le futur |
| Animal | `pet_id` | obligatoire |
| Type d'activité | `type` | promenade, course, jeu, natation, autre |
| Durée | `duration_min` | en minutes, 1 min à 24 h |
| Distance | `distance_km` | en km, facultative, ≤ 200 km ; toujours 0 pour le jeu |
| Calories estimées | `calories` | calculées par le repository, jamais saisies |
| Poids utilisé | `weight_kg` | prérempli avec le poids de l'animal (`PetSummary.weightKg`) |
| Description | `description` | notes libres, 500 caractères max |
| Trajet GPS | `route` | JSON `[[lat, lng, ms], …]`, vide pour une saisie manuelle |

## Calculs automatiques

**Calories estimées** = MET du type × poids (kg) × durée (h).
MET : promenade 3, course 7, jeu 4,5, natation 5, autre 3,5 (estimation).

Les semaines sont **glissantes** : « cette semaine » = les 7 derniers jours, aujourd'hui compris ; la semaine précédente = les 7 jours d'avant.

| Indicateur | Formule |
|---|---|
| Distance hebdomadaire | somme des distances sur 7 jours (+ évolution vs semaine précédente) |
| Durée moyenne | durée totale ÷ nombre d'activités, sur la période choisie |
| Nombre d'activités | compte sur la période choisie (7 jours, 30 jours, 3 mois, tout) |
| Évolution de l'activité | temps d'activité de la semaine actuelle vs semaine précédente |

Le graphique « Distance hebdomadaire (km) » montre les 6 dernières semaines. Les filtres animal et type s'appliquent aux indicateurs et à la liste.

## Bonus GPS

1. Bouton **Promenade GPS** → **Démarrer** : l'app demande l'autorisation de localisation.
2. Pendant la promenade : durée, distance, vitesse et tracé en direct ; **Pause** / **Reprendre**.
3. **Terminer** : le formulaire s'ouvre prérempli (promenade, date, durée, distance, trajet). Il reste à choisir l'animal et à enregistrer.

Mesures ignorées : précision > 35 m, sauts > 45 km/h, positions reçues pendant la pause.
Le temps de pause n'est pas compté dans la durée.

Le tracé est dessiné sur une grille, sans fond de carte, pour fonctionner hors ligne. Pour afficher une vraie carte, il faut ajouter `flutter_map` (tuiles OpenStreetMap, qui demandent Internet).

Autorisations : `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` (Android) et `NSLocationWhenInUseUsageDescription` (iOS). Elles sont déjà ajoutées.
Le GPS ne fonctionne qu'avec l'app ouverte (pas de suivi en arrière-plan).

**Sur l'émulateur :** ⋯ (Extended controls) → **Location** → **Routes**. Tracez un itinéraire puis **Play route** pour simuler une promenade.

## Analyse des activités

Règles dans [activity_insights.dart](../lib/models/activity_insights.dart) et [activity_guidelines.dart](../lib/models/activity_guidelines.dart) (fonctions pures, testées dans `test/activities/activity_insights_test.dart`). Elles sont affichées dans la section « Analyse » sous le graphique ([activity_insights_section.dart](../lib/views/widgets/activity_insights_section.dart)) :
- **vue « Tous » :** les alertes et le bilan de l'année ;
- **un animal choisi :** sa charge, sa durée conseillée, son bilan énergétique et ses records.

### Charge d'entraînement et récupération

- **Charge d'une activité :** minutes × intensité (promenade 3, course 7, natation 5, jeu 4,5, autre 3,5).
- **Rapport :** charge des 7 derniers jours ÷ charge moyenne par semaine sur 28 jours. Il faut au moins 3 semaines d'historique pour comparer.
- **Au-dessus de 1,5 :** « Rex : charge en forte hausse (+70 %), risque de blessure, prévoyez une journée calme ».
- **En dessous de 0,6 :** « baisse d'activité ».
- **Repos :** après 2 jours de course d'affilée, une journée de repos est conseillée (aujourd'hui, ou demain si l'animal a déjà couru aujourd'hui).

### Durée conseillée selon la taille

| Profil | par jour |
|---|---|
| petit chien (moins de 10 kg) | 30 à 60 min |
| chien moyen (10 à 25 kg, ou poids inconnu) | 60 à 90 min |
| grand chien (plus de 25 kg) | 90 à 120 min |
| chat | 2 séances de jeu de 15 min |

**Alertes**, pour un animal dont les activités sont suivies :
- **Chien :** moyenne de la semaine sous le minimum. Exemple : « Rex : 30 min par jour en moyenne cette semaine (conseillé : 90 à 120 min pour un grand chien) ».
- **Chat :** « Mia : 2 jours sans séance de jeu ».
- **Excès :** une journée au-delà de 1,5 × le maximum.

**Objectif de la semaine :** le minimum par jour × 7, par exemple 630 min pour un grand chien. C'est désormais la même source pour l'indice Smart Pet (critère Activité) et pour la ration conseillée (bonus « actif »).

### Bilan énergétique et poids prévu (indicatif, à confirmer avec le vétérinaire)

- **Apport :** calories des repas (module Alimentation), par jour de repas saisi. Il faut au moins 7 jours saisis sur 14.
- **Dépense :** besoin au repos × 1,2 (vie quotidienne : digestion, déplacements dans la maison) + calories des activités enregistrées sur 14 jours. Le facteur 1,2 évite de sous-estimer la dépense : avec le seul besoin au repos, presque tous les animaux sembleraient prendre du poids.
- **Bilan :** « Rex : +559 kcal par jour en moyenne (apport 1665, dépense 1106) ».
- **Projection :** environ 7 700 kcal par kilo, donc « À ce rythme, Rex prendrait environ 2,2 kg par mois » (stable en dessous de 0,1 kg).
- **Comparaison avec les pesées du module Santé :** la projection est « cohérente » si l'écart avec la courbe réelle est de moins de 0,5 kg par mois. Sinon : « vérifiez les quantités et les calories saisies ».

### Records personnels

- **Records :** plus longue sortie (distance), sortie la plus rapide (au moins 1 km), semaine record (du lundi au dimanche).
- **Bilan de l'année :** « 2026 : 412 km, 186 activités, 120 h ».
- **Nouveau record :** une activité qui bat un record de l'animal déclenche une notification (« 🏆 Nouveau record pour Rex : 6,2 km ! »). Le record s'affiche aussi en tête de la section. Il faut au moins une sortie précédente à battre.

## Tester

```powershell
flutter test test/activities
```

Sur l'émulateur : onglet **Activité** → menu ⋮ → **Charger des exemples** (6 semaines d'activités, dont une promenade GPS).
