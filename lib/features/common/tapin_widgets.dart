import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/tokens.dart';
import '../../core/directory/company.dart';

bool isArabic(BuildContext context) => context.locale.languageCode == 'ar';

/// White card, radius 20, no shadow.
class TapInCard extends StatelessWidget {
  const TapInCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(TapInSpace.s4),
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: TapInColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TapInRadius.lg),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: child,
    );
  }
}

/// 44 × 44 white square button (history, settings, back).
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: TapInColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TapInRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(TapInRadius.md),
          onTap: onPressed,
          child: SizedBox.square(dimension: 44, child: Icon(icon, size: 22, color: TapInColors.ink)),
        ),
      ),
    );
  }
}

/// Back button + page heading (History, Settings, Custom server).
class BackHeader extends StatelessWidget {
  const BackHeader({super.key, required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SquareIconButton(
          key: const Key('header.back'),
          icon: Icons.chevron_left_rounded,
          tooltip: 'common.back'.tr(),
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: TapInSpace.s2),
        Expanded(
          child: Text(title, style: TapInText.heading(arabic: isArabic(context))),
        ),
      ],
    );
  }
}

/// Field label: uppercase in Latin, sentence case in Arabic.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(isArabic(context) ? text : text.toUpperCase(), style: TapInText.label);
  }
}

/// Rounded status pill (32 px high).
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    required this.icon,
    required this.foreground,
    this.iconColor,
    this.background = TapInColors.surfaceRaised,
    this.onTap,
  });

  final String text;
  final IconData icon;
  final Color foreground;
  final Color? iconColor;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: iconColor ?? foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    style: TapInText.tabular(
                      TapInText.bodySmall(arabic: isArabic(context)).copyWith(color: foreground),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Company logo, or its initials on an `ink` square.
class CompanyBadge extends StatelessWidget {
  const CompanyBadge({super.key, required this.company, this.size = 52});

  final Company company;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size >= 48 ? TapInRadius.md : TapInRadius.sm);
    final initials = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: TapInColors.ink, borderRadius: radius),
      alignment: Alignment.center,
      child: Text(
        company.initials,
        style: TextStyle(
          color: TapInColors.surfaceRaised,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.38,
        ),
      ),
    );
    final logo = company.logoUrl;
    if (logo == null) return initials;
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        logo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => initials,
      ),
    );
  }
}

enum NoticeKind { danger, warning, info }

/// Card with a coloured edge for errors and notices (Login "phone not approved").
class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.kind, required this.title, this.body, this.child});

  final NoticeKind kind;
  final String title;
  final String? body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final (color, icon, background) = switch (kind) {
      NoticeKind.danger => (TapInColors.danger, Icons.close_rounded, TapInColors.surfaceRaised),
      NoticeKind.warning => (TapInColors.warning, Icons.schedule_rounded, TapInColors.warningTint),
      NoticeKind.info => (TapInColors.primaryStrong, Icons.info_outline_rounded, TapInColors.surfaceRaised),
    };
    final arabic = isArabic(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TapInSpace.s4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(TapInRadius.md),
        border: kind == NoticeKind.warning ? null : Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: TapInSpace.s2),
              Expanded(
                child: Text(
                  title,
                  style: TapInText.body(arabic: arabic).copyWith(
                    fontWeight: FontWeight.w600,
                    color: kind == NoticeKind.warning ? TapInColors.ink : color,
                  ),
                ),
              ),
            ],
          ),
          if (body != null) ...[
            const SizedBox(height: 10),
            Text(body!, style: TapInText.bodySmall(arabic: arabic).copyWith(fontSize: 15)),
          ],
          if (child != null) ...[const SizedBox(height: 10), child!],
        ],
      ),
    );
  }
}

/// Phone ID (or any code) in mono with a Copy button.
class CopyCodeRow extends StatelessWidget {
  const CopyCodeRow({super.key, required this.code, this.copiedMessage, this.boxed = true});

  final String code;
  final String? copiedMessage;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: boxed ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10) : EdgeInsets.zero,
            decoration: boxed
                ? BoxDecoration(
                    color: TapInColors.surface,
                    borderRadius: BorderRadius.circular(TapInRadius.sm),
                  )
                : null,
            child: SelectableText(code, style: TapInText.code, textDirection: TextDirection.ltr),
          ),
        ),
        const SizedBox(width: TapInSpace.s2),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(copiedMessage ?? 'common.copied'.tr())));
            }
          },
          child: Text('common.copy'.tr()),
        ),
      ],
    );
  }
}

/// Lays out a screen whose last child sticks to the bottom (buttons) but
/// scrolls when the keyboard needs the room.
class BottomAnchoredColumn extends StatelessWidget {
  const BottomAnchoredColumn({super.key, required this.top, required this.bottom, this.gap = 20});

  final List<Widget> top;
  final List<Widget> bottom;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(TapInSpace.gutter, TapInSpace.s4, TapInSpace.gutter, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 44),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, w) in top.indexed) ...[if (i > 0) SizedBox(height: gap), w],
                const Spacer(),
                SizedBox(height: gap),
                for (final (i, w) in bottom.indexed) ...[if (i > 0) const SizedBox(height: 12), w],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
