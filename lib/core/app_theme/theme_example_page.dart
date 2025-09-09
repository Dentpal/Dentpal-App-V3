import 'package:flutter/material.dart';
import 'package:dentpal/core/app_theme/index.dart';

/// Example page showing how to use the new DentPal theme system
class ThemeExamplePage extends StatelessWidget {
  const ThemeExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DentPal Theme Example'),
      ),
      body: SingleChildScrollView(
        padding: context.paddingAll16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Typography Examples
            Text(
              'Typography Examples',
              style: context.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            
            Text(
              'Headline Large',
              style: AppTextStyles.headlineLarge,
            ),
            Text(
              'Title Medium',
              style: AppTextStyles.titleMedium,
            ),
            Text(
              'Body Large - This is body text that demonstrates the Poppins font family with proper line spacing and readability.',
              style: AppTextStyles.bodyLarge,
            ),
            Text(
              'Body Small - Smaller text for secondary information',
              style: AppTextStyles.bodySmall,
            ),
            
            const SizedBox(height: 32),
            
            // Color Examples
            Text(
              'Color Palette',
              style: context.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ColorSwatch('Primary', AppColors.primary),
                _ColorSwatch('Secondary', AppColors.secondary),
                _ColorSwatch('Accent', AppColors.accent),
                _ColorSwatch('Success', AppColors.success),
                _ColorSwatch('Warning', AppColors.warning),
                _ColorSwatch('Error', AppColors.error),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // Button Examples
            Text(
              'Button Styles',
              style: context.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Elevated Button'),
                ),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Outlined Button'),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('Text Button'),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // Gradient Examples
            Text(
              'Gradient Examples',
              style: context.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            
            Column(
              children: [
                Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: AppGradients.primary,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: const Center(
                    child: Text(
                      'Primary Gradient',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: AppGradients.teal,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: const Center(
                    child: Text(
                      'Teal Gradient',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // Card Example
            Text(
              'Card Example',
              style: context.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            
            Card(
              child: Padding(
                padding: context.paddingAll16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Example Card',
                      style: AppTextStyles.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This card demonstrates the default card styling with proper shadows, colors, and border radius.',
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Input Field Example
            Text(
              'Input Field Example',
              style: context.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            
            const TextField(
              decoration: InputDecoration(
                labelText: 'Email Address',
                hintText: 'Enter your email',
                prefixIcon: Icon(Icons.email),
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final String name;
  final Color color;
  
  const _ColorSwatch(this.name, this.color);
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: AppShadows.light,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: AppTextStyles.labelSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
