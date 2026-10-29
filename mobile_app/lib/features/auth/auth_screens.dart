import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/config.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';

/// The Al Anad mark: copper "C + arrow" on a teal tile (light screens) or white on glass (dark screens).
class BrandMark extends StatelessWidget {
  final double size;
  final bool onDark;
  const BrandMark({super.key, this.size = 64, this.onDark = false});

  @override
  Widget build(BuildContext context) => onDark
      ? Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(size * 0.3),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Image.asset('assets/brand/mark_white.png', fit: BoxFit.contain),
        )
      : ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.3),
          child: Image.asset('assets/brand/mark.png', width: size, height: size, fit: BoxFit.cover),
        );
}

class LanguageToggle extends ConsumerWidget {
  final bool onDark;
  const LanguageToggle({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = context.isAr;
    final color = onDark ? Colors.white : context.scheme.onSurface;
    return TextButton.icon(
      onPressed: () => ref.read(localeProvider.notifier).set(ar ? 'en' : 'ar'),
      icon: Icon(Icons.language_rounded, color: color, size: 20),
      label: Text(ar ? 'English' : 'العربية', style: TextStyle(color: color)),
    );
  }
}

// ==================================================================== welcome

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradient = brandGradient(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Align(alignment: AlignmentDirectional.centerEnd, child: LanguageToggle(onDark: true)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight), child: const Center(child: WelcomeHero())),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: context.scheme.surface, borderRadius: BorderRadius.circular(22)),
                child: const EmailCheckForm(autofocus: false),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The centre of the welcome page: floating preview cards, logo, title and subtitle. Shared by the phone page and the laptop's brand panel.
class WelcomeHero extends ConsumerWidget {
  final bool wide;
  const WelcomeHero({super.key, this.wide = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(sessionProvider).notice;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const _FloatingCards(),
      SizedBox(height: wide ? 48 : 36),
      BrandMark(size: wide ? 88 : 72, onDark: true),
      const SizedBox(height: 22),
      Text(context.t('auth.welcome.title', {'app': AppConfig.productName}), textAlign: TextAlign.center, style: (wide ? context.text.headlineLarge : context.text.headlineMedium)?.copyWith(color: Colors.white)),
      const SizedBox(height: 10),
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Text(context.t('auth.welcome.subtitle'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: wide ? 16.5 : 15, height: 1.5))),
      if (notice == 'expired') ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
          child: Text(context.t('auth.session_expired'), style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
        ),
      ],
    ]);
  }
}

/// Decorative "app preview" cards on the welcome screen.
class _FloatingCards extends StatelessWidget {
  const _FloatingCards();

  @override
  Widget build(BuildContext context) {
    final ar = context.isAr;
    Widget card(IconData icon, Color color, String text, {double dx = 0}) => Transform.translate(
          offset: Offset(dx, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8))]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconBadge(icon, color: color, size: 34),
              const SizedBox(width: 10),
              Text(text, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700)),
            ]),
          ),
        );
    return Column(children: [
      card(Icons.login_rounded, const Color(0xFF10B981), ar ? 'تم تسجيل الحضور 9:00 ص' : 'Checked in · 9:00 AM', dx: -28),
      const SizedBox(height: 12),
      card(Icons.beach_access_rounded, const Color(0xFF00617A), ar ? 'تمت الموافقة على إجازتك' : 'Your leave was approved', dx: 24),
      const SizedBox(height: 12),
      card(Icons.receipt_long_rounded, const Color(0xFFF59E0B), ar ? 'مرتّبك جاهز' : 'Your payslip is ready', dx: -12),
    ]);
  }
}

// ========================================================================= shell

class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBrand;
  const AuthScaffold({super.key, required this.title, this.subtitle, required this.children, this.showBrand = true});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(actions: const [LanguageToggle()]),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (showBrand) const Align(alignment: AlignmentDirectional.centerStart, child: BrandMark(size: 52)),
              const SizedBox(height: 22),
              Text(title, style: context.text.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(subtitle!, style: TextStyle(color: context.colors.subtext, fontSize: 15, height: 1.45)),
              ],
              const SizedBox(height: 28),
              ...children,
            ]),
          ),
        ),
      );
}

// ========================================================================= email

class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: context.t('auth.email.title'),
        subtitle: context.t('auth.email.subtitle'),
        children: const [EmailCheckForm()],
      );
}

/// The first step of signing in, shared by the welcome page (phone + laptop) and the e-mail page: the person types their
/// e-mail or mobile number, the server says who they are and the app shows the next field -
/// first time -> the one-time code from their e-mail (and a new password); already activated -> their password.
class EmailCheckForm extends ConsumerStatefulWidget {
  final bool autofocus;
  /// The laptop's sign-in panel is built ABOVE the app's navigator, where `context.push` cannot find the router: it passes it in.
  final GoRouter? router;
  const EmailCheckForm({super.key, this.autofocus = true, this.router});

  @override
  ConsumerState<EmailCheckForm> createState() => _EmailCheckFormState();
}

