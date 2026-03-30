import 'package:flutter/material.dart';
import 'package:dentpal/core/app_theme/index.dart';

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

class SpecialtySelectionWidget extends StatefulWidget {
  final List<String> selectedSpecialties;
  final Function(List<String>) onSelectionChanged;

  const SpecialtySelectionWidget({
    super.key,
    required this.selectedSpecialties,
    required this.onSelectionChanged,
  });

  @override
  State<SpecialtySelectionWidget> createState() => _SpecialtySelectionWidgetState();
}

class _SpecialtySelectionWidgetState extends State<SpecialtySelectionWidget> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customSpecialtyController = TextEditingController();
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

  void _showAddCustomSpecialtyDialog(BuildContext parentContext, List<String> currentSelections, Function(String) onAdd) {
    _customSpecialtyController.clear();
    
    showDialog(
      context: parentContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.add_circle_outline, color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'Add Custom Specialty',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter a specialty not in the list:',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.grey600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customSpecialtyController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g., Pediatric Oral Surgery',
                  hintStyle: AppTextStyles.inputHint,
                  filled: true,
                  fillColor: AppColors.grey50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.grey300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.grey300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: AppTextStyles.buttonMedium.copyWith(
                  color: AppColors.grey600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final customSpecialty = _customSpecialtyController.text.trim();
                if (customSpecialty.isNotEmpty) {
                  // Check if specialty already exists (case-insensitive)
                  final alreadyExists = currentSelections.any(
                    (s) => s.toLowerCase() == customSpecialty.toLowerCase()
                  ) || DentalSpecialties.specialties.any(
                    (s) => s.toLowerCase() == customSpecialty.toLowerCase()
                  );
                  
                  if (alreadyExists) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text('This specialty already exists'),
                        backgroundColor: AppColors.warning,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } else {
                    onAdd(customSpecialty);
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text('Added "$customSpecialty"'),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showSpecialtyPicker() {
    // Create a local copy of selected specialties for the modal
    List<String> localSelectedSpecialties = List.from(widget.selectedSpecialties);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
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
          
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.grey50,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle bar
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.grey300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Select Specialties',
                            style: AppTextStyles.headlineSmall.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${localSelectedSpecialties.length} selected',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Search field
                      TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setModalState(() {
                            _searchQuery = value;
                            _updateFilteredSpecialties();
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search specialties...',
                          hintStyle: AppTextStyles.inputHint,
                          prefixIcon: const Icon(Icons.search, color: AppColors.grey400),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Specialty list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredSpecialties.length,
                    itemBuilder: (context, index) {
                      final specialty = _filteredSpecialties[index];
                      final isSelected = localSelectedSpecialties.contains(specialty);
                      
                      return ListTile(
                        key: ValueKey(specialty),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: Checkbox(
                          value: isSelected,
                          activeColor: AppColors.primary,
                          onChanged: (value) {
                            toggleLocalSpecialty(specialty);
                          },
                        ),
                        title: Text(
                          specialty,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: isSelected ? AppColors.primary : AppColors.onSurface,
                          ),
                        ),
                        onTap: () {
                          toggleLocalSpecialty(specialty);
                        },
                      );
                    },
                  ),
                ),
                
                // Done button
                Container(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: MediaQuery.of(context).padding.bottom + 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.grey50,
                    border: Border(top: BorderSide(color: AppColors.grey200)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Add Custom Specialty Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _showAddCustomSpecialtyDialog(context, localSelectedSpecialties, (newSpecialty) {
                              if (newSpecialty.isNotEmpty && !localSelectedSpecialties.contains(newSpecialty)) {
                                localSelectedSpecialties.add(newSpecialty);
                                setModalState(() {});
                                widget.onSelectionChanged(List.from(localSelectedSpecialties));
                              }
                            });
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Custom Specialty'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Done Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

  @override
  void dispose() {
    _searchController.dispose();
    _customSpecialtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Specialty',
          style: AppTextStyles.labelLarge.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select at least 1 specialty',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.grey600,
          ),
        ),
        const SizedBox(height: 8),
        
        // Selection button
        GestureDetector(
          onTap: _showSpecialtyPicker,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.selectedSpecialties.isEmpty 
                    ? AppColors.grey200 
                    : AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: widget.selectedSpecialties.isEmpty
                      ? Text(
                          'Tap to select specialties',
                          style: AppTextStyles.inputHint,
                        )
                      : Text(
                          '${widget.selectedSpecialties.length} specialty(s) selected',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: AppColors.grey400,
                ),
              ],
            ),
          ),
        ),
        
        // Selected specialties chips
        if (widget.selectedSpecialties.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selectedSpecialties.map((specialty) {
              return Chip(
                label: Text(
                  specialty,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                deleteIcon: Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.primary,
                ),
                onDeleted: () => _toggleSpecialty(specialty),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
