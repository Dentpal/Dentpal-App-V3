import 'package:flutter/material.dart';

import '../../../core/app_theme/app_text_styles.dart';
import '../../../core/app_theme/ink_palette.dart';
import '../../../core/app_theme/theme_utils.dart';
import '../../../product/widgets/loading_skeletons.dart';

/// A long-form policy document — terms, privacy, anything else the platform
/// publishes as plain text.
///
/// Terms and Privacy were two files that differed only in their title and which
/// service call they made, so the screen itself lives here once and each page
/// supplies its own [loader].
class PolicyDocumentPage extends StatefulWidget {
  const PolicyDocumentPage({
    super.key,
    required this.title,
    required this.icon,
    required this.loader,
    required this.unavailableMessage,
    required this.failureMessage,
    this.summary,
  });

  /// Screen title, e.g. 'Terms & Conditions'.
  final String title;
  final IconData icon;

  /// Fetches the document. Returns null when nothing is published yet.
  final Future<String?> Function() loader;

  /// Shown when [loader] returns null — published nothing, no error.
  final String unavailableMessage;

  /// Shown when [loader] throws.
  final String failureMessage;

  /// One line under the title saying what the document is for.
  final String? summary;

  @override
  State<PolicyDocumentPage> createState() => _PolicyDocumentPageState();
}

class _PolicyDocumentPageState extends State<PolicyDocumentPage> {
  String? _content;
  bool _isLoading = true;
  String? _errorMessage;

  /// A reading column, not a page-wide one: long prose set across a full
  /// desktop window is unreadable.
  static const double _kMaxContentWidth = 760;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final content = await widget.loader();

      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;

          if (content == null || content.trim().isEmpty) {
            _errorMessage = widget.unavailableMessage;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = widget.failureMessage;
        });
      }
    }
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = context.isWideLayout ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(horizontalPadding),
                Expanded(child: _buildBody(horizontalPadding)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double horizontalPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding - 8,
        4,
        horizontalPadding,
        10,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: ink.text),
            tooltip: 'Back',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: AppTextStyles.titleLarge.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                ),
                if (widget.summary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.summary!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.text.withValues(alpha: 0.5),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(widget.icon, size: 19, color: ink.emerald),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(double horizontalPadding) {
    if (_isLoading) {
      return PolicyDocumentSkeleton(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          4,
          horizontalPadding,
          24,
        ),
      );
    }

    if (_errorMessage != null) return _buildErrorState(horizontalPadding);

    return _buildDocument(horizontalPadding);
  }

  Widget _buildDocument(double horizontalPadding) {
    final blocks = parsePolicyDocument(_content ?? '');

    // One selection across the whole document: the old screen used a single
    // SelectableText, and dropping to per-block text would have meant you could
    // no longer drag-select a passage that spans a heading.
    return SelectionArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          4,
          horizontalPadding,
          32,
        ),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
            decoration: BoxDecoration(
              color: ink.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ink.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final block in blocks) _buildBlock(block)],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: ink.text.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Questions about this document? Contact DentPal support.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBlock(PolicyBlock block) {
    switch (block.kind) {
      case PolicyBlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: Text(
            block.text,
            style: AppTextStyles.titleMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              height: 1.3,
            ),
          ),
        );
      case PolicyBlockKind.subheading:
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(
            block.text,
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              height: 1.35,
            ),
          ),
        );
      case PolicyBlockKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 8, right: 10),
                decoration: BoxDecoration(
                  color: ink.emerald,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  block.text,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        );
      case PolicyBlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            block.text,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.85),
              fontSize: 13.5,
              height: 1.65,
            ),
          ),
        );
    }
  }

  Widget _buildErrorState(double horizontalPadding) {
    final unavailable = _errorMessage == widget.unavailableMessage;
    final tone = unavailable ? ink.amber : ink.text.withValues(alpha: 0.5);

    return ListView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 60, horizontalPadding, 24),
      children: [
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              unavailable ? Icons.description_outlined : Icons.cloud_off,
              size: 30,
              color: tone,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          unavailable ? 'Not published yet' : 'Couldn’t load the document',
          textAlign: TextAlign.center,
          style: AppTextStyles.titleMedium.copyWith(
            color: ink.text,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage!,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: _muted,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('Try again', style: AppTextStyles.buttonMedium),
              style: ElevatedButton.styleFrom(
                backgroundColor: ink.emerald,
                foregroundColor: ink.onEmerald,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The shapes a policy document is rendered in.
enum PolicyBlockKind { heading, subheading, bullet, paragraph }

class PolicyBlock {
  const PolicyBlock(this.kind, this.text);

  final PolicyBlockKind kind;
  final String text;
}

/// Splits a plain-text policy into headings, bullets and paragraphs.
///
/// The documents are authored as `text/plain` in the admin dashboard, so there
/// is no markup to trust. Only unambiguous markers are honoured — a `#` prefix,
/// a bullet character, or a short ALL-CAPS line, which in a legal document is
/// always a section title. Anything else stays a paragraph, so prose can never
/// be mangled into a heading.
List<PolicyBlock> parsePolicyDocument(String raw) {
  final blocks = <PolicyBlock>[];
  final paragraph = <String>[];

  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(PolicyBlock(PolicyBlockKind.paragraph, paragraph.join('\n')));
    paragraph.clear();
  }

  for (final line in raw.replaceAll('\r\n', '\n').split('\n')) {
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      flush();
      continue;
    }

    if (trimmed.startsWith('###')) {
      flush();
      blocks.add(
        PolicyBlock(
          PolicyBlockKind.subheading,
          trimmed.replaceFirst(RegExp(r'^#+\s*'), ''),
        ),
      );
      continue;
    }

    if (trimmed.startsWith('#')) {
      flush();
      final text = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
      blocks.add(
        PolicyBlock(
          trimmed.startsWith('##')
              ? PolicyBlockKind.subheading
              : PolicyBlockKind.heading,
          text,
        ),
      );
      continue;
    }

    if (RegExp(r'^[-•*]\s+').hasMatch(trimmed)) {
      flush();
      blocks.add(
        PolicyBlock(
          PolicyBlockKind.bullet,
          trimmed.replaceFirst(RegExp(r'^[-•*]\s+'), ''),
        ),
      );
      continue;
    }

    if (_looksLikeSectionTitle(trimmed)) {
      flush();
      blocks.add(PolicyBlock(PolicyBlockKind.heading, trimmed));
      continue;
    }

    paragraph.add(trimmed);
  }

  flush();
  return blocks;
}

/// An ALL-CAPS line short enough to be a title, e.g. "1. ACCEPTANCE OF TERMS".
bool _looksLikeSectionTitle(String line) {
  if (line.length > 70) return false;
  if (!RegExp(r'[A-Za-z]').hasMatch(line)) return false;
  if (line.endsWith('.') || line.endsWith(',') || line.endsWith(';')) {
    return false;
  }
  return line == line.toUpperCase();
}
