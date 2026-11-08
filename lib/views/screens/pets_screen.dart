import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/pets_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/pet.dart';
import '../../models/pets_model.dart';
import '../formatters.dart';
import '../pet_actions.dart';
import '../widgets/empty_state.dart';
import '../widgets/pet_photo.dart';

/// Écran principal du Module 1 — Mes animaux : liste, recherche et ajout.
class PetsScreen extends StatelessWidget {
  const PetsScreen({super.key});

  static const _color = AppColors.pet;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PetsModel>();
    final controller = context.read<PetsController>();
    final pets = model.visible;
    final species = model.countBySpecies.entries
        .map((e) => '${e.key.emoji} ${e.value}')
        .join('  ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes animaux'),
        backgroundColor: _color,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
        actions: [
          PopupMenuButton<int>(
            onSelected: (_) => PetActions.seedDemo(context),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 0,
                child: ListTile(
                  leading: Icon(Icons.auto_fix_high_rounded),
                  title: Text('Charger des exemples'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _color,
        onRefresh: controller.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!model.isEmpty) ...[
                      Text(
                        '${model.all.length} '
                        '${model.all.length > 1 ? 'animaux' : 'animal'} · $species',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        onChanged: controller.setQuery,
                        inputFormatters: [LengthLimitingTextInputFormatter(60)],
                        decoration: const InputDecoration(
                          hintText: 'Rechercher (nom, race, puce…)',
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                      ),
                    ],
                    if (model.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(model.error!,
                            style: const TextStyle(color: AppColors.danger)),
                      ),
                  ],
                ),
              ),
            ),
            if (model.loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(color: _color)),
                ),
              )
            else if (model.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.pets_rounded,
                  color: _color,
                  title: 'Aucun animal pour l\'instant',
                  message: 'Ajoutez vos animaux : ils seront proposés dans la '
                      'santé, les repas, les activités et les rappels.',
                  action: OutlinedButton.icon(
                    onPressed: () => PetActions.seedDemo(context),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: const Text('Charger des exemples'),
                  ),
                ),
              )
            else if (pets.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Aucun animal ne correspond.')),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 236,
                  ),
                  itemCount: pets.length,
                  itemBuilder: (_, i) => PetCard(pet: pets[i], now: model.now),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-pet',
        backgroundColor: _color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter un animal',
            style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => PetActions.openForm(context),
      ),
    );
  }
}

/// Carte d'un animal : photo, nom, espèce, âge et poids.
class PetCard extends StatelessWidget {
  const PetCard({super.key, required this.pet, required this.now});

  final Pet pet;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final age = pet.ageLabel(now);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => PetActions.openDetail(context, pet),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 130,
              child: LayoutBuilder(
                builder: (_, c) => PetPhoto.of(pet, size: c.maxWidth, radius: 0),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(pet.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                      if (pet.sex != PetSex.unknown)
                        Text(pet.sex.symbol,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: pet.sex == PetSex.male
                                    ? AppColors.activity
                                    : const Color(0xFFDB2777))),
                    ],
                  ),
                  Text(
                    pet.breed == null
                        ? pet.species.label
                        : '${pet.species.label} · ${pet.breed}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      ?age,
                      if (pet.weightKg != null) Units.kg(pet.weightKg!),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
