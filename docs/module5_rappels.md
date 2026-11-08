# Module 5 — Rappels & alertes (`Reminder`)

Ne plus oublier un vaccin, un vermifuge ou un rendez-vous : rappels manuels ou générés par les autres modules, notifications locales J-x, report, répétition et historique.

**Architecture :** MVC (Model – View – Controller). **Données :** SQLite local (`sqflite`). L'app fonctionne sans connexion et sans serveur (critère T09).

## Arborescence (MVC)

```
lib/
├── models/                                 MODEL : données, règles, état observé
│   ├── reminder.dart, reminder_enums.dart    entité + conversion ligne SQLite (toMap / fromMap)
│   ├── reminder_calculator.dart              calculs purs : jours restants, regroupement, répétition, stats
│   ├── reminder_repository.dart              interface d'accès aux données
│   ├── sqlite_reminder_repository.dart       implémentation SQLite + règles métier
│   ├── reminder_exception.dart               erreurs métier affichables
│   ├── reminders_model.dart                  état de l'écran : rappels, animaux, filtres, indicateurs
│   ├── reminder_form_model.dart              rappel en cours de saisie, validation, aperçu des alertes
│   ├── assistant/                            chatbot : analyse des phrases, messages, conversation
│   └── notifications/                        notifications locales (flutter_local_notifications)
├── controllers/                            CONTROLLER : reçoit les actions, met à jour le Model
│   ├── reminders_controller.dart             chargement, filtres, fait, report, suppression, notifications
│   ├── reminder_form_controller.dart         saisie et enregistrement du formulaire
│   └── reminder_assistant_controller.dart    réponses du chatbot
└── views/                                  VIEW : widgets uniquement
    ├── screens/  reminders_screen, reminder_form_screen, reminder_assistant_screen
    ├── sheets/   fiche détail, report
    ├── widgets/  carte, en-tête, calendrier, onglets, filtres, carte Dashboard
    └── home_shell.dart  navigation principale (barre du bas)
```

Cycle MVC :

1. La **View** affiche le Model : `context.watch<RemindersModel>()`.
2. Une action de l'utilisateur (toucher, glisser, saisir) appelle le **Controller** : `context.read<RemindersController>().markDone(r)`.
3. Le **Controller** applique la règle via le repository SQLite, reprogramme les notifications, puis met à jour le **Model**.
4. Le **Model** prévient la View (`notifyListeners`), qui se redessine.

Une View ne modifie jamais le Model et ne parle jamais au repository ni au service de notifications.

## Base de données

Table `reminders`, créée dans [core/database/app_database.dart](../lib/core/database/app_database.dart) (fichier `smart_pet.db`).

| Colonne | Type | Remarque |
|---|---|---|
| `id` | INTEGER PK | auto-incrément |
| `pet_id` | INTEGER | animal concerné, `NULL` = général |
| `title`, `type` | TEXT | type : vaccination, deworming, vetAppointment, treatment, checkup, purchase, other |
| `due_date` | INTEGER | échéance (millisecondes epoch) |
| `alert_offsets` | TEXT | délais d'alerte, ex. `oneDay,atTime` |
| `repeat`, `status` | TEXT | none/weekly/monthly/yearly — upcoming/done/postponed |
| `source`, `source_id` | TEXT, INTEGER | manual / health / feeding + id de l'enregistrement d'origine |
| `postpone_count`, `completed_at`, `created_at`, `updated_at` | INTEGER | |

Un **index unique** `(source, source_id, due_date)` garantit qu'une échéance venant de Santé ou d'Alimentation n'est jamais dupliquée. « En retard » n'est pas stocké : c'est un rappel non fait dont la date est passée.

Les autres modules ajoutent leurs tables dans `_onCreate` (et une migration dans `_onUpgrade` en incrémentant `version`).

## Notifications

À chaque chargement, `RemindersController.load()` appelle `ReminderNotifier.syncAll(...)`. Les alertes futures sont reprogrammées, et celles des rappels supprimés, faits ou reportés sont annulées. Un rappel créé par un autre module reçoit donc ses notifications automatiquement.

## Assistant (chatbot)

