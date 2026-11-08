# Smart Pet Manager

Application mobile Flutter (Android / iOS) de gestion de la vie et des dépenses des animaux.
Architecture **MVC** (Model – View – Controller), base de données **SQLite locale** (`sqflite`) : l'app fonctionne hors ligne, sans serveur.

| Module | Entité | État |
|---|---|---|
| **1. Animaux** | **`Pet`** (+ photo) | **fait** — voir [docs/module1_animaux.md](docs/module1_animaux.md) |
| **2. Santé** | **`HealthRecord`** (+ carnet de vaccination, carnet PDF) | **fait** — voir [docs/module2_sante.md](docs/module2_sante.md) |
| **3. Alimentation** | **`FeedingRecord`** (+ ration, friandises, appétit, horaires, stock des sacs, perte de poids, budget) | **fait** — voir [docs/module3_alimentation.md](docs/module3_alimentation.md) |
| **4. Activités** | **`Activity`** (+ GPS, charge, bilan énergétique, records) | **fait** — voir [docs/module4_activites.md](docs/module4_activites.md) |
| **5. Rappels & alertes** | **`Reminder`** (+ priorité, escalade, observance, planification, budget) | **fait** — voir [docs/module5_rappels.md](docs/module5_rappels.md) |
| **Comptes** | **`AppUser`** (rôles admin / user) | **fait** — voir ci-dessous |
| **Accueil** | indice, alertes croisées, coûts, rapport mensuel | **fait** — voir [docs/accueil_tableau_de_bord.md](docs/accueil_tableau_de_bord.md) |

## Comptes : Sign up, Sign in, rôles

Au lancement, l'app affiche l'écran **Connexion** (Sign in), avec un lien vers **Créer un compte** (Sign up). Les comptes sont stockés dans la base SQLite du téléphone (table `users`), sans serveur.

- **Sign up :** nom, e-mail unique, mot de passe de 8 caractères minimum (au moins une lettre et un chiffre), confirmation.
- **Captcha :** la connexion et la création de compte demandent de cocher « Je ne suis pas un robot », puis de recopier un code de 5 caractères dessiné et brouillé par l'app (sans 0, O, 1, I ni L ; majuscules ou minuscules). Le captcha fonctionne hors ligne, sans clé Google. Après 3 erreurs, un nouveau code s'affiche ; le bouton ⟳ en donne un autre. Une vérification ne sert qu'une fois : après une tentative refusée, il faut recommencer. L'admin qui crée un compte depuis l'Administration, déjà connecté, n'en a pas.
- **Sign in :** e-mail et mot de passe. Après 5 essais ratés, le compte est bloqué 5 minutes. La session reste ouverte jusqu'à « Se déconnecter » (écran **Mon compte**, avatar en haut de l'accueil).
- **Mot de passe :** il n'est jamais enregistré en clair, seulement son empreinte (PBKDF2-HMAC-SHA256 avec un sel aléatoire, [password_hasher.dart](lib/models/auth/password_hasher.dart)).
- **Photo de profil :** facultative, choisie avec l'appareil photo ou la galerie à l'inscription, dans **Mon compte** (« Changer la photo ») ou par un administrateur. Elle est copiée dans le stockage de l'app (dossier `user_photos`), et supprimée quand elle est remplacée ou quand le compte est supprimé. La photo des animaux se choisit de la même façon dans le formulaire « Ajouter un animal ».
- **Données par compte :** chaque utilisateur ne voit que ses animaux, leurs soins, repas, activités et rappels. À la déconnexion, les notifications du compte sont annulées.

| Rôle | Droits |
|---|---|
| **user** | ses propres données (les cinq modules), son profil (nom, mot de passe) |
| **admin** | les mêmes droits, plus l'écran **Administration** : statistiques de l'app, liste des comptes, **créer un compte** utilisateur ou administrateur (bouton « Ajouter un compte »), **modifier un compte** (nom, e-mail, rôle, statut actif, photo, nouveau mot de passe), nommer ou retirer un administrateur, désactiver ou réactiver un compte, supprimer un compte et toutes ses données |

- **Rôle à l'inscription :** l'écran « Créer un compte » propose **Utilisateur** ou **Administrateur**. Le premier compte créé sur le téléphone est toujours administrateur ; il récupère aussi les données saisies avant l'ajout des comptes.
- **Comptes suivants :** ils sont `user`. Un admin peut les nommer administrateurs.
- **Garde-fous :** un admin ne peut pas modifier son propre compte depuis l'administration, et il reste toujours au moins un administrateur actif.

