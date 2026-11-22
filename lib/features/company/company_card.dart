import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../core/directory/company.dart';
import '../common/tapin_widgets.dart';

/// Logo, name and host of the company found by code; a green tick when it can
/// be used, an amber clock when it cannot (yet).
class CompanyCard extends StatelessWidget {
  const CompanyCard({super.key, required this.company, required this.foundLabel});

  final Company company;
  final String foundLabel;

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    final ok = company.canLogIn;
    return TapInCard(
      child: Row(
        children: [
          CompanyBadge(company: company),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company.name,
                  style: TapInText.body(arabic: arabic).copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  company.host,
                  style: TapInText.bodySmall(arabic: arabic).copyWith(color: TapInColors.inkMuted),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
          Semantics(
            label: ok ? foundLabel : null,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ok ? TapInColors.success : TapInColors.warningTint,
              ),
              child: Icon(
                ok ? Icons.check_rounded : Icons.schedule_rounded,
                size: 18,
                color: ok ? TapInColors.ink : TapInColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
