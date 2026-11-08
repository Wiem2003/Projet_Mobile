import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/health_booklet_controller.dart';
import 'package:smart_pet/controllers/pets_controller.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/pets_model.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';
import 'package:smart_pet/views/screens/pets_screen.dart';

import '../reminders/test_helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late FakePhotoStore photos;

  Future<PetsModel> pump(WidgetTester tester,
      {bool demo = false, Size size = const Size(412, 1400)}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 3, 14));
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final model = PetsModel(clock: clock.call);
    photos = FakePhotoStore();
    final ctrl = PetsController(
        model: model,
        repository: SqlitePetRepository(db, clock: clock.call),
        photos: photos);
    await ctrl.load();
    if (demo) await ctrl.seedDemo();

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: ctrl),
        ChangeNotifierProvider.value(value: model),
        ChangeNotifierProvider(create: (_) => HealthModel(clock: clock.call)),
        Provider.value(value: HealthBookletController(clock: clock.call)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const PetsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    return model;
  }

  testWidgets('écran vide, exemples et recherche', (tester) async {
    await pump(tester);
    expect(find.text('Aucun animal pour l\'instant'), findsOneWidget);
    await tester.tap(find.text('Charger des exemples'));
    await tester.pumpAndSettle();
    expect(find.byType(PetCard), findsNWidgets(3));
    expect(find.text('3 animaux · 🐕 1  🐈 1  🐦 1'), findsOneWidget);
    expect(find.text('3 ans et 1 mois · 28 kg'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'perruche');
    await tester.pumpAndSettle();
    expect(find.byType(PetCard), findsOneWidget);
    expect(find.text('Coco'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zèbre');
    await tester.pumpAndSettle();
    expect(find.text('Aucun animal ne correspond.'), findsOneWidget);
  });

  testWidgets('ajouter un animal avec photo, validation du nom',
      (tester) async {
    final model = await pump(tester);
    await tester.tap(find.text('Ajouter un animal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter l\'animal'));
    await tester.pumpAndSettle();
    expect(find.text('Le nom est obligatoire'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Ex. Rex'), 'Filou');
    await tester.tap(find.text('Chat'));
    await tester.tap(find.text('♀ Femelle'));
    await tester.tap(find.text('Galerie'));
    await tester.pumpAndSettle();
    expect(find.text('Retirer'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Facultatif — ex. 12,5'), '3,8');
    await tester.tap(find.text('Ajouter l\'animal'));
    await tester.pumpAndSettle();

    expect(find.text('Fiche de Filou créée'), findsOneWidget);
    final filou = model.all.single;
    expect((filou.species, filou.sex, filou.weightKg),
        (Species.cat, PetSex.female, 3.8));
    expect(filou.photoPath, '/data/pet_photos/photo_1.jpg');
    expect(find.byType(PetCard), findsOneWidget);
  });

  testWidgets('consulter, modifier puis supprimer', (tester) async {
    final model = await pump(tester, demo: true);
    await tester.tap(find.text('Rex'));
    await tester.pumpAndSettle();
    expect(find.text('🐕 Chien · Berger allemand · ♂ Mâle'), findsOneWidget);
    expect(find.text('250269812345678'), findsOneWidget);
    expect(find.textContaining('(3 ans et 1 mois)'), findsOneWidget);

    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier Rex'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Noir et feu'), 'Fauve');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Fauve'), findsOneWidget);

    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer Rex ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Fiche de Rex supprimée'), findsOneWidget);
    expect(model.all.map((p) => p.name), ['Coco', 'Mia']);
    expect(find.byType(PetCard), findsNWidgets(2));
  });

  testWidgets('doublon de nom affiché dans le formulaire', (tester) async {
    await pump(tester, demo: true);
    await tester.tap(find.text('Ajouter un animal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Ex. Rex'), 'mia');
    await tester.tap(find.text('Ajouter l\'animal'));
    await tester.pumpAndSettle();
    expect(find.text('Un animal nommé « mia » existe déjà.'), findsOneWidget);
  });

  testWidgets('aucun débordement sur un petit écran (360 dp)', (tester) async {
    await pump(tester, demo: true, size: const Size(360, 740));
    await tester.tap(find.text('Mia'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -2500));
    await tester.pumpAndSettle();
    expect(find.text('Numéro d\'identification'.toUpperCase()), findsOneWidget);
  });
}
