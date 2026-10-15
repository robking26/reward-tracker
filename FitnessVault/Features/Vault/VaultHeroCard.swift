import SwiftUI

// MARK: - Vault hero

/// The dashboard's focal point: what's left to unlock this month.
struct VaultHeroCard: View {
    let summary: VaultSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text("\(summary.month.monthName()) vault")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("\(summary.percentUnlocked)% unlocked")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(summary.earned.isPositive ? Palette.accent : Palette.textSecondary)
                    .contentTransition(.numericText(value: Double(summary.percentUnlocked)))
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if summary.isFullyUnlocked {
                    MoneyText(amount: summary.allocation, font: .system(.largeTitle, design: .default), weight: .medium,
                              color: Palette.accent)
                    Text("You've unlocked your full \(summary.allocation.formatted()).")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    MoneyText(amount: summary.remainingToUnlock, font: .system(.largeTitle, design: .default), weight: .medium)
                    Text("left to unlock")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            ThinProgressBar(progress: summary.progress)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Earned")
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                    MoneyText(amount: summary.earned, font: .headline, weight: .semibold, color: Palette.accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Monthly allocation")
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                    MoneyText(amount: summary.allocation, font: .headline, weight: .semibold, color: Palette.textPrimary)
                }
            }
        }
        .surface(radius: Radius.hero, padding: Spacing.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(summary.month.monthName()) vault. \(summary.remainingToUnlock.formatted()) left to unlock. " +
            "Earned \(summary.earned.formatted()) of \(summary.allocation.formatted()), \(summary.percentUnlocked) percent.")
    }
}


struct PayoutStatusLine: View {
    @Environment(AppModel.self) private var model
    var showsChevron = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private var pending: PaymentOrder? { model.payments.first { $0.status.isUnresolved } }

    private var symbol: String { pending?.status.symbol ?? (model.isBankConfigured ? "clock" : "building.columns") }
    private var tint: Color { pending?.status.tint ?? Palette.textSecondary }

    private var message: String {
        if let pending {
            switch pending.status {
            case .awaitingApproval: return "\(pending.amount.formatted()) is awaiting your approval in Starling."
            case .processing: return "\(pending.amount.formatted()) is on its way to Monzo."
            default: return "A \(pending.amount.formatted()) payment needs checking before anything else is sent."
            }
        }
        guard model.isBankConfigured else { return "Connect Starling to start receiving money in Monzo." }
        let time = model.nextSettlement.formatted(date: .omitted, time: .shortened)
        let outstanding = model.flow.earned - model.flow.paid - model.flow.awaitingApproval - model.flow.processing - model.flow.needsChecking
        if outstanding.isPositive {
            return "\(outstanding.nonNegative.formatted()) will be prepared for Monzo at \(time). You'll approve it in Starling."
        }
        return "Next payment to Monzo is prepared at \(time)."
    }
}