Bouton 🤖 au-dessus de « Nouveau rappel ». L'assistant comprend des phrases simples en français, **sans Internet ni API** : l'analyse est faite en Dart ([assistant_parser.dart](../lib/models/assistant/assistant_parser.dart)), et les actions passent par `RemindersController`. Il applique donc les mêmes règles (T02, anti-doublon, T07), utilise la même base SQLite et programme les mêmes notifications.

| L'utilisateur écrit | L'assistant |
|---|---|
| « Quoi de prévu demain ? », « Qu'est-ce qui est en retard ? », « Prochain vaccin de Rex ? », « Quoi de prévu cette semaine ? », « Historique » | répond avec des cartes cliquables (fiche détail) |
| « Fais le point » | résumé : en retard, aujourd'hui, 7 jours, faits ce mois-ci |
| « Rappelle-moi le vermifuge de Rex vendredi à 8h » | récapitule, demande confirmation, puis enregistre |
| « Rappelle-moi d'acheter des croquettes » | demande « Pour quand ? » |
| « J'ai donné le vermifuge » | marque fait ; demande « Lequel ? » si plusieurs rappels correspondent |
| « Reporte l'antipuces à lundi », « Décale le rendez-vous de 3 jours » | reporte (T07), l'heure est conservée |
| « Supprime le contrôle » | demande confirmation |
| « annuler » (juste après une action) | annule la création ou le « fait » |
| « rappel vaccin Rex 15/12 10h », « rapelle moi … » | forme courte et fautes courantes : création |
| « Lequel ? » → réponse incomprise | repose la question ; « le premier », « le 2 », « celui de Mia » |
| « Combien j'ai dépensé chez le véto ? », « Quel est le poids de Rex ? » | hors rappels : oriente vers l'onglet Santé, Repas, Activité ou Mes animaux |

Dates comprises : aujourd'hui, demain, après-demain, ce soir, lundi…dimanche, dans 3 jours / 2 semaines / 1 mois / 2 heures, le 20/11, le 1er décembre 2027, à 9h, 18h30, midi, 7h du soir. Répétition : chaque semaine / mois / année.

Pour brancher plus tard un vrai modèle de langage, il suffit de remplacer `AssistantParser` : il renvoie une `AssistantCommand`, et le Controller et la View ne changent pas.

## Priorité et escalade

Règles dans [reminder_rules.dart](../lib/models/reminder_rules.dart) (fonctions pures, testées).

**Score d'urgence = gravité du type × jours de retard** (au moins 1 dès que l'échéance est dépassée). La liste « En retard » est triée par ce score, puis par date.

| Type | Gravité | Reports max | Durée max d'un report |
|---|---|---|---|
| Vaccin | 5 | 3 | 30 jours |
| Traitement | 4 | 2 | 7 jours |
| Rendez-vous | 4 | 3 | 30 jours |
| Vermifuge | 3 | 3 | 30 jours |
| Contrôle | 3 | 3 | 60 jours |
| Autre | 2 | sans limite | sans limite |
| Achat | 1 | sans limite | sans limite |

**Escalade d'un rappel non fait :**

| Retard | Niveau | Effet |
|---|---|---|
| le jour même | En retard | — |
| J+1 et J+2 | Relance 1 | une notification de relance à J+1, à l'heure de l'échéance |
| J+3 | Relance 2 | une deuxième relance à J+3 |
| plus de 3 jours | Critique | badge rouge « Critique » sur la carte, compté dans l'onglet « En retard » |

Les relances utilisent les créneaux de notification 14 et 15 du rappel (`id × 16 + créneau`). Elles sont annulées dès que le rappel est fait.

**Limite de reports :** la durée maximale est comptée depuis l'échéance, ou depuis aujourd'hui si elle est passée. La feuille de report affiche « Report 2 sur 3 autorisés » et grise les choix trop lointains. Au-delà de la limite :
- le repository refuse le report (`ReminderException`, `isPostponeLimit`), y compris depuis l'assistant ;
- l'app affiche « Report impossible » et propose **Prendre rendez-vous**, qui ouvre un nouveau rappel « Rendez-vous vétérinaire » pré-rempli pour le même animal, demain à 10 h.

## Statistiques d'observance