Code (MVC) :
- Models : [lib/models/auth/](lib/models/auth/) (`AppUser`, `SqliteUserRepository`, `AuthModel`, `AdminModel`).
- Controllers : [auth_controller.dart](lib/controllers/auth_controller.dart), [admin_controller.dart](lib/controllers/admin_controller.dart), [user_session.dart](lib/controllers/user_session.dart) (les cinq modules du compte connecté).
- Views : [auth_screens.dart](lib/views/screens/auth_screens.dart), [account_screen.dart](lib/views/screens/account_screen.dart), [admin_screen.dart](lib/views/screens/admin_screen.dart).

## Lancer le projet (PowerShell)

```powershell
flutter pub get
flutter emulators --launch Medium_Phone   # attendre l'écran d'accueil Android
flutter run
```

Ou brancher un téléphone Android en mode développeur, puis `flutter run`.

## Mot de passe oublié (e-mail)

Sur l'écran **Connexion**, le lien **Mot de passe oublié ?** déroule ce parcours :
1. Saisir l'e-mail du compte et valider le captcha.
2. Un code à 6 chiffres est envoyé à cette adresse par Gmail, depuis **souhirzitoun2003@gmail.com**.
3. Sur l'écran **Nouveau mot de passe**, saisir le code puis le nouveau mot de passe.
4. Retour à la connexion, avec l'e-mail déjà rempli.

Règles :
- **Validité du code :** 15 minutes, un seul usage. Seule l'empreinte du code est enregistrée.
- **Essais :** après 5 codes faux, le code est annulé.
- **Nouveau code :** « Renvoyer le code » est possible après 60 s, et l'ancien code ne fonctionne plus.
- **Comptes protégés :** la réponse est la même que l'adresse ait un compte ou non. Un compte désactivé ne reçoit pas de code.
- **Blocage levé :** un mot de passe changé lève le blocage de 5 minutes.

### Configuration de l'envoi

Gmail exige un **mot de passe d'application**, pas le mot de passe du compte Google :
1. Sur le compte souhirzitoun2003@gmail.com, activer la **validation en deux étapes**.
2. Ouvrir https://myaccount.google.com/apppasswords, créer un mot de passe d'application nommé « Smart Pet » et copier les 16 lettres.
3. Les coller dans `env.json`, qui ne doit jamais être commité :
   ```json
   "RESET_MAIL_SENDER": "souhirzitoun2003@gmail.com",
   "GMAIL_APP_PASSWORD": "abcd efgh ijkl mnop"
   ```
4. Lancer l'app avec `flutter run --dart-define-from-file=env.json`.

**Sans mot de passe d'application :** en mode debug, le code s'affiche à l'écran (« Mode démo »), ce qui permet de tester sur l'émulateur. En release, l'app indique que l'envoi n'est pas configuré.

**Attention :** comme la clé Gemini, ce mot de passe est intégré à l'APK. Il donne accès à l'envoi d'e-mails depuis ce compte Gmail. Pour une app publiée, il faut passer par un serveur.

## Assistant Gemini (facultatif)

