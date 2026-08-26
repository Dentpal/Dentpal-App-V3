import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';

/// Predefined list of dental specialties
class DentalSpecialties {
  static const List<String> specialties = [
    '3D Printing in Dentistry',
    'Academic / Teaching Dentistry',
    'Adult Orthodontics',
    'Biological Dentistry',
    'Bone Grafting and Regenerative Surgery',
    'CAD/CAM Dentistry',
    'Clear Aligner Therapy',
    'Clinical Research',
    'Community Dentistry',
    'Corporate Dentistry',
    'Cosmetic / Aesthetic Dentistry',
    'Crown Lengthening',
    'Dental Public Health',
    'Dental Sleep Medicine',
    'Dentistry for Patients with Disabilities',
    'Digital Dentistry',
    'Digital Smile Design',
    'Early / Interceptive Orthodontics',
    'Emergency Dentistry',
    'Endodontics',
    'Epidemiology in Dentistry',
    'Esthetic Dentistry',
    'Fixed Prosthodontics',
    'Full Mouth Rehabilitation',
    'Functional Orthopedics',
    'General Dentistry',
    'Geriatric Dentistry',
    'Gingival Aesthetics',
    'Guided Tissue Regeneration',
    'Gum Disease Treatment',
    'Hard Tissue Surgery',
    'Holistic Dentistry',
    'Hospital Dentistry',
    'Implant Dentistry',
    'Implant Prosthodontics',
    'Integrative Dentistry',
    'Laser Dentistry',
    'Lingual Orthodontics',
    'Maxillofacial Prosthetics',
    'Microscopic Endodontics',
    'Minimally Invasive Dentistry',
    'Mobile Dentistry',
    'Occlusal Rehabilitation',
    'Oral and Maxillofacial Pathology',
    'Oral and Maxillofacial Radiology',
    'Oral and Maxillofacial Surgery',
    'Oral Diagnosis',
    'Oral Implantology',
    'Oral Medicine',
    'Orofacial Pain Management',
    'Orthodontics and Dentofacial Orthopedics',
    'Pediatric Dentistry',
    'Periodontal Surgery',
    'Periodontics',
    'Preventive Dentistry',
    'Private Practice',
    'Prosthodontics',
    'Regenerative Endodontics',
    'Removable Prosthodontics',
    'Restorative Dentistry',
    'Root Canal Treatment',
    'Sinus Lift Surgery',
    'Smile Design',
    'Soft Tissue Surgery',
    'Special Care Dentistry',
    'Surgical Endodontics (Apicoectomy)',
    'Surgical Extractions',
    'TMJ / TMD Disorders',
    'Traditional Orthodontics',
    'Others',
  ];
}

/// Picks the specialties a dentist practises.
///
/// Shared between signup and Edit Profile, so it draws itself from
/// [InkPalette] rather than a fixed palette: on a dark Edit Profile the label
/// and the picker used to render as near-black on near-black.
class SpecialtySelectionWidget extends StatefulWidget {
  final List<String> selectedSpecialties;
  final Function(List<String>) onSelectionChanged;

  const SpecialtySelectionWidget({
    super.key,
    required this.selectedSpecialties,
    required this.onSelectionChanged,
  });

  @override
  State<SpecialtySelectionWidget> createState() =>
      _SpecialtySelectionWidgetState();
}