Calculs dans [reminder_compliance.dart](../lib/models/reminder_compliance.dart) ; écran [reminder_compliance_screen.dart](../lib/views/screens/reminder_compliance_screen.dart), ouvert depuis le menu ⋮ (« Statistiques d'observance ») ou depuis l'onglet « Terminés ».

Seules les échéances passées comptent. Chacune a l'un de ces résultats :
- **à temps** : faite le jour prévu ou avant ;
- **en retard** : faite après le jour prévu ;
- **oubliée** : pas faite, et le jour prévu est passé. Le jour même, le soin peut encore être fait à temps.

Un rappel reporté est jugé sur sa nouvelle date. Le nombre d'échéances reportées est affiché à part.

L'écran montre :
- **le taux global** : part des soins faits à temps, retard moyen, répartition à temps / en retard / oubliés ;
- **les séries en cours** : soins d'un même type pour un même animal faits à temps d'affilée, en partant du plus récent (« 8 vermifuges d'affilée faits à l'heure »), à partir de 2 ;
- **le graphique par mois** : taux des 6 derniers mois, selon le mois de l'échéance ;
- **le détail par animal** ;
- **le détail par type de soin**, avec le retard moyen. Le type au retard moyen le plus élevé est marqué « Le plus souvent en retard ».

Le retard moyen compte 0 jour pour un soin fait à temps. Le filtre par animal (Tous / Rex / Mia) est le même que celui de l'écran Rappels.

**Démo :** sans échéance passée, l'écran propose « Charger un historique d'exemple » (`RemindersController.seedHistory`). Il ajoute 21 soins passés : 8 vermifuges de Rex à l'heure, des antipuces de Mia parfois en retard, un vaccin en retard de 12 jours, des achats.

## Planification de la semaine

Règles dans [reminder_planning.dart](../lib/models/reminder_planning.dart). Écran **Planification & budget** ([reminder_planning_screen.dart](../lib/views/screens/reminder_planning_screen.dart)), ouvert depuis le menu ⋮ ou depuis le bandeau d'alerte en tête de l'onglet « À venir ».

**Journées surchargées :**
- **Règle :** plus de 3 rappels non faits le même jour, à partir d'aujourd'hui.
- **Rappels déplacés :** seulement les peu graves, de gravité 1 ou 2 (achats, « Autre »), le moins grave d'abord.
- **Destination :** le jour libre le plus proche, cherché le lendemain, puis la veille, puis J+2, J-2… sur 14 jours au plus. L'heure est conservée.
- **Garde-fous :** jamais dans le passé, jamais vers un jour qui deviendrait surchargé, jamais en violation d'un délai minimal.
- **Validation :** l'utilisateur coche les déplacements puis touche « Déplacer ». Ce n'est pas un report : le compteur de reports ne change pas.

**Délais minimaux entre deux soins :**
- **Règle :** pour un même animal, un délai minimal entre deux types de soins, dans les deux sens. Par défaut : 7 jours entre un vaccin et un vermifuge.
- **Réglage :** les règles s'ajoutent, se modifient (1 à 90 jours) et se suppriment dans l'écran, selon l'avis du vétérinaire. Elles sont enregistrées par compte dans `app_settings`.
- **Soin déjà fait :** il compte à la date où il a été fait.
- **Dans le formulaire :** un avertissement donne le soin trop proche et la **première date possible**, qui respecte toutes les règles et garde la même heure, avec le bouton « Utiliser cette date ». Le rappel peut quand même être enregistré.

## Saisonnalité

Répétition **« Saison »** (`ReminderRepeat.seasonal`), pour les antipuces et antitiques :
- **en saison des parasites (mars à octobre)** : chaque mois ;
- **hors saison** : tous les 3 mois, sans dépasser le début de la saison suivante. Le rappel tombe alors le même jour en mars.

Exemples :
- 15 octobre → 15 novembre (octobre est encore dans la saison) ;
- 15 novembre → 15 février ;
- 20 janvier → 20 mars, et non 20 avril.

« Marquer fait » crée l'occurrence suivante avec cette règle ([reminder_calculator.dart](../lib/models/reminder_calculator.dart), `nextSeasonal`). L'assistant comprend « saisonnier » et « en saison ».

## Budget prévisionnel

Calculs dans [reminder_budget.dart](../lib/models/reminder_budget.dart). Les coûts viennent du module Santé (`HealthRecord.cost`).

**Coût estimé d'un rappel :**
- **Rappel issu d'un dossier de santé :** le coût de ce dossier.
- **Sinon :** le coût du dernier soin du même type (correspondance `HealthType.reminderType`), pour le même animal en priorité, puis pour un autre animal.
- **Aucun soin comparable :** « coût inconnu ».

**Prévision sur 3 mois** (mois en cours compris) :
- un rappel répété compte une fois par occurrence (marquée « répétition ») ;
- un rappel en retard compte dans le mois en cours.

Exemple : « Prévu en décembre : 145 DT (vaccin 60, détartrage 85) ».

**Plafond mensuel :**
- **Réglage :** le budget se fixe dans l'écran. Un champ vide signifie pas de plafond.
- **Dépassement :** une alerte s'affiche (« Budget dépassé de 65,00 DT »). Le bandeau de l'onglet « À venir » la signale aussi.
- **Proposition :** l'app propose de décaler au mois suivant les soins **non urgents** (contrôles, achats, « Autre »), les moins graves et les plus chers d'abord, jusqu'à repasser sous le plafond.
- **Jamais décalés :** les vaccins, traitements, vermifuges et rendez-vous, ainsi que les répétitions futures.

## Intégration avec les autres modules

Le repository est disponible partout via `context.read<ReminderRepository>()`.

### Module 2 — Santé : après l'enregistrement d'un HealthRecord

```dart
await context.read<ReminderRepository>().syncFromSource(
  source: ReminderSource.health,
  sourceId: record.id!,
  petId: record.petId,
  type: ReminderType.vaccination,          // ou deworming, checkup, treatment
  title: 'Rappel vaccin ${record.description}',
  dueDate: record.prochaineEcheance,       // null => le rappel lié est supprimé
);
await context.read<RemindersController>().load();   // rafraîchit écran + notifications
```

Intégré : `HealthController` passe par `RemindersController.syncDeadline` / `removeDeadlines` (voir [module2_sante.md](module2_sante.md)). Appeler la même méthode à chaque modification : elle crée, met à jour ou ne fait rien, sans jamais créer de doublon. À la suppression du dossier : `deleteBySource(ReminderSource.health, record.id!)`.

### Module 3 — Alimentation

Même appel avec `source: ReminderSource.feeding`, `type: ReminderType.purchase` et `dueDate` = date estimée de fin du stock.

### Module 1 — Animaux (intégré)

- Les animaux viennent de la table `pets` via `PetRepositoryDirectory` ([models/pet_repository.dart](../lib/models/pet_repository.dart)).
- Supprimer un animal supprime ses rappels dans la même transaction (`SqlitePetRepository.delete`).

### Dashboard

```dart
UpcomingRemindersCard(onSeeAll: () => /* aller à l'onglet Rappels */)
```

## Tests

```
flutter test
```

Les tests utilisent une vraie base SQLite en mémoire (`sqflite_common_ffi`).

| Fichier | Couvre |
|---|---|
| `sqlite_reminder_repository_test.dart` | CRUD, **T02**, doublons, **T04**, **T07**, répétition, annulation, index unique, suppressions |
| `reminder_calculator_test.dart` | jours restants, libellés, regroupement, répétition (fin de mois, 29 février), alertes, report |
| `reminders_controller_test.dart` | chargement, erreurs, filtres, fait / annuler, T07, notifications, démo |
| `reminder_form_controller_test.dart` | T02, date passée, aperçu des alertes, doublon, modification |
| `reminders_screen_test.dart` | écran, onglets, filtre animal, aucun débordement à 360 dp, assistant |
| `assistant_parser_test.dart` | dates en français, intentions, titres extraits, recherche d'un rappel |
| `reminder_assistant_controller_test.dart` | conversations complètes sur SQLite : créer, confirmer, annuler, choisir, reporter, supprimer |

## Démo

Menu ⋮ de l'écran Rappels :
- **Charger des exemples** : les rappels du cahier des charges (vermifuge demain, vaccin dans 10 jours, rendez-vous le 20/11, etc.)
- **Simuler une échéance Santé** : montre la synchronisation et l'anti-doublon (choisir deux fois la même date)
- **Tester une notification** / **Autoriser les notifications**