Sans clé, l'assistant fonctionne hors ligne (règles en Dart, rappels uniquement). Avec une clé Gemini, il répond sur les cinq modules et agit sur les rappels. La même clé permet aussi d'ajouter au **carnet de santé PDF** une synthèse rédigée par Gemini (résumé, points d'attention, conseils, questions pour le vétérinaire) ; voir [docs/module2_sante.md](docs/module2_sante.md).

1. Créer une clé sur https://aistudio.google.com/apikey.
2. Créer à la racine du projet un fichier `env.json` (il est ignoré par Git : **ne jamais commiter de clé**) :
   ```json
   { "GEMINI_API_KEY": "votre-clé", "GEMINI_MODEL": "gemini-3.5-flash" }
   ```
3. Lancer avec la clé :
   ```powershell
   flutter run --dart-define-from-file=env.json
   ```
   Dans VS Code : configuration **smart_pet (Gemini)** (F5).

Points à connaître :
- **Surcharge de Gemini :** si le modèle est surchargé, les suivants sont essayés (`gemini-flash-latest`, puis `gemini-flash-lite-latest`). Au-delà de 45 s, ou sans Internet, l'assistant hors ligne répond.
- **Suppression :** supprimer un rappel exige toujours un « oui » de l'utilisateur. C'est l'app qui le vérifie, pas Gemini.
- **Confidentialité :** les questions et les données utiles à la réponse sont envoyées à Google.
- **Clé visible dans l'APK :** la clé est intégrée à l'APK et peut en être extraite. Pour une app publiée, restreindre la clé (Google Cloud → Identifiants → restriction aux applications Android) ou passer par un serveur intermédiaire.

Code : [gemini_client.dart](lib/models/assistant/gemini_client.dart) (API REST), [assistant_tools.dart](lib/controllers/assistant_tools.dart) (outils), [gemini_assistant_controller.dart](lib/controllers/gemini_assistant_controller.dart) (conversation).

## Contrôles de saisie

Les règles sont dans les Models et sont vérifiées à deux endroits :
- **le formulaire**, champ par champ, dès que l'utilisateur a touché un champ ;
- **le repository**, avant l'écriture en base.

Les règles communes sont dans [validation.dart](lib/models/validation.dart) (`InputRules`), les filtres de frappe dans [input_formatters.dart](lib/views/widgets/input_formatters.dart).

| Formulaire | Contrôles |
|---|---|
| Tous | champs numériques : chiffres et une virgule uniquement, décimales limitées ; textes : longueur maximale, caractères interdits (`< > { }`), au moins une lettre ou un chiffre |
| Animal | nom obligatoire et unique ; race et couleur : lettres, chiffres, espaces, `'` et `-` ; numéro : puce de 15 chiffres ou tatouage de 4 à 10 caractères, unique ; poids plausible pour l'espèce (ex. chat 0,3 à 15 kg) ; naissance ni future ni avant 1950 |
| Santé | date ni future ni avant la naissance ; nom du vaccin ou du médicament obligatoire pour un vaccin ou un traitement ; échéance après le soin et au plus dans 10 ans ; coût de 0 à 100 000 DT ; poids plausible pour l'espèce |
| Repas | quantité obligatoire, plausible (au plus 30 % du poids de l'animal par jour) ; prix de 0 à 10 000 DT ; 1 à 10 repas ; date ni future ni avant la naissance |
| Activité | durée de 1 min à 24 h (entier) ; distance jusqu'à 200 km ; vitesse plausible (promenade 12 km/h, course 70 km/h, natation 10 km/h) ; poids plausible ; date et heure ni futures ni avant la naissance |
| Rappel | titre obligatoire (80 caractères) ; notes (500) ; date future ; pas de doublon |
| Compte | nom obligatoire ; e-mail valide et unique ; mot de passe de 8 à 64 caractères avec au moins une lettre et un chiffre ; confirmation identique |
| Assistant, recherche | message limité à 500 caractères, recherche à 60 caractères |

## Tests

367 tests, sans téléphone ni Internet. La base SQLite est en mémoire, et les notifications, le GPS, les photos et Gemini sont simulés.

```powershell
flutter test                      # tout le projet
flutter test test/pets            # un module : pets, health, feeding, activities, reminders, assistant, auth
flutter test --coverage           # + couverture dans coverage/lcov.info
```

| Dossier | Ce qui est testé |
|---|---|
| `test/models` | états des Models (chargement, erreur, filtres, recherche), règles partagées |
| `test/pets` | repository SQLite (unicité, suppression en cascade), Controllers, photo, écrans |
| `test/health` | calculs (consultations, dépenses, poids), rappels automatiques, pesées, écrans |
| `test/feeding` | calculs du mois, CRUD, « Reprendre le dernier repas », écrans |
| `test/activities` | calories, semaines glissantes, GPS (filtrage, pause), écrans |
| `test/reminders` | rappels, notifications, chatbot hors ligne, priorité et escalade, limites de report, observance, journées chargées, délais minimaux, saisonnalité, budget, écrans |
| `test/assistant` | client Gemini (HTTP simulé), outils, confirmation de suppression, repli hors ligne |
| `test/auth` | Sign up / Sign in, captcha, mot de passe oublié, blocage après 5 essais, rôles, administration, données séparées par compte, parcours à l'écran |
| `test/dashboard` | indice Smart Pet, alertes croisées, coûts, rapport mensuel (texte, PDF), partage, accueil |
| `test/database` | migrations v1 → v7 |
| `test/app_test.dart` | application complète : liens entre les cinq modules |


## Structure

```
lib/
├── main.dart            Injection : AppDatabase, comptes (AuthController), notifications
├── app.dart             Porte d'entrée : Sign in, puis les modules du compte connecté
├── models/            MODEL : entités, accès SQLite, règles métier, état observé
├── views/             VIEW : écrans, feuilles et widgets (home_shell = barre du bas)
├── controllers/       CONTROLLER : reçoivent les actions, mettent à jour les models
└── core/              commun à tous les modules
    ├── database/      AppDatabase : base SQLite partagée, tables et migrations
    ├── pets/          PetDirectory (lien avec le module Animaux)
    └── theme/         couleurs par module, thème clair / sombre
```

La base est en **version 7** (tables `users`, `pets`, `health_records`, `feeding_records`, `activities`, `reminders`). Sur une base existante, la migration ajoute les tables manquantes sans perdre de données.

Les modules sont reliés : les animaux du module 1 sont proposés partout ; les échéances de santé deviennent des rappels ; la dernière pesée met à jour le poids de l'animal ; supprimer un animal supprime ses données dans tous les modules.

Chaque module ajoute ses fichiers dans ces trois dossiers (ex. `models/pet.dart`, `controllers/pets_controller.dart`, `views/screens/pets_screen.dart`). Ses tables sont ajoutées dans `core/database/app_database.dart`.