class _EmailCheckFormState extends ConsumerState<EmailCheckForm> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim().toLowerCase();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = asMap(await ref.read(apiProvider).post('/auth/employee/check-email', {'email': email}));
      if (!mounted) return;
      final router = widget.router ?? GoRouter.of(context);
      switch (jStr(data, 'status')) {
        case 'hr':
        case 'active':
          router.push('/auth/password', extra: {'email': email, 'hr': jStr(data, 'status') == 'hr'});
        case 'needs_activation':
          router.push('/auth/activate', extra: {'email': email});
        default:
          setState(() => _error = context.t('auth.email.not_found'));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());   // never fail silently
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Form(
          key: _form,
          child: AppField(
            controller: _email,
            label: context.t('auth.identity.label'),
            icon: Icons.alternate_email_rounded,
            keyboard: TextInputType.emailAddress,
            action: TextInputAction.done,
            autofocus: widget.autofocus,
            onSubmitted: (_) => _next(),
            validator: (v) => identityValidator(context, v),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _Notice(_error!, error: true),
        ],
        const SizedBox(height: 20),
        LoadingButton(label: context.t('common.next'), loading: _loading, onPressed: _next),
      ]);
}

class _Notice extends StatelessWidget {
  final String text;
  final bool error;
  const _Notice(this.text, {this.error = false});

  @override
  Widget build(BuildContext context) {
    final c = error ? context.colors.danger : context.colors.info;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(error ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: c, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
    );
  }
}

// ===================================================================== password

class PasswordScreen extends ConsumerStatefulWidget {
  final String email;
  final bool hr;
  const PasswordScreen({super.key, required this.email, this.hr = false});

  @override
  ConsumerState<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends ConsumerState<PasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _hide = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).post('/auth/login', {'email': widget.email, 'password': _password.text});
      await ref.read(sessionProvider.notifier).signIn(data);
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: context.t('auth.password.title'),
        subtitle: context.t('auth.password.subtitle'),
        showBrand: false,
        children: [
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Avatar(name: widget.email, size: 44),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.email, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                if (widget.hr) Padding(padding: const EdgeInsets.only(top: 4), child: Pill(context.t('auth.hr_hint'), icon: Icons.verified_user_rounded)),
              ])),
              TextButton(onPressed: () => context.pop(), child: Text(context.t('common.edit'))),
            ]),
          ),
          const SizedBox(height: 20),
          Form(
            key: _form,
            child: AppField(
              controller: _password,
              label: context.t('auth.password.label'),
              icon: Icons.lock_outline_rounded,
              obscure: _hide,
              autofocus: true,
              action: TextInputAction.done,
              onSubmitted: (_) => _signIn(),
              validator: (v) => (v == null || v.isEmpty) ? context.t('common.required') : null,
              suffix: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 16), _Notice(_error!, error: true)],
          const SizedBox(height: 24),
          LoadingButton(label: context.t('auth.sign_in'), loading: _loading, onPressed: _signIn),
          const SizedBox(height: 8),
          Center(child: TextButton(onPressed: () => context.push('/auth/reset', extra: {'email': widget.email}), child: Text(context.t('auth.forgot')))),
        ],
      );
}

// =================================================================== activation

class ActivateScreen extends ConsumerStatefulWidget {
  final String email;
  const ActivateScreen({super.key, required this.email});

  @override
  ConsumerState<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends ConsumerState<ActivateScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _hide = true;
  bool _loading = false;
  bool _sending = false;
  String? _error;

  /// Ask the server to send a one-time code to this account, by e-mail or SMS (the answer is always the same, whether or not the address exists).
  Future<void> _emailCode({bool sms = false}) async {
    final sent = context.t(sms ? 'auth.reset.sms_sent' : 'auth.reset.email_sent');
    setState(() => _sending = true);
    try {
      await ref.read(apiProvider).post('/auth/employee/forgot-password', {'email': widget.email, if (sms) 'via': 'sms'});
      if (mounted) toast(context, sent);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).post('/auth/employee/activate', {'email': widget.email, 'code': _code.text.trim(), 'password': _password.text});
      await ref.read(sessionProvider.notifier).signIn(data);
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: context.t('auth.activate.title'),
        subtitle: context.t('auth.activate.subtitle'),
        showBrand: false,
        children: [
          OutlinedButton.icon(
            onPressed: _sending ? null : _emailCode,
            icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.mark_email_unread_outlined),
            label: Text(context.t('auth.reset.email_me')),
          ),
          TextButton.icon(
            onPressed: _sending ? null : () => _emailCode(sms: true),
            icon: const Icon(Icons.sms_outlined, size: 18),
            label: Text(context.t('auth.reset.sms_me')),
          ),
          const SizedBox(height: 6),
          Text(context.t('auth.reset.email_hint'), textAlign: TextAlign.center, style: TextStyle(color: context.colors.subtext, fontSize: 12)),
          const SizedBox(height: 18),
          Form(
            key: _form,
            child: Column(children: [
              AppField(
                controller: _code,
                label: context.t('auth.activate.code'),
                icon: Icons.pin_outlined,
                keyboard: TextInputType.number,
                maxLength: 6,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                validator: (v) => (v == null || v.trim().length != 6) ? context.t('common.required') : null,
              ),
              const SizedBox(height: 14),
              AppField(
                controller: _password,
                label: context.t('auth.activate.password'),
                icon: Icons.lock_outline_rounded,
                obscure: _hide,
                validator: (v) => passwordValidator(context, v),
                suffix: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
              ),
              const SizedBox(height: 14),
              AppField(
                controller: _confirm,
                label: context.t('auth.activate.confirm'),
                icon: Icons.lock_reset_rounded,
                obscure: _hide,
                action: TextInputAction.done,
                onSubmitted: (_) => _activate(),
                validator: (v) => v != _password.text ? context.t('auth.password_mismatch') : null,
              ),
            ]),
          ),
          if (_error != null) ...[const SizedBox(height: 16), _Notice(_error!, error: true)],
          const SizedBox(height: 24),
          LoadingButton(label: context.t('auth.activate.button'), loading: _loading, onPressed: _activate),
          const SizedBox(height: 14),
          Text(context.t('auth.activate.no_code'), textAlign: TextAlign.center, style: TextStyle(color: context.colors.subtext)),
        ],
      );
}

