# Module 2 — Santé & vaccinations (`HealthRecord`)

Le carnet de santé : vaccins, traitements, consultations, détartrages, analyses. Calcul des dépenses médicales et suivi du poids ; chaque prochaine échéance devient un rappel.

**Architecture :** MVC. **Données :** table SQLite `health_records` dans la base partagée `smart_pet.db`. Tout fonctionne hors ligne.

## Fichiers (MVC)

```
lib/
├── models/
│   ├── health_record.dart             entité + HealthType + règles de validation
│   ├── health_repository.dart         interface d'accès aux données
│   ├── sqlite_health_repository.dart  CRUD SQLite
│   ├── health_stats.dart              calculs automatiques, périodes, pesées
│   ├── health_model.dart              état de l'écran : dossiers, filtres, prochaines échéances
│   └── health_form_model.dart         dossier en cours de saisie, échéances proposées
├── controllers/
│   ├── health_controller.dart         CRUD + synchronisation des rappels + poids de l'animal
│   └── health_form_controller.dart
└── views/
    ├── screens/health_screen.dart       indicateurs, courbe de poids, échéances, historique par mois
    ├── screens/health_form_screen.dart
    ├── widgets/line_chart_card.dart     courbe « Évolution du poids »
    └── health_actions.dart, health_style.dart
```

## Données

| Champ | Colonne | Règle |
|---|---|---|
| Type | `type` | 💉 vaccination, 💊 traitement, 🩺 consultation, 🦷 détartrage, 🧪 analyse, autre |
| Date | `date` | pas dans le futur |
| Animal | `pet_id` | obligatoire |
| Vétérinaire | `vet` | facultatif |
| Description | `description` | 500 caractères maximum |
| Poids | `weight_kg` | facultatif (pesée lors de la visite) |
| Médicament | `medication` | facultatif |
| Coût | `cost` | ≥ 0, en DT |
| Prochaine échéance | `next_due` | facultative, après la date du soin |

## CRUD

| Action | Où |
|---|---|
| ➕ Ajouter | « Ajouter un dossier » ; échéances proposées selon le type (vaccin : 1 an…) |
| 👁️ Historique | liste groupée par mois avec le total du mois ; filtres animal, type, période |
| ✏️ Modifier | toucher la ligne, ou menu ⋮ → Modifier |
| 🗑️ Supprimer | menu ⋮ → Supprimer (le rappel lié est supprimé aussi) |

## Calculs automatiques (`HealthStats.compute`)

Ils portent sur la période choisie (3 mois, 12 mois, tout) et l'animal sélectionné.

| Indicateur | Formule |
|---|---|
| Nombre de consultations | dossiers de type Consultation |
| Dépenses médicales | somme des coûts |
| Poids moyen | moyenne des pesées de l'animal |
| Évolution du poids | dernière pesée − première pesée (kg et %), plus la courbe |

Le poids n'a de sens que par animal. Avec « Tous » et plusieurs animaux, l'écran demande d'en choisir un. Le filtre de type ne masque pas les pesées.

## Carnet de vaccination

Règles dans [vaccination_booklet.dart](../lib/models/vaccination_booklet.dart). La carte « Carnet de vaccination » est sur la fiche de l'animal (Mes animaux → animal).

**Vaccins reconnus** dans le nom saisi au dossier (accents et majuscules ignorés). Un dossier « CHPPi + rage » compte pour les deux.

| Vaccin | Mots reconnus |
|---|---|
| Rage | rage, rabies, rabique, Rabisin |
| CHPPi | CHPPi, CHPP, DHPP, Carré, parvo, hépatite |
| Leptospirose | lepto |
| Typhus / Coryza | typhus, panleucopénie / coryza |
| Leucose féline | leucose, FeLV |
| Autre vaccin | tout autre nom |

**Validité :**
- **Échéance saisie :** c'est la date d'expiration. Par exemple, une rage valable 3 ans avec l'échéance rapide « Dans 3 ans ».
- **Sans échéance :** 1 an après l'injection.

**Statut :**
- **À jour** ;
- **Bientôt expiré** : il reste moins de 30 jours, affiché « J-27 » ;
- **Expiré**.

La fiche résume le carnet : « Vaccins à jour », « 1 vaccin expiré », « 2 vaccins bientôt expirés » ou « Aucun vaccin enregistré ». Elle signale aussi les vaccins conseillés jamais saisis : CHPPi et rage pour un chien, typhus et coryza pour un chat.

