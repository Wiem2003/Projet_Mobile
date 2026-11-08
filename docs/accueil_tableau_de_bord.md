# Accueil — Tableau de bord

L'accueil croise les données des cinq modules. Les calculs sont des fonctions pures dans [lib/models/dashboard/](../lib/models/dashboard/), testées dans `test/dashboard/`.

## Indice Smart Pet (0 à 100)

[smart_pet_index.dart](../lib/models/dashboard/smart_pet_index.dart). Une pastille sur la bulle de chaque animal, une carte « Indice Smart Pet », et le détail de chaque critère en touchant l'animal.

| Critère | Points | Règle |
|---|---|---|
| Soins à jour (Rappels) | 30 | −15 par rappel critique (plus de 3 jours de retard), −5 par rappel en retard |
| Activité de la semaine (Activités) | 25 | minutes des 7 derniers jours ÷ objectif de la semaine selon l'espèce et la taille (chien : 210, 420 ou 630 min ; chat 210 ; lapin 120 ; cheval 420), voir [module 4](module4_activites.md) ; autres espèces : 25 |
| Poids stable (Santé) | 25 | variation < 5 % en 2 mois : 25 ; < 10 % : 12 ; sinon 0 ; une seule pesée : 20 ; aucune pesée depuis 2 mois : 15 |
| Repas saisis (Alimentation) | 20 | jours avec un repas sur les 7 derniers × 20 / 7 |

Couleur : vert à partir de 80, orange de 50 à 79, rouge en dessous. Le détail donne ce qui fait baisser la note : « Rex : 49 (−20 : 1 rappel critique et 1 rappel en retard, …) ».

## Alertes croisées

[cross_alerts.dart](../lib/models/dashboard/cross_alerts.dart).

| Alerte | Règle |
|---|---|
| Risque de prise de poids | repas (grammes) +20 % et activité (minutes) −30 %, 30 derniers jours par rapport aux 30 précédents |
| Perte de poids | −8 % ou plus en 2 mois (pesées du module Santé) |
| Repas non saisis | aucun repas depuis 3 jours, pour un animal dont les repas sont suivis |
| Dépense inhabituelle | dépenses du mois (santé + alimentation) supérieures de 50 % à la moyenne des 3 mois précédents. La cause est le soin le plus cher du mois, sinon l'alimentation la plus chère |

« Ne plus afficher pendant 30 jours » masque une alerte. Le masquage est enregistré par compte (`app_settings`). L'alerte de dépense est propre à chaque mois.

## Coût de revient par animal

[pet_costs.dart](../lib/models/dashboard/pet_costs.dart). La carte « Coût par animal » ouvre l'écran de détail.

- **Mois en cours :** santé + alimentation, et coût par jour (total ÷ jours écoulés).
- **Moyenne des 3 derniers mois complets.**
- **Projection sur 12 mois :** alimentation (moyenne des 3 derniers mois × 12) + soins déjà prévus dans les rappels, au coût estimé du budget prévisionnel.
- **Comparaison :** « Rex coûte 2,5 fois plus que Mia, surtout en alimentation ». Elle n'apparaît qu'à partir d'un écart de 20 %, sur les 3 derniers mois. La catégorie citée est celle où l'écart est le plus grand.

## Rapport mensuel

[monthly_report.dart](../lib/models/dashboard/monthly_report.dart), [report_pdf.dart](../lib/models/dashboard/report_pdf.dart).

**Disponibilité :** à partir du 1er du mois, l'accueil affiche « Votre rapport de octobre 2026 est prêt » jusqu'à ce qu'il soit ouvert ou masqué. Les mois précédents restent consultables (flèches), et le mois en cours donne un rapport provisoire.

**Contenu :**
- les dépenses par module ;
- pour chaque animal :
  - ses soins (date, type, médicament, vétérinaire, coût) ;
  - ses rappels du mois : faits à temps, faits en retard, non faits ;
  - son activité : séances, minutes, km, kcal ;
  - l'évolution de son poids.

**Partage :** en texte ou en PDF, par la feuille de partage du téléphone (paquet `share_plus` : e-mail, WhatsApp…). Le PDF est généré en Dart (paquet `pdf`), avec la police Roboto intégrée pour les accents ([assets/fonts](../assets/fonts/), licence Apache 2.0).

## Code (MVC)

- **Models :** [lib/models/dashboard/](../lib/models/dashboard/). `DashboardModel` contient les préférences : alertes masquées et dernier rapport vu.
- **Controller :** [dashboard_controller.dart](../lib/controllers/dashboard_controller.dart), pour masquer une alerte, marquer le rapport comme vu et partager.
- **Views :**
  - [dashboard_cards.dart](../lib/views/widgets/dashboard_cards.dart) ;
  - [monthly_report_screen.dart](../lib/views/screens/monthly_report_screen.dart) ;
  - [pet_cost_screen.dart](../lib/views/screens/pet_cost_screen.dart) ;
  - [dashboard_data.dart](../lib/views/dashboard_data.dart), qui lit les Models des cinq modules.