// ======================================================================== reset

class ResetScreen extends ConsumerStatefulWidget {
  final String email;
  const ResetScreen({super.key, required this.email});

  @override
  ConsumerState<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends ConsumerState<ResetScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).post('/auth/employee/reset-password', {'email': widget.email, 'code': _code.text.trim(), 'newPassword': _password.text});
      if (!mounted) return;
      toast(context, context.t('auth.reset.done'));
      context.pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: context.t('auth.reset.title'),
        subtitle: context.t('auth.reset.subtitle'),
        showBrand: false,
        children: [
          Form(
            key: _form,
            child: Column(children: [
              AppField(
                controller: _code,
                label: context.t('auth.reset.code'),
                icon: Icons.pin_outlined,
                keyboard: TextInputType.number,
                maxLength: 6,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                validator: (v) => (v == null || v.trim().length != 6) ? context.t('common.required') : null,
              ),
              const SizedBox(height: 14),
              AppField(
                controller: _password,
                label: context.t('auth.reset.new_password'),
                icon: Icons.lock_outline_rounded,
                obscure: _hide,
                action: TextInputAction.done,
                onSubmitted: (_) => _reset(),
                validator: (v) => passwordValidator(context, v),
                suffix: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
              ),
            ]),
          ),
          if (_error != null) ...[const SizedBox(height: 16), _Notice(_error!, error: true)],
          const SizedBox(height: 24),
          LoadingButton(label: context.t('auth.reset.button'), loading: _loading, onPressed: _reset),
        ],
      );
}

// ============================================================== company sign-up

class RegisterCompanyScreen extends ConsumerStatefulWidget {
  const RegisterCompanyScreen({super.key});

  @override
  ConsumerState<RegisterCompanyScreen> createState() => _RegisterCompanyScreenState();
}

class _RegisterCompanyScreenState extends ConsumerState<RegisterCompanyScreen> {
  final _form = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_company, _name, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).post('/companies/register', {
        'companyName': _company.text.trim(),
        'name': _name.text.trim(),
        'email': _email.text.trim().toLowerCase(),
        'password': _password.text,
      });
      await ref.read(sessionProvider.notifier).signIn(data);
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: context.t('auth.company.title'),
        subtitle: context.t('auth.company.subtitle'),
        children: [
          Form(
            key: _form,
            child: Column(children: [
              AppField(controller: _company, label: context.t('auth.company.name'), icon: Icons.business_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
              const SizedBox(height: 14),
              AppField(controller: _name, label: context.t('auth.company.admin_name'), icon: Icons.person_outline_rounded, capitalization: TextCapitalization.words, validator: (v) => requiredValidator(context, v)),
              const SizedBox(height: 14),
              AppField(controller: _email, label: context.t('auth.email.label'), icon: Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress, validator: (v) => emailValidator(context, v)),
              const SizedBox(height: 14),
              AppField(
                controller: _password,
                label: context.t('auth.password.label'),
                icon: Icons.lock_outline_rounded,
                obscure: _hide,
                action: TextInputAction.done,
                onSubmitted: (_) => _create(),
                validator: (v) => passwordValidator(context, v),
                suffix: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
              ),
            ]),
          ),
          if (_error != null) ...[const SizedBox(height: 16), _Notice(_error!, error: true)],
          const SizedBox(height: 24),
          LoadingButton(label: context.t('auth.company.button'), loading: _loading, onPressed: _create),
          const SizedBox(height: 12),
          Text(context.t('auth.company.terms'), textAlign: TextAlign.center, style: TextStyle(color: context.colors.subtext, fontSize: 12)),
        ],
      );
}