**Voyage ou pension** (bouton « Vérifier un voyage », avec une date de départ) :
- **Rage obligatoire :** elle doit être enregistrée.
- **Délai de 21 jours :** une première injection doit dater d'au moins 21 jours avant le départ. Un rappel fait avant l'expiration du précédent protège sans attendre.
- **Validité :** la rage doit être encore valable le jour du départ. Exemple de refus : « Rex ne peut pas voyager le 15/12 : rage expirée le 03/12 ».
- **Points à vérifier (non bloquants) :** les autres vaccins expirés à cette date, souvent exigés par les pensions.

## Carnet de santé PDF

[health_booklet_pdf.dart](../lib/models/health_booklet_pdf.dart), bouton « Carnet de santé PDF » de la fiche. Il réutilise le partage et la police du rapport mensuel ([pdf_fonts.dart](../lib/models/pdf_fonts.dart)).

**Contenu :**
- l'identité (espèce, race, sexe, naissance et âge, couleur, puce ou tatouage, poids) ;
- les **allergies**, en rouge si renseignées ;
- les vaccins et leur statut ;
- les traitements, avec la date de renouvellement ;
- les autres soins ;
- la **courbe de poids**, avec les dernières pesées.

À partager avec une pension, un nouveau vétérinaire ou le pet-sitter.

### Synthèse rédigée par Gemini

**Accès :** fiche animal → **Carnet de santé PDF (Gemini)**, ou écran **Santé** → menu ⋮ → **Carnet de santé PDF**. Le menu propose l'animal choisi en haut, sinon il demande lequel.

Avec une clé Gemini, l'app demande d'abord **« Avec synthèse Gemini »** ou **« Carnet simple »**. Le premier choix ajoute en tête du PDF un encadré contenant :
- une synthèse de 3 à 5 phrases sur l'état de santé ;
- les points d'attention (vaccin expiré, échéance dépassée, poids, allergies, traitements) ;
- des conseils pratiques ;
- les questions à poser au vétérinaire.

**Règles :**
- **Prudence :** Gemini doit s'en tenir aux données du carnet, sans diagnostic ni médicament ou dose. L'encadré indique qu'il ne remplace pas l'avis d'un vétérinaire.
- **Données envoyées :** l'espèce, la race, le sexe, l'âge, la stérilisation, le poids, les allergies, les vaccins et leur statut, et les 40 derniers soins (sans le vétérinaire ni le coût). Ni le propriétaire ni le numéro de puce ne sont envoyés.
- **Format de la réponse :** Gemini répond en JSON. Les listes sont limitées à 5 éléments et les textes trop longs sont coupés. Les emojis et symboles que la police du PDF ne sait pas afficher sont retirés.
- **Repli :** sans Internet, si Gemini est surchargé ou si sa réponse est illisible, le carnet est partagé **sans la synthèse**, avec un message qui en donne la raison.
- **Sans clé Gemini :** le carnet simple est partagé directement.

Code : [health_ai_summary.dart](../lib/models/health_ai_summary.dart), [health_booklet_controller.dart](../lib/controllers/health_booklet_controller.dart) et [health_booklet_actions.dart](../lib/views/health_booklet_actions.dart).

**Allergies :** un champ facultatif de la fiche animal (200 caractères, mêmes contrôles que les autres textes). La base passe en **version 5** pour ajouter la colonne `pets.allergies`.

## Liens avec les autres modules

- **Rappels :** la prochaine échéance devient un rappel, avec le même animal, à 9 h, et des notifications J-10, J-1 et le jour J. Elle passe par `RemindersController.syncDeadline` (source `health`, sans doublon).
  - Seul le dossier **le plus récent** d'un type garde son échéance. Quand on refait un vaccin, le rappel de l'ancien vaccin est retiré.
  - Si on supprime ce dossier récent, l'échéance du précédent revient.
- **Animaux :** la dernière pesée devient le poids de la fiche de l'animal (`onWeightMeasured`). Ce poids sert ensuite aux calories du module Activités.

## Tester

```powershell
flutter test test/health
```

Sur l'émulateur : onglet **Santé** → ⋮ → **Charger des exemples**. Ces exemples créent un an de suivi pour le chien et le chat, et leurs échéances apparaissent dans l'onglet **Rappels**.
