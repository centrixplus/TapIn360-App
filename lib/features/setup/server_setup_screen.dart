import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../core/api/server_probe.dart';
import '../../core/config/server_url.dart';
import '../common/tapin_widgets.dart';

/// Company screen → "Use a custom server": the manual Server URL + **Test**
/// (spec §6.1 item 1) for on-premise or other attendance servers.
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  late final _url = TextEditingController(text: ref.read(sessionProvider).serverUrl ?? '');
  ServerProbe? _probe;
  String? _probedUrl;
  String? _inputError;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<ServerProbe?> _test() async {
    final url = normaliseServerUrl(_url.text);
    if (url == null) {
      setState(() => _inputError = 'setup.url_invalid'.tr());
      return null;
    }
    if (isInsecureServerUrl(url)) {
      setState(() {
        _inputError = 'setup.insecure'.tr();
        _probe = null;
      });
      return null;
    }
    setState(() {
      _busy = true;
      _inputError = null;
      _probe = null;
    });
    final probe = await ref.read(apiProvider).probe(url);
    if (!mounted) return probe;
    setState(() {
      _busy = false;
      _probe = probe;
      _probedUrl = url;
      _url.text = url;
    });
    return probe;
  }

  Future<void> _continue() async {
    final url = normaliseServerUrl(_url.text);
    var probe = _probe;
    if (url == null || probe == null || _probedUrl != url) probe = await _test();
    if (probe?.kind != ProbeKind.ok || !mounted) return;
    await ref.read(sessionProvider.notifier).saveServerUrl(_probedUrl!);
  }

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    return Scaffold(
      body: SafeArea(
        child: BottomAnchoredColumn(
          top: [
            BackHeader(title: 'setup.title'.tr()),
            Text('setup.intro'.tr(), style: TapInText.body(arabic: arabic)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldLabel('setup.url_label'.tr()),
                const SizedBox(height: TapInSpace.s2),
                TextField(
                  key: const Key('setup.url'),
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textDirection: TextDirection.ltr,
                  style: TapInText.code,
                  decoration: InputDecoration(
                    hintText: 'setup.url_hint'.tr(),
                    errorText: _inputError,
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() => _probe = null),
                  onSubmitted: (_) => _test(),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_probe != null) _ProbeNotice(probe: _probe!),
          ],
          bottom: [
            FilledButton(
              key: const Key('setup.continue'),
              onPressed: _busy ? null : _continue,
              child: Text('setup.continue'.tr()),
            ),
            OutlinedButton(
              key: const Key('setup.test'),
              onPressed: _busy ? null : _test,
              child: Text('setup.test'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProbeNotice extends StatelessWidget {
  const _ProbeNotice({required this.probe});

  final ServerProbe probe;

  @override
  Widget build(BuildContext context) {
    if (probe.kind == ProbeKind.ok) {
      return TapInCard(
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: TapInColors.successStrong),
            const SizedBox(width: TapInSpace.s2),
            Expanded(
              child: Text(
                'setup.ok'.tr(),
                style: TapInText.body(arabic: isArabic(context)).copyWith(color: TapInColors.successStrong),
              ),
            ),
          ],
        ),
      );
    }
    return NoticeCard(
      kind: NoticeKind.danger,
      title: switch (probe.kind) {
        ProbeKind.notAttendanceServer => 'setup.not_server'.tr(namedArgs: {'status': '${probe.status}'}),
        ProbeKind.redirect => 'setup.redirect'.tr(namedArgs: {'location': probe.location ?? '?'}),
        _ => 'setup.unreachable'.tr(),
      },
    );
  }
}
