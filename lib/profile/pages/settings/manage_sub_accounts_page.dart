import 'package:flutter/material.dart';
import 'package:dentpal/core/models/sub_account_model.dart';
import 'package:dentpal/core/services/sub_account_service.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/app_theme/theme_utils.dart';
import 'package:dentpal/core/widgets/app_page_header.dart';
import 'package:dentpal/core/widgets/skeleton.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:intl/intl.dart';

/// The people who can order on this account's behalf.
///
/// Called "assistants" everywhere the buyer can see, which is what the Profile
/// menu that leads here calls them; "sub account" survives in the model and the
/// service, where it is the stored shape.
class ManageSubAccountsPage extends StatefulWidget {
  const ManageSubAccountsPage({super.key});

  @override
  State<ManageSubAccountsPage> createState() => _ManageSubAccountsPageState();
}

class _ManageSubAccountsPageState extends State<ManageSubAccountsPage> {
  final SubAccountService _subAccountService = SubAccountService();
  List<SubAccount>? _subAccounts;
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadSubAccounts();
  }

  Future<void> _loadSubAccounts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final accounts = await _subAccountService.getSubAccounts();
      if (mounted) {
        setState(() {
          _subAccounts = accounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.d('Error loading sub accounts: $e');
      if (mounted) {
        setState(() {
          // Kept separate from an empty list: "you have none" and "we could not
          // ask" used to look identical here, and only one of them is worth
          // offering a Retry for.
          _error = e;
          _isLoading = false;
        });
      }
    }
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    AppLayout.gutter,
    4,
    AppLayout.gutter,
    28,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadSubAccounts,
                    color: ink.emerald,
                    backgroundColor: ink.surface,
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final count = _subAccounts?.length ?? 0;

    final String subtitle;
    if (_error != null) {
      subtitle = 'Couldn’t load your assistants';
    } else if (_isLoading) {
      subtitle = 'Loading your assistants…';
    } else if (count == 0) {
      subtitle = 'No assistants yet';
    } else {
      subtitle = '$count assistant${count == 1 ? '' : 's'}';
    }

    return AppPageHeader(
      title: 'Assistants',
      subtitle: subtitle,
      subtitleColor: _error != null ? _danger : null,
      // Below ~430px the labelled button and the title fight over the same
      // row, so the action collapses to its icon.
      trailing: _buildAddButton(
        compact: MediaQuery.sizeOf(context).width < 430,
      ),
    );
  }

  Widget _buildAddButton({bool compact = false}) {
    if (compact) {
      return Tooltip(
        message: 'Add assistant',
        child: IconButton(
          onPressed: () => _openEditor(),
          icon: Icon(Icons.person_add_alt, size: 19, color: ink.onEmerald),
          style: IconButton.styleFrom(
            backgroundColor: ink.emerald,
            shape: const CircleBorder(),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ElevatedButton.icon(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.person_add_alt, size: 16),
        label: Text(
          'Add assistant',
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 12.5),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) {
      return const _SubAccountsSkeleton(padding: _listPadding);
    }

    if (_error != null) {
      return _buildStateMessage(
        icon: Icons.cloud_off,
        tone: _danger,
        title: 'Couldn’t load assistants',
        detail: 'Check your connection and try again — nothing has been lost.',
        action: _buildStateAction(
          label: 'Retry',
          icon: Icons.refresh,
          onTap: _loadSubAccounts,
        ),
      );
    }

    final accounts = _subAccounts ?? const <SubAccount>[];

    if (accounts.isEmpty) {
      return _buildStateMessage(
        icon: Icons.people_outline,
        tone: ink.emerald,
        title: 'No assistants yet',
        detail:
            'Add someone from your clinic and they can browse, build a cart '
            'and — if you let them — check out on your account.',
        action: _buildStateAction(
          label: 'Add assistant',
          icon: Icons.person_add_alt,
          onTap: () => _openEditor(),
        ),
      );
    }

    return ListView.builder(
      padding: _listPadding,
      itemCount: accounts.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildSubAccountCard(accounts[index]),
      ),
    );
  }

  Widget _buildSubAccountCard(SubAccount subAccount) {
    final permissions = subAccount.permissions;
    final created = DateFormat('MMM d, yyyy').format(subAccount.dateCreated);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(
                    alpha: ink.isDark ? 0.16 : 0.11,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.person_outline,
                  color: ink.emerald,
                  size: 19,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subAccount.name.isNotEmpty ? subAccount.name : 'Unnamed',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subAccount.email,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Removing used to hide in a three-dot menu next to Edit; Edit
              // has its own button below, so this is all the menu had left.
              Tooltip(
                message: 'Remove assistant',
                child: IconButton(
                  onPressed: () => _showRemoveConfirmation(subAccount),
                  icon: Icon(Icons.person_remove_outlined,
                      size: 19, color: _danger),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: ink.border),
          const SizedBox(height: 12),

          Text(
            'Permissions',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in _permissionSummary(permissions).entries)
                _buildPermissionChip(entry.key, entry.value),
            ],
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 13,
                color: ink.text.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Added $created',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.45),
                    fontSize: 11.5,
                  ),
                ),
              ),
              SizedBox(
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: () => _openEditor(subAccount: subAccount),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: Text(
                    'Edit',
                    style: AppTextStyles.buttonMedium.copyWith(fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink.text,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    side: BorderSide(color: ink.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Label → granted, in the order the editor lists them.
  static Map<String, bool> _permissionSummary(SubAccountPermissions p) => {
    'Sign in': p.canLogin,
    'View cart': p.canViewCart,
    'Edit cart': p.canModifyCart,
    'Checkout': p.canCheckout,
    'Manage assistants': p.canManageSubAccounts,
  };

  /// A granted permission is emerald; a withheld one is simply quiet.
  ///
  /// Both used to be shouted — granted in green, withheld in red — which read
  /// as "five things, two of them broken" rather than "three of five granted".
  Widget _buildPermissionChip(String label, bool granted) {
    final tone = granted ? ink.emerald : ink.text.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: granted
            ? tone.withValues(alpha: ink.isDark ? 0.16 : 0.11)
            : ink.surfaceHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: granted ? tone.withValues(alpha: 0.3) : ink.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            granted ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 12,
            color: tone,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ── States ───────────────────────────────────────────────────────────────

  Widget _buildStateAction({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: AppTextStyles.buttonMedium),
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildStateMessage({
    required IconData icon,
    required Color tone,
    required String title,
    required String detail,
    Widget? action,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          // Always scrollable so the pull-to-refresh above still works when
          // the page has nothing in it to pull.
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 30, color: tone),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _muted,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                    if (action != null) ...[
                      const SizedBox(height: 24),
                      action,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Named routes, so the address bar reads `/profile/sub-accounts/add` or
  /// `/profile/sub-accounts/edit`. The path deliberately carries no id, so
  /// which assistant to edit travels in arguments.
  Future<void> _openEditor({SubAccount? subAccount}) async {
    final navigator = Navigator.of(context);
    final saved = subAccount == null
        ? await navigator.pushNamed('/profile/sub-accounts/add')
        : await navigator.pushNamed(
            '/profile/sub-accounts/edit',
            arguments: subAccount,
          );

    // The editor pops `true` when it wrote something. Reloading regardless
    // would cost a read every time somebody opened the form and backed out.
    if (saved == true && mounted) {
      await _loadSubAccounts();
    }
  }

  Future<void> _showRemoveConfirmation(SubAccount subAccount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.person_remove_outlined, color: _danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Remove assistant?',
                style: TextStyle(color: ink.text),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ink.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 18, color: ink.emerald),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subAccount.name.isNotEmpty
                              ? subAccount.name
                              : 'Unnamed',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: ink.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          subAccount.email,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: _muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'They will no longer be able to sign in to this account. This '
              'cannot be undone.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: _muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _subAccountService.removeSubAccount(subAccount.id);
      if (!mounted) return;
      _showSnack('${subAccount.name} has been removed', ink.emerald);
      await _loadSubAccounts();
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to remove: ${_readableError(e)}', _danger);
      }
    }
  }

  void _showSnack(String message, Color tone) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: tone,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Strips the `Exception: ` the service prefixes onto its thrown messages.
String _readableError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

/// Placeholder cards in the shape the real list settles into, so the page does
/// not jump when the read returns.
class _SubAccountsSkeleton extends StatelessWidget {
  const _SubAccountsSkeleton({this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  /// Enough cards to fill a phone screen; the real list replaces them before a
  /// reader could count.
  static const int _itemCount = 3;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return SkeletonShimmer(
      child: ListView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _itemCount,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ink.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ink.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    SkeletonBox(width: 38, height: 38, radius: 11),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonLine(width: 130, height: 13),
                          SizedBox(height: 6),
                          SkeletonLine(width: 170, height: 11),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 18),
                SkeletonLine(widthFactor: 0.85, height: 22, radius: 11),
                SizedBox(height: 8),
                SkeletonLine(widthFactor: 0.6, height: 22, radius: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Adds an assistant, or edits the two permissions an existing one can be
/// granted.
///
/// This was two near-identical `AlertDialog`s of ~300 lines each, which is also
/// why neither had a URL. One page, [subAccount] null for a new assistant,
/// reached at `/profile/sub-accounts/add` and `/profile/sub-accounts/edit`.
/// Pops `true` when it saved, so the list behind it knows to re-read.
class SubAccountEditorPage extends StatefulWidget {
  const SubAccountEditorPage({super.key, this.subAccount});

  final SubAccount? subAccount;

  @override
  State<SubAccountEditorPage> createState() => _SubAccountEditorPageState();
}

class _SubAccountEditorPageState extends State<SubAccountEditorPage> {
  final SubAccountService _subAccountService = SubAccountService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  late SubAccountPermissions _permissions;
  bool _isSaving = false;
  String? _errorMessage;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  bool get _isEditing => widget.subAccount != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.subAccount;
    if (existing != null) {
      _nameController.text = existing.name;
      _emailController.text = existing.email;
      _permissions = existing.permissions;
    } else {
      _permissions = SubAccountPermissions.defaultPermissions();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  /// A form reads best in a narrower column than a browse grid, so the fields
  /// stop short of the page's full width — but it still centres inside the same
  /// frame every other buyer surface uses.
  static const double _formMaxWidth = 640;

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    AppLayout.gutter,
    4,
    AppLayout.gutter,
    32,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _formMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppPageHeader(
                  title: _isEditing ? 'Edit assistant' : 'New assistant',
                  subtitle: _isEditing
                      ? widget.subAccount!.email
                      : 'Someone who can order on your account',
                ),
                Expanded(child: _buildForm()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: _autovalidateMode,
      child: ListView(
        padding: _listPadding,
        children: [
          if (_errorMessage != null) ...[
            _buildErrorBanner(_errorMessage!),
            const SizedBox(height: 18),
          ],

          _buildSectionHeader('Details'),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _nameController,
            label: 'Name',
            icon: Icons.person_outline,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Name is required'
                : null,
          ),
          const SizedBox(height: 14),
          if (_isEditing)
            // The email is the assistant's sign-in identity, so it is shown
            // rather than offered — changing it would be a different account.
            _buildReadOnlyEmail()
          else
            _buildTextField(
              controller: _emailController,
              label: 'Email address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Email address is required';
                if (!email.contains('@') || !email.contains('.')) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),

          const SizedBox(height: 22),
          _buildSectionHeader('Permissions'),
          const SizedBox(height: 10),
          _buildPermissionToggle(
            icon: Icons.shopping_cart_checkout,
            label: 'Checkout',
            detail: 'Can complete purchases on your account',
            value: _permissions.canCheckout,
            onChanged: (value) => setState(
              () => _permissions = _permissions.copyWith(canCheckout: value),
            ),
          ),
          const SizedBox(height: 10),
          _buildPermissionToggle(
            icon: Icons.manage_accounts_outlined,
            label: 'Manage assistants',
            detail: 'Can add and remove other assistants',
            value: _permissions.canManageSubAccounts,
            onChanged: (value) => setState(
              () => _permissions = _permissions.copyWith(
                canManageSubAccounts: value,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildAlwaysGranted(),

          if (!_isEditing) ...[
            const SizedBox(height: 22),
            _buildInfoBanner(),
          ],

          const SizedBox(height: 24),
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          color: ink.text,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: ink.isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: _danger, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: _danger,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ink.emerald.withValues(alpha: ink.isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink.emerald.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: ink.emerald, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'We’ll email them a link to set their own password — you never '
              'have to hand one over.',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.75),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyEmail() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ink.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.email_outlined,
            size: 19,
            color: ink.text.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email address',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.45),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subAccount!.email,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock_outline,
            size: 15,
            color: ink.text.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionToggle({
    required IconData icon,
    required String label,
    required String detail,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ink.emerald.withValues(
                alpha: value ? (ink.isDark ? 0.16 : 0.11) : 0.06,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              color: ink.emerald.withValues(alpha: value ? 1 : 0.4),
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: _isSaving ? null : onChanged,
            activeThumbColor: ink.onEmerald,
            activeTrackColor: ink.emerald,
          ),
        ],
      ),
    );
  }

  /// The three permissions every assistant has and no form can withhold.
  ///
  /// The list page shows all five, so leaving these off the form made it look
  /// as though two of the five had been lost somewhere.
  Widget _buildAlwaysGranted() {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Always granted',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in const ['Sign in', 'View cart', 'Edit cart'])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ink.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: ink.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 12,
                        color: ink.text.withValues(alpha: 0.45),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ink.text.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          disabledBackgroundColor: ink.emerald.withValues(alpha: 0.5),
          disabledForegroundColor: ink.onEmerald.withValues(alpha: 0.8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isSaving
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ink.onEmerald,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Saving…', style: AppTextStyles.buttonLarge),
                ],
              )
            : Text(
                _isEditing ? 'Save changes' : 'Add assistant',
                style: AppTextStyles.buttonLarge,
              ),
      ),
    );
  }

  /// The one decoration every field on this form wears.
  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
  }) {
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      errorMaxLines: 2,
      errorStyle: AppTextStyles.bodySmall.copyWith(
        color: _danger,
        fontSize: 11.5,
      ),
      prefixIcon: Icon(icon, size: 19, color: ink.emerald),
      border: border(ink.border),
      enabledBorder: border(ink.border),
      focusedBorder: border(ink.emerald, width: 1.5),
      errorBorder: border(_danger),
      focusedErrorBorder: border(_danger, width: 1.5),
      filled: true,
      fillColor: ink.surface,
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: ink.text.withValues(alpha: 0.6),
        fontSize: 14,
      ),
      floatingLabelStyle: AppTextStyles.bodyMedium.copyWith(
        color: ink.emerald,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      enabled: !_isSaving,
      cursorColor: ink.emerald,
      style: AppTextStyles.bodyMedium.copyWith(color: ink.text, fontSize: 14),
      decoration: _fieldDecoration(label: label, icon: icon),
    );
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_autovalidateMode != AutovalidateMode.always) {
      setState(() => _autovalidateMode = AutovalidateMode.always);
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    // Captured before the await: on success this page is popped, so reaching
    // for its Navigator or messenger afterwards would be reaching through a
    // context that is on its way out.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    try {
      if (_isEditing) {
        await _subAccountService.updateSubAccount(
          subAccountId: widget.subAccount!.id,
          name: name,
          permissions: _permissions,
        );
      } else {
        await _subAccountService.createSubAccountStreamlined(
          email: email,
          name: name,
          mainUserPassword: '', // Not used, kept for API compatibility
          permissions: _permissions,
        );
      }

      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Assistant updated'
                : 'Assistant added — we’ve emailed $email a link to set their '
                      'password.',
          ),
          backgroundColor: ink.emerald,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          // Shown in the banner at the top of the form rather than a snackbar:
          // it is usually about a field, and the fields are right here.
          _errorMessage = _readableError(e);
        });
      }
    }
  }
}