class _SpecialtySelectionWidgetState extends State<SpecialtySelectionWidget> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customSpecialtyController =
      TextEditingController();
  String _searchQuery = '';
  List<String> _filteredSpecialties = List.from(DentalSpecialties.specialties);

  void _updateFilteredSpecialties() {
    if (_searchQuery.isEmpty) {
      _filteredSpecialties = List.from(DentalSpecialties.specialties);
    } else {
      _filteredSpecialties = DentalSpecialties.specialties
          .where((s) => s.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
  }

  void _toggleSpecialty(String specialty) {
    final List<String> newSelection = List.from(widget.selectedSpecialties);

    if (newSelection.contains(specialty)) {
      newSelection.remove(specialty);
    } else {
      newSelection.add(specialty);
    }

    widget.onSelectionChanged(newSelection);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customSpecialtyController.dispose();
    super.dispose();
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// "3 specialties selected" — the old copy said "3 specialty(s) selected".
  String get _selectionSummary {
    final count = widget.selectedSpecialties.length;
    return '$count ${count == 1 ? 'specialty' : 'specialties'} selected';
  }

  // ── Inline ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasSelection = widget.selectedSpecialties.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Specialty',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Select at least one',
          style: AppTextStyles.bodySmall.copyWith(
            color: ink.text.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),

        // Selection button. Sits on surfaceHigh rather than surface: it is
        // nested inside a card wherever it is used, and matching the card would
        // make it disappear into it.
        Material(
          color: ink.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _showSpecialtyPicker,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasSelection
                      ? ink.emerald.withValues(alpha: 0.45)
                      : ink.border,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.medical_services_outlined,
                      size: 19,
                      color: hasSelection
                          ? ink.emerald
                          : ink.text.withValues(alpha: 0.35),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hasSelection
                            ? _selectionSummary
                            : 'Tap to choose specialties',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: hasSelection
                              ? ink.text
                              : ink.text.withValues(alpha: 0.4),
                          fontWeight: hasSelection
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: ink.text.withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        if (hasSelection) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final specialty in widget.selectedSpecialties)
                _buildChip(specialty),
            ],
          ),
        ],
      ],
    );
  }

  /// One chosen specialty, in the badge shape the rest of the app uses.
  Widget _buildChip(String specialty) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
      decoration: BoxDecoration(
        color: ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ink.emerald.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              specialty,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.emerald,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: () => _toggleSpecialty(specialty),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 13, color: ink.emerald),
            ),
          ),
        ],
      ),
    );
  }

  // ── Picker sheet ─────────────────────────────────────────────────────────

  void _showSpecialtyPicker() {
    // Create a local copy of selected specialties for the modal
    List<String> localSelectedSpecialties = List.from(
      widget.selectedSpecialties,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          void toggleLocalSpecialty(String specialty) {
            if (localSelectedSpecialties.contains(specialty)) {
              localSelectedSpecialties.remove(specialty);
            } else {
              localSelectedSpecialties.add(specialty);
            }
            setModalState(() {});
            // Update parent immediately
            widget.onSelectionChanged(List.from(localSelectedSpecialties));
          }

          final media = MediaQuery.of(context);
          // Sit above the keyboard rather than under it — searching used to
          // push the list and the Done button out of reach.
          final height = math.min(
            media.size.height * 0.8,
            media.size.height - media.viewInsets.bottom - media.padding.top - 8,
          );

          return Padding(
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: ink.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: ink.border),
              ),
              child: Column(
                children: [
                  _buildSheetHeader(
                    count: localSelectedSpecialties.length,
                    onSearch: (value) => setModalState(() {
                      _searchQuery = value;
                      _updateFilteredSpecialties();
                    }),
                  ),
                  Expanded(
                    child: _filteredSpecialties.isEmpty
                        ? _buildNoMatches()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            itemCount: _filteredSpecialties.length,
                            itemBuilder: (context, index) {
                              final specialty = _filteredSpecialties[index];
                              return _buildSpecialtyRow(
                                specialty: specialty,
                                selected: localSelectedSpecialties.contains(
                                  specialty,
                                ),
                                onTap: () => toggleLocalSpecialty(specialty),
                              );
                            },
                          ),
                  ),
                  _buildSheetFooter(
                    onAddCustom: () => _showAddCustomSpecialtyDialog(
                      context,
                      localSelectedSpecialties,
                      (newSpecialty) {
                        if (newSpecialty.isNotEmpty &&
                            !localSelectedSpecialties.contains(newSpecialty)) {
                          localSelectedSpecialties.add(newSpecialty);
                          setModalState(() {});
                          widget.onSelectionChanged(
                            List.from(localSelectedSpecialties),
                          );
                        }
                      },
                    ),
                    onDone: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      // Clear search when modal closes
      _searchController.clear();
      _searchQuery = '';
      _updateFilteredSpecialties();
    });
  }

  Widget _buildSheetHeader({
    required int count,
    required ValueChanged<String> onSearch,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: ink.text.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Specialties',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: ink.emerald.withValues(
                      alpha: ink.isDark ? 0.16 : 0.11,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: ink.emerald.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$count selected',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.emerald,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSearchField(onSearch),
        ],
      ),
    );
  }

  Widget _buildSearchField(ValueChanged<String> onSearch) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ink.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: ink.text.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: onSearch,
              textInputAction: TextInputAction.search,
              style: AppTextStyles.bodyMedium.copyWith(color: ink.text),
              cursorColor: ink.emerald,
              // The global inputDecorationTheme fills and outlines fields; this
              // one draws its own shell, so all of that is switched off.
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search specialties…',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                onSearch('');
              },
              child: Icon(
                Icons.close,
                size: 18,
                color: ink.text.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpecialtyRow({
    required String specialty,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? ink.emerald.withValues(alpha: ink.isDark ? 0.12 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                // A drawn box rather than a Material Checkbox: the stock one
                // takes its unselected colour from the theme, which is still
                // the light one, and vanished on a dark sheet.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected ? ink.emerald : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: selected
                          ? ink.emerald
                          : ink.text.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 14, color: ink.onEmerald)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    specialty,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: selected
                          ? ink.text
                          : ink.text.withValues(alpha: 0.75),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoMatches() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: ink.emerald.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off, size: 30, color: ink.emerald),
            ),
            const SizedBox(height: 20),
            Text(
              'No matches',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nothing in the list matches that. You can add it as a custom '
              'specialty below.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text.withValues(alpha: 0.6),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetFooter({
    required VoidCallback onAddCustom,
    required VoidCallback onDone,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(top: BorderSide(color: ink.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onAddCustom,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                      'Add custom',
                      style: AppTextStyles.buttonMedium.copyWith(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink.text,
                      side: BorderSide(color: ink.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onDone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ink.emerald,
                      foregroundColor: ink.onEmerald,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Done',
                      style: AppTextStyles.buttonMedium.copyWith(fontSize: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Custom specialty ─────────────────────────────────────────────────────

  void _showAddCustomSpecialtyDialog(
    BuildContext parentContext,
    List<String> currentSelections,
    Function(String) onAdd,
  ) {
    _customSpecialtyController.clear();

    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    showDialog(
      context: parentContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: ink.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.add_circle_outline, color: ink.emerald),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add a specialty',
                  style: TextStyle(color: ink.text),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Not in the list? Type it here.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _customSpecialtyController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                cursorColor: ink.emerald,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. Pediatric Oral Surgery',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: ink.surfaceHigh,
                  border: border(ink.border),
                  enabledBorder: border(ink.border),
                  focusedBorder: border(ink.emerald, width: 1.5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: ink.text.withValues(alpha: 0.6)),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final customSpecialty = _customSpecialtyController.text.trim();
                if (customSpecialty.isEmpty) return;

                // Check if specialty already exists (case-insensitive)
                final alreadyExists =
                    currentSelections.any(
                      (s) => s.toLowerCase() == customSpecialty.toLowerCase(),
                    ) ||
                    DentalSpecialties.specialties.any(
                      (s) => s.toLowerCase() == customSpecialty.toLowerCase(),
                    );

                if (alreadyExists) {
                  _showSnack(
                    parentContext,
                    'That specialty is already in the list',
                    ink.amber,
                    onTone: ink.onAmber,
                  );
                  return;
                }

                onAdd(customSpecialty);
                Navigator.pop(dialogContext);
                _showSnack(
                  parentContext,
                  'Added “$customSpecialty”',
                  ink.emerald,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ink.emerald,
                foregroundColor: ink.onEmerald,
                elevation: 0,
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(
    BuildContext context,
    String message,
    Color tone, {
    Color? onTone,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: onTone ?? Colors.white),
        ),
        backgroundColor: tone,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
