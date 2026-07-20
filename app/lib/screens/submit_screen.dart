import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key});

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _submitted = false;

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      setState(() => _errorMessage = 'Please enter a URL');
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(
        () => _errorMessage = 'Please enter a valid URL starting with https://',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final title = _titleController.text.trim();
      await supabase.from('submissions').insert({
        'url': url,
        'title': title.isEmpty ? null : title,
      });
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitted = true;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.code == '23505'
            ? 'This URL has already been submitted.'
            : 'Submission failed. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Submission failed. Please try again.';
      });
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    required Color surface,
    required Color border,
    required Color muted,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: muted),
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: kRed),
      ),
      prefixIcon: Icon(icon, color: muted, size: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = textPrimaryOf(context);
    final secondary = textSecondaryOf(context);
    final muted = textMutedOf(context);
    final surface = surfaceOf(context);
    final border = borderOf(context);

    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(
        backgroundColor: bgOf(context),
        title: const Text(
          'SUBMIT A LINK',
          style: TextStyle(fontSize: 11, letterSpacing: 2),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kRed),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _submitted
            ? _buildSuccess(primary, secondary)
            : _buildForm(primary, secondary, muted, surface, border),
      ),
    );
  }

  Widget _buildSuccess(Color primary, Color secondary) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 60),
          const Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Color(0xFF00AA44),
          ),
          const SizedBox(height: 20),
          Text(
            'Link submitted!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thank you for contributing to ShiftFeed.\n'
            'Your submission will be reviewed shortly.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: secondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _submitted = false;
                _urlController.clear();
                _titleController.clear();
              });
            },
            child: const Text('Submit another'),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(
    Color primary,
    Color secondary,
    Color muted,
    Color surface,
    Color border,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoCard(secondary, muted, surface, border),
        const SizedBox(height: 24),
        Text(
          'ARTICLE URL *',
          style: TextStyle(
            fontSize: 10,
            color: muted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _urlController,
          decoration: _fieldDecoration(
            hint: 'https://...',
            icon: Icons.link,
            surface: surface,
            border: border,
            muted: muted,
          ),
          style: TextStyle(color: primary, fontSize: 13),
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        const SizedBox(height: 16),
        Text(
          'TITLE (OPTIONAL)',
          style: TextStyle(
            fontSize: 10,
            color: muted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          decoration: _fieldDecoration(
            hint: 'Article title...',
            icon: Icons.title,
            surface: surface,
            border: border,
            muted: muted,
          ),
          style: TextStyle(color: primary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Text(
          'Adding a title helps reviewers understand the article faster.',
          style: AppTextStyles.caption.copyWith(color: muted),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(fontSize: 13, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: kRed,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Submit for Review',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        _guidelinesCard(secondary, muted, surface, border),
      ],
    );
  }

  Widget _infoCard(
    Color secondary,
    Color muted,
    Color surface,
    Color border,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: muted),
              const SizedBox(width: 8),
              Text(
                'COMMUNITY SUBMISSIONS',
                style: AppTextStyles.sectionLabel.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Found an interesting OpenShift or Kubernetes article not yet in '
            'the feed? Submit it here for review. Good submissions will be '
            'added to ShiftFeed.',
            style: TextStyle(
              fontSize: 13,
              color: secondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _guidelinesCard(
    Color secondary,
    Color muted,
    Color surface,
    Color border,
  ) {
    const guidelines = [
      'Must be related to OpenShift, Kubernetes, or cloud-native tech',
      'Original articles, blog posts, or release announcements',
      'English language content preferred',
      'No spam, paywalled, or promotional content',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SUBMISSION GUIDELINES',
            style: AppTextStyles.sectionLabel.copyWith(color: muted),
          ),
          const SizedBox(height: 12),
          for (final g in guidelines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check,
                      size: 12,
                      color: Color(0xFF00AA44),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      g,
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
