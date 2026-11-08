# Module 1 — Gestion des animaux (`Pet`)

Les fiches des animaux : identité, photo, poids. Tous les autres modules (Santé, Repas, Activités, Rappels) proposent les animaux enregistrés ici.

**Architecture :** MVC. **Données :** table SQLite `pets` dans la base partagée `smart_pet.db`. Les photos sont copiées dans le stockage privé de l'app (dossier `pet_photos`). Tout fonctionne hors ligne.

## Fichiers (MVC)

```
lib/
├── models/
│   ├── pet.dart                    entité + Species + PetSex + âge + règles de validation
│   ├── pet_repository.dart         interface + PetRepositoryDirectory (lien avec les autres modules)
│   ├── sqlite_pet_repository.dart  CRUD SQLite, unicité, suppression en cascade
│   ├── pet_photo_store.dart        appareil photo / galerie (image_picker), copie du fichier
│   ├── pets_model.dart             liste, recherche
│   └── pet_form_model.dart         animal en cours de saisie, validation, aperçu de l'âge
├── controllers/
│   ├── pets_controller.dart        chargement, ajout, modification, suppression, exemples
│   └── pet_form_controller.dart    saisie, photo, nettoyage des photos abandonnées
└── views/
    ├── screens/pets_screen.dart        « Mes animaux » : grille, recherche
    ├── screens/pet_detail_screen.dart  « Consulter » : fiche + résumé santé + courbe de poids
    ├── screens/pet_form_screen.dart
    ├── widgets/pet_photo.dart          photo ou emoji de l'espèce
    └── pet_actions.dart
```

Accès : **Accueil → Mes animaux** (« Voir tout », ou toucher un animal, ou « Ajouter »).

## Données

| Champ | Colonne | Règle |
|---|---|---|
| Nom | `name` | obligatoire, 40 caractères, unique (sans tenir compte des majuscules) |
| Espèce | `species` | chien, chat, oiseau, lapin, rongeur, poisson, reptile, cheval, autre |
| Race | `breed` | facultative |
| Sexe | `sex` | mâle, femelle, inconnu |
| Date de naissance | `birth_date` | facultative, pas dans le futur ; l'âge est calculé |
| Poids | `weight_kg` | facultatif, mis à jour par chaque pesée du module Santé |
| Couleur | `color` | facultative |
| Numéro d'identification | `identification` | puce ou tatouage, facultatif, **unique** (espaces retirés, majuscules) |
| Photo | `photo_path` | appareil photo ou galerie |

## CRUD

| Action | Où |
|---|---|
| ➕ Ajouter | « Ajouter un animal » (photo : Appareil photo / Galerie) |
| 👁️ Consulter | toucher la carte : fiche, âge, résumé santé, prochaine échéance, évolution du poids |
| ✏️ Modifier | bouton crayon de la fiche |
| 🗑️ Supprimer | bouton corbeille : la confirmation indique ce qui sera supprimé dans les autres modules |

La suppression est faite **en une transaction** : dossiers de santé, repas, activités et rappels de l'animal sont supprimés avec lui, ainsi que sa photo.

## Bonus : plusieurs animaux

Un même utilisateur gère autant d'animaux qu'il veut. Chaque module a un sélecteur d'animal (« Tous » ou un animal) qui filtre la liste et les calculs.

## Lien avec les autres modules

- Les modules lisent les animaux via `PetDirectory` (`PetRepositoryDirectory` dans l'app, `DemoPetDirectory` dans les tests).
- Après chaque ajout, modification ou suppression, `PetsController.onPetsChanged` recharge les autres modules (branché dans `main.dart`).
- **Migration v3 :** sur une base déjà installée, Rex (id 1) et Mia (id 2) sont recréés s'ils ont déjà des données, pour que rien ne soit perdu.
- **Nouvelle installation :** aucun animal n'est créé ; les formulaires des autres modules demandent d'en ajouter un.

## Tester

```powershell
flutter test test/pets
```

Sur l'émulateur : **Accueil → Mes animaux → Voir tout** → ⋮ → **Charger des exemples** (Rex, Mia, Coco).
