import 'package:flutter/material.dart';
import '../models/shipping_address.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

class AddressCard extends StatelessWidget {
  final ShippingAddress address;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onSetDefault;
  final bool showActions;
  final bool isSelected;

  const AddressCard({
    super.key,
    required this.address,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onSetDefault,
    this.showActions = true,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: isSelected
            ? Border.all(color: AppColors.primary, width: 2)
            : address.isDefault
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with name, default badge, and actions
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            address.fullName,
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (address.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'DEFAULT',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.onPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'SELECTED',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.onPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showActions)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              onEdit?.call();
                              break;
                            case 'default':
                              onSetDefault?.call();
                              break;
                            case 'delete':
                              onDelete?.call();
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          if (!address.isDefault)
                            const PopupMenuItem(
                              value: 'default',
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline, size: 18),
                                  SizedBox(width: 8),
                                  Text('Set as Default'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                        child: Icon(
                          Icons.more_vert,
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Address details
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address.addressLine1,
                      style: AppTextStyles.bodyMedium,
                    ),
                    if (address.addressLine2 != null && address.addressLine2!.isNotEmpty)
                      Text(
                        address.addressLine2!,
                        style: AppTextStyles.bodyMedium,
                      ),
                    Text(
                      '${address.city}, ${address.state} ${address.postalCode}',
                      style: AppTextStyles.bodyMedium,
                    ),
                    Text(
                      address.country,
                      style: AppTextStyles.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 16,
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          address.phoneNumber,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddressListTile extends StatelessWidget {
  final ShippingAddress address;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool showRadio;

  const AddressListTile({
    super.key,
    required this.address,
    this.onTap,
    this.isSelected = false,
    this.showRadio = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: AppColors.primary, width: 2)
            : Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: showRadio
            ? Radio<bool>(
                value: true,
                groupValue: isSelected,
                onChanged: (_) => onTap?.call(),
                activeColor: AppColors.primary,
              )
            : null,
        title: Row(
          children: [
            Text(
              address.fullName,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (address.isDefault) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'DEFAULT',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          address.singleLineAddress,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.7),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isSelected
            ? Icon(
                Icons.check_circle,
                color: AppColors.primary,
              )
            : null,
      ),
    );
  }
}

class EmptyAddressState extends StatelessWidget {
  final VoidCallback? onAddAddress;
  final String title;
  final String subtitle;

  const EmptyAddressState({
    super.key,
    this.onAddAddress,
    this.title = 'No addresses yet',
    this.subtitle = 'Add your first shipping address to get started',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 64,
              color: AppColors.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            if (onAddAddress != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAddAddress,
                icon: const Icon(Icons.add),
                label: const Text('Add Address'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
