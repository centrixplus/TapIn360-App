import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../core/api/api_models.dart';
import '../../core/api/api_outcome.dart';
import '../../core/api/error_codes.dart';
import '../../core/directory/company.dart';
import '../common/tapin_widgets.dart';
import '../settings/logout_flow.dart';

/// "Employee ID" + "PIN / Password" → `POST /login` (AppLogin artboard).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  /// 403 device_not_allowed: show this phone's ID so HR can approve it.
  bool _deviceBlocked = false;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _deviceBlocked = false;
    });
    final outcome = await ref.read(sessionProvider.notifier).login(_login.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _deviceBlocked = outcome is ApiRejected<LoginResult> && outcome.code == ErrorCodes.deviceNotAllowed;
      _error = switch (outcome) {
        ApiOk() => null,
        ApiRejected(:final message, :final status) =>
          message.isNotEmpty ? message : 'login.rejected'.tr(namedArgs: {'status': '$status'}),
        ApiUnreachable() => 'login.unreachable'.tr(),
      };
    });
  }

  Future<void> _changeCompany() async {
    if (!await confirmChangeCompany(context, ref)) return;
    await ref.read(sessionProvider.notifier).changeCompany();
  }

  String? _required(String? value) => (value == null || value.trim().isEmpty) ? 'login.required'.tr() : null;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final arabic = isArabic(context);
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: BottomAnchoredColumn(
            top: [
              _ServerCard(
                company: session.company,
                serverUrl: session.serverUrl ?? '',
                onChange: _changeCompany,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('login.title'.tr(), style: TapInText.title(arabic: arabic)),
                    const SizedBox(height: 6),
                    Text('login.intro'.tr(), style: TapInText.body(arabic: arabic)),
                  ],
                ),
              ),
              if (session.expired) NoticeCard(kind: NoticeKind.warning, title: 'login.expired'.tr()),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldLabel('login.employee_id'.tr()),
                  const SizedBox(height: TapInSpace.s2),
                  TextFormField(
                    key: const Key('login.id'),
                    controller: _login,
                    autocorrect: false,
                    enableSuggestions: false,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    style: TapInText.code.copyWith(fontSize: 18),
                    validator: _required,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldLabel('login.pin'.tr()),
                  const SizedBox(height: TapInSpace.s2),
                  TextFormField(
                    key: const Key('login.pin'),
                    controller: _password,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(fontSize: 18, letterSpacing: 4),
                    onFieldSubmitted: (_) => _submit(),
                    validator: _required,
                    decoration: InputDecoration(
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? 'login.hide_pin'.tr() : 'login.show_pin'.tr(),
                        icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                ],
              ),
              if (_deviceBlocked)
                NoticeCard(
                  kind: NoticeKind.danger,
                  title: 'login.blocked_title'.tr(),
                  body: 'login.blocked_body'.tr(),
                  child: CopyCodeRow(
                    code: ref.read(hardwareIdProvider),
                    copiedMessage: 'common.phone_id_copied'.tr(),
                  ),
                )
              else if (_error != null)
                NoticeCard(kind: NoticeKind.danger, title: _error!),
            ],
            bottom: [
              FilledButton(
                key: const Key('login.submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: TapInColors.surfaceRaised),
                      )
                    : Text('login.submit'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Company (logo, name, code) or the custom server, with **Change**.
class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.company, required this.serverUrl, required this.onChange});

  final Company? company;
  final String serverUrl;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    final company = this.company;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: TapInColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TapInRadius.md),
      ),
      child: Row(
        children: [
          if (company != null)
            CompanyBadge(company: company, size: 36)
          else
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: TapInColors.surface,
                borderRadius: BorderRadius.circular(TapInRadius.sm),
              ),
              child: const Icon(Icons.dns_rounded, size: 20, color: TapInColors.ink),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company?.name ?? 'login.custom_server'.tr(),
                  style: TapInText.bodySmall(
                    arabic: arabic,
                  ).copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  company?.code ?? (Uri.tryParse(serverUrl)?.host ?? serverUrl),
                  style: TapInText.code.copyWith(fontSize: 13, height: 18 / 13),
                  textDirection: TextDirection.ltr,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(key: const Key('login.change'), onPressed: onChange, child: Text('login.change'.tr())),
        ],
      ),
    );
  }
}
