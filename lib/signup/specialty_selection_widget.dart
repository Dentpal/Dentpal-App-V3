import 'package:flutter/material.dart';
import 'package:dentpal/core/app_theme/index.dart';

/// Predefined list of dental specialties
class DentalSpecialties {
  static const List<String> specialties = [
    // Recognized Dental Specialties (Core)
    'General Dentistry',
    'Prosthodontics',
    'Orthodontics and Dentofacial Orthopedics',
    'Periodontics',
    'Endodontics',
    'Oral and Maxillofacial Surgery',
    'Pediatric Dentistry',
    'Oral and Maxillofacial Pathology',
    'Oral and Maxillofacial Radiology',
    'Dental Public Health',
    
    // Restorative & Aesthetic Dentistry
    'Restorative Dentistry',
    'Cosmetic / Aesthetic Dentistry',
    'Esthetic Dentistry',
    'Smile Design',
    'Full Mouth Rehabilitation',
    'Minimally Invasive Dentistry',
    
    // Surgical & Advanced Procedures
    'Implant Dentistry',
    'Oral Implantology',
    'Bone Grafting and Regenerative Surgery',
    'Sinus Lift Surgery',
    'Surgical Extractions',
    'Soft Tissue Surgery',
    'Hard Tissue Surgery',
    
    // Periodontal Sub-Specialties
    'Periodontal Surgery',
    'Gum Disease Treatment',
    'Gingival Aesthetics',
    'Crown Lengthening',
    'Guided Tissue Regeneration',
    
    // Endodontic Sub-Specialties
    'Root Canal Treatment',
    'Microscopic Endodontics',
    'Surgical Endodontics (Apicoectomy)',
    'Regenerative Endodontics',
    
    // Prosthodontic Sub-Specialties
    'Fixed Prosthodontics',
    'Removable Prosthodontics',
    'Implant Prosthodontics',
    'Maxillofacial Prosthetics',
    'Occlusal Rehabilitation',
    
    // Orthodontic Sub-Specialties
    'Traditional Orthodontics',
    'Clear Aligner Therapy',
    'Lingual Orthodontics',
    'Early / Interceptive Orthodontics',
    'Adult Orthodontics',
    'Functional Orthopedics',
    
    // Pediatric & Special Care
    'Special Care Dentistry',
    'Dentistry for Patients with Disabilities',
    'Geriatric Dentistry',
    
    // Diagnostic & Preventive Dentistry
    'Preventive Dentistry',
    'Oral Diagnosis',
    'Oral Medicine',
    'Dental Sleep Medicine',
    'TMJ / TMD Disorders',
    'Orofacial Pain Management',
    
    // Public Health, Research & Education
    'Community Dentistry',
    'Academic / Teaching Dentistry',
    'Clinical Research',
    'Epidemiology in Dentistry',
    
    // Digital & Modern Dentistry
    'Digital Dentistry',
    'CAD/CAM Dentistry',
    '3D Printing in Dentistry',
    'Digital Smile Design',
    'Laser Dentistry',
    
    // Holistic & Alternative Approaches
    'Holistic Dentistry',
    'Biological Dentistry',
    'Integrative Dentistry',
    
    // Practice Type / Focus
    'Private Practice',
    'Hospital Dentistry',
    'Corporate Dentistry',
    'Mobile Dentistry',
    'Emergency Dentistry',
  ];
}

class SpecialtySelectionWidget extends StatefulWidget {
  final List<String> selectedSpecialties;
  final Function(List<String>) onSelectionChanged;
  final int maxSelections;

  const SpecialtySelectionWidget({
    super.key,
    required this.selectedSpecialties,
    required this.onSelectionChanged,
    this.maxSelections = 5,
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
      if (newSelection.length >= widget.maxSelections) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Maximum ${widget.maxSelections} specialties can be selected'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      newSelection.add(specialty);
    }
    
    widget.onSelectionChanged(newSelection);
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
              if (localSelectedSpecialties.length >= widget.maxSelections) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Maximum ${widget.maxSelections} specialties can be selected'),
                    backgroundColor: AppColors.error,
                    duration: const Duration(seconds: 2),
                  ),
                );
                return;
              }
              localSelectedSpecialties.add(specialty);
            }
            setModalState(() {});
            // Update parent immediately
            widget.onSelectionChanged(List.from(localSelectedSpecialties));
          }
          
          void addLocalCustomSpecialty() {
            final customSpecialty = _customSpecialtyController.text.trim();
            
            if (customSpecialty.isEmpty) {
              return;
            }
            
            if (localSelectedSpecialties.length >= widget.maxSelections) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Maximum ${widget.maxSelections} specialties can be selected'),
                  backgroundColor: AppColors.error,
                  duration: const Duration(seconds: 2),
                ),
              );
              return;
            }
            
            // Check if already exists (case insensitive)
            final exists = localSelectedSpecialties.any(
              (s) => s.toLowerCase() == customSpecialty.toLowerCase()
            ) || DentalSpecialties.specialties.any(
              (s) => s.toLowerCase() == customSpecialty.toLowerCase()
            );
            
            if (exists) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('This specialty already exists'),
                  backgroundColor: AppColors.error,
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }
            
            localSelectedSpecialties.add(customSpecialty);
            setModalState(() {});
            widget.onSelectionChanged(List.from(localSelectedSpecialties));
            _customSpecialtyController.clear();
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added custom specialty: $customSpecialty'),
                backgroundColor: AppColors.success,
                duration: const Duration(seconds: 2),
              ),
            );
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
                            '${localSelectedSpecialties.length}/${widget.maxSelections}',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: localSelectedSpecialties.length >= widget.maxSelections 
                                  ? AppColors.error 
                                  : AppColors.primary,
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
                
                // Custom specialty input
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Can\'t find your specialty?',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.grey600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customSpecialtyController,
                              decoration: InputDecoration(
                                hintText: 'Enter custom specialty',
                                hintStyle: AppTextStyles.inputHint,
                                filled: true,
                                fillColor: AppColors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: addLocalCustomSpecialty,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
          'Select at least 1, up to ${widget.maxSelections} specialties',
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
              final isCustom = !DentalSpecialties.specialties.contains(specialty);
              return Chip(
                label: Text(
                  specialty,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isCustom ? AppColors.accent : AppColors.primary,
                  ),
                ),
                backgroundColor: isCustom 
                    ? AppColors.accent.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.1),
                deleteIcon: Icon(
                  Icons.close,
                  size: 16,
                  color: isCustom ? AppColors.accent : AppColors.primary,
                ),
                onDeleted: () => _toggleSpecialty(specialty),
                side: BorderSide(
                  color: isCustom 
                      ? AppColors.accent.withValues(alpha: 0.3)
                      : AppColors.primary.withValues(alpha: 0.3),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
