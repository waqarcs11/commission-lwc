/**
 * CommissionCalculationService
 * Runs in a before insert/before update context.
 * - When a plan changes: clears all data entry fields not configured for the new plan.
 * - Calculates commission components and writes results directly onto the triggering record.
 */
public with sharing class CommissionCalculationService {

    // All data entry fields that can be cleared on plan change.
    // Calculation output fields and system fields are intentionally excluded.
    private static final Set<String> DATA_ENTRY_FIELDS = new Set<String>{
        'Base_Commission__c',
        'Eligible_Units__c',
        'Funded_Units__c',
        'Termed_Deal_Margin_Amount__c',
        'Termed_Deal_Margin_Percentage__c',
        'Brokered_Margin__c',
        'Brokered_Margin_Amount__c',
        'Team_Closing_Ratio__c',
        'Team_Margin__c',
        'Team_Margin_Amount__c',
        'Day60_Plus_Termed_Margin__c',
        'Day60_Plus_Termed_Margin_Amount__c',
        'Approve_to_Fund_Ratio__c',
        'Proposed_Comp_Margin__c',
        'X50K_Funded__c',
        'X50KPlus_Funded__c',
        'Cardiff_Deal_Margin__c',
        'Cardiff_Deal_Margin_Amount__c',
        'Commission_Adjustment__c',
        'Commission_Adjustment_Note__c'
    };

    public static void process(List<Representative_Commission__c> records,
                               Map<Id, Representative_Commission__c> oldMap) {
        // Load tiers for all plans involved
        Set<String> planNames = new Set<String>();
        Set<Id>     ownerIds  = new Set<Id>();
        for (Representative_Commission__c rec : records) {
            if (String.isNotBlank(rec.Commission_Plan_Developer_Name__c)) {
                planNames.add(rec.Commission_Plan_Developer_Name__c);
            }
            if (rec.OwnerId != null) ownerIds.add(rec.OwnerId);
        }
        if (planNames.isEmpty()) return;

        Map<String, List<Commission_Tier__mdt>> tiersByPlan = loadTiers(planNames);
        Map<String, Set<String>> configuredFieldsByPlan = loadConfiguredFields(planNames);

        // Build owner name map for name auto-generation
        Map<Id, String> ownerNames = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds]) {
            ownerNames.put(u.Id, u.Name);
        }

        for (Representative_Commission__c rec : records) {
            String plan = rec.Commission_Plan_Developer_Name__c;
            if (String.isBlank(plan)) continue;

            // Detect plan change on update
            Boolean planChanged = (oldMap != null)
                && (oldMap.get(rec.Id).Commission_Plan_Developer_Name__c != plan);

            // Clear data entry fields that are NOT configured for the new plan
            if (planChanged) {
                Set<String> keepFields = configuredFieldsByPlan.containsKey(plan)
                    ? configuredFieldsByPlan.get(plan)
                    : new Set<String>();

                for (String fieldName : DATA_ENTRY_FIELDS) {
                    if (!keepFields.contains(fieldName)) {
                        rec.put(fieldName, null);
                    }
                }
                // Reset calculation outputs and status
                clearCalculationFields(rec);
                rec.Status__c = 'Draft';
            }

            // Auto-generate record Name: "Owner Name - Plan Month-Year"
            String ownerName = ownerNames.containsKey(rec.OwnerId)
                ? ownerNames.get(rec.OwnerId) : '';
            String monthYear = String.isNotBlank(rec.Commission_Month_Year__c)
                ? rec.Commission_Month_Year__c : '';
            String baseName = (String.isNotBlank(ownerName) ? ownerName + ' - ' : '')
                + plan
                + (String.isNotBlank(monthYear) ? ' ' + monthYear : '');
            rec.Name = baseName.abbreviate(80);

            // Run calculation and write results directly onto the record
            calculate(rec, tiersByPlan.get(plan));

            // Set status to Calculated unless already Approved
            if (rec.Status__c != 'Approved') {
                rec.Status__c = 'Calculated';
            }
        }
    }

    private static void calculate(Representative_Commission__c rec,
                                   List<Commission_Tier__mdt> tiers) {
        String plan = rec.Commission_Plan_Developer_Name__c;

        // --- Attainment ---
        Decimal attainment = 0;
        if (plan == 'Proposed_Comp') {
            attainment = rec.Approve_to_Fund_Ratio__c != null ? rec.Approve_to_Fund_Ratio__c : 0;
        } else {
            Decimal eligible = rec.Eligible_Units__c != null ? rec.Eligible_Units__c : 0;
            Decimal funded   = rec.Funded_Units__c   != null ? rec.Funded_Units__c   : 0;
            attainment = (eligible > 0) ? (funded / eligible) * 100 : 0;
        }
        rec.Attainment_Calc__c = attainment;

        // --- Tier match ---
        Commission_Tier__mdt matchedTier = findTier(tiers, attainment);
        Decimal tierPayout = 0;
        if (matchedTier != null) {
            rec.Tier_Lower_Calc__c = matchedTier.Lowest_of_Funded_Unit_Against_Eligible__c;
            rec.Tier_Upper_Calc__c = matchedTier.Upper_of_Funded_Units_Against_Eligible__c;
            rec.Tier_Payout_Calc__c = matchedTier.Plan_Tier_Payout__c;
            tierPayout = matchedTier.Plan_Tier_Payout__c != null ? matchedTier.Plan_Tier_Payout__c : 0;
        } else {
            rec.Tier_Lower_Calc__c = null;
            rec.Tier_Upper_Calc__c = null;
            rec.Tier_Payout_Calc__c = 0;
        }

        // --- Commission components ---

        // Brokered: Brokered_Margin_Amount * (Brokered_Margin__c / 100)
        Decimal brokeredComm = 0;
        if (rec.Brokered_Margin_Amount__c != null && rec.Brokered_Margin__c != null) {
            brokeredComm = rec.Brokered_Margin_Amount__c * (rec.Brokered_Margin__c / 100);
        }
        rec.Brokered_Commission_Calc__c = brokeredComm;

        // Team Closing Ratio: >75% = $3000, 70-75% = $1000, else $0
        Decimal teamCloseComm = 0;
        if (rec.Team_Closing_Ratio__c != null) {
            if (rec.Team_Closing_Ratio__c > 75) {
                teamCloseComm = 3000;
            } else if (rec.Team_Closing_Ratio__c >= 70) {
                teamCloseComm = 1000;
            }
        }
        rec.Team_Closing_Ratio_Commission_Calc__c = teamCloseComm;

        // Team Margin: Team_Margin_Amount * (Team_Margin__c / 100)
        Decimal teamMarginComm = 0;
        if (rec.Team_Margin_Amount__c != null && rec.Team_Margin__c != null) {
            teamMarginComm = rec.Team_Margin_Amount__c * (rec.Team_Margin__c / 100);
        }
        rec.Team_Margin_Commission_Calc__c = teamMarginComm;

        // Deal Margin — BPM/Proposed: percent of Base_Commission; BCRR/ARD/Cardiff: flat dollar tier
        Decimal dealMarginComm = 0;
        if ((plan == 'Brokered_PM_Comp' || plan == 'Proposed_Comp') && rec.Base_Commission__c != null) {
            dealMarginComm = rec.Base_Commission__c * (tierPayout / 100);
        } else if (plan == 'Brokered_CRR_Comp'
                || plan == 'Assistant_Renewals_Director_Comp'
                || plan == 'Cardiff_PM_Comp'
                || plan == 'CRF_CRR_Comp') {
            dealMarginComm = tierPayout;
        }
        rec.Deal_Margin_Commission_Calc__c = dealMarginComm;

        // Termed Deal: Termed_Deal_Margin_Amount * (Termed_Deal_Margin_Percentage__c / 100)
        Decimal termedComm = 0;
        if (rec.Termed_Deal_Margin_Amount__c != null && rec.Termed_Deal_Margin_Percentage__c != null) {
            termedComm = rec.Termed_Deal_Margin_Amount__c * (rec.Termed_Deal_Margin_Percentage__c / 100);
        }
        rec.Termed_Deal_Commission_Calc__c = termedComm;

        // Cardiff: Cardiff_Deal_Margin_Amount * (Cardiff_Deal_Margin__c / 100)
        // Cardiff_Deal_Margin__c is a Percent field — stored as e.g. 15 for 15%, so divide by 100
        // Tier payout for Cardiff_PM_Comp is handled in Deal_Margin_Commission_Calc__c
        Decimal cardiffComm = 0;
        if (rec.Cardiff_Deal_Margin_Amount__c != null && rec.Cardiff_Deal_Margin__c != null) {
            cardiffComm = rec.Cardiff_Deal_Margin_Amount__c * (rec.Cardiff_Deal_Margin__c / 100);
        }
        rec.Cardiff_Commission_Calc__c = cardiffComm;

        // 60 Day Termed: Day60_Plus_Termed_Margin_Amount * (Day60_Plus_Termed_Margin__c / 100)
        Decimal day60Comm = 0;
        if (rec.Day60_Plus_Termed_Margin_Amount__c != null && rec.Day60_Plus_Termed_Margin__c != null) {
            day60Comm = rec.Day60_Plus_Termed_Margin_Amount__c * (rec.Day60_Plus_Termed_Margin__c / 100);
        }
        rec.Day60_Termed_Commission_Calc__c = day60Comm;

        // Proposed Comp: Proposed_Comp_Margin * (tier% / 100) + X50K + X50K+
        Decimal proposedComm = 0;
        if (plan == 'Proposed_Comp') {
            if (rec.Proposed_Comp_Margin__c != null) {
                proposedComm = rec.Proposed_Comp_Margin__c * (tierPayout / 100);
            }
            if (rec.X50K_Funded__c != null)     proposedComm += rec.X50K_Funded__c;
            if (rec.X50KPlus_Funded__c != null) proposedComm += rec.X50KPlus_Funded__c;
        }
        rec.Proposed_Comp_Commission_Calc__c = proposedComm;

        // Total and final
        Decimal total = brokeredComm + teamCloseComm + teamMarginComm
                      + dealMarginComm + termedComm + cardiffComm
                      + day60Comm + proposedComm;
        rec.Commission_Amount_Calc__c = total;

        Decimal adjustment = rec.Commission_Adjustment__c != null ? rec.Commission_Adjustment__c : 0;
        rec.Final_Commission_Calc__c = total + adjustment;
    }

    private static void clearCalculationFields(Representative_Commission__c rec) {
        rec.Attainment_Calc__c                    = null;
        rec.Tier_Lower_Calc__c                    = null;
        rec.Tier_Upper_Calc__c                    = null;
        rec.Tier_Payout_Calc__c                   = null;
        rec.Brokered_Commission_Calc__c           = null;
        rec.Team_Closing_Ratio_Commission_Calc__c = null;
        rec.Team_Margin_Commission_Calc__c        = null;
        rec.Deal_Margin_Commission_Calc__c        = null;
        rec.Termed_Deal_Commission_Calc__c        = null;
        rec.Cardiff_Commission_Calc__c            = null;
        rec.Day60_Termed_Commission_Calc__c       = null;
        rec.Proposed_Comp_Commission_Calc__c      = null;
        rec.Commission_Amount_Calc__c             = null;
        rec.Final_Commission_Calc__c              = null;
    }

    private static Commission_Tier__mdt findTier(List<Commission_Tier__mdt> tiers, Decimal attainment) {
        if (tiers == null) return null;
        for (Commission_Tier__mdt tier : tiers) {
            Decimal lower = tier.Lowest_of_Funded_Unit_Against_Eligible__c != null
                ? tier.Lowest_of_Funded_Unit_Against_Eligible__c : 0;
            Decimal upper = tier.Upper_of_Funded_Units_Against_Eligible__c != null
                ? tier.Upper_of_Funded_Units_Against_Eligible__c : 9999;
            if (attainment >= lower && attainment <= upper) return tier;
        }
        return null;
    }

    private static Map<String, List<Commission_Tier__mdt>> loadTiers(Set<String> planNames) {
        Map<String, List<Commission_Tier__mdt>> result = new Map<String, List<Commission_Tier__mdt>>();
        // CMT relationship traversal in WHERE is not supported — fetch all tiers and filter in Apex
        for (Commission_Tier__mdt tier : [
            SELECT Commission_Plan__r.DeveloperName,
                   Lowest_of_Funded_Unit_Against_Eligible__c,
                   Upper_of_Funded_Units_Against_Eligible__c,
                   Plan_Tier_Payout__c,
                   Payout_Type__c
            FROM Commission_Tier__mdt
            ORDER BY Lowest_of_Funded_Unit_Against_Eligible__c
        ]) {
            String planKey = tier.Commission_Plan__r.DeveloperName;
            if (!planNames.contains(planKey)) continue;
            if (!result.containsKey(planKey)) {
                result.put(planKey, new List<Commission_Tier__mdt>());
            }
            result.get(planKey).add(tier);
        }
        return result;
    }

    private static Map<String, Set<String>> loadConfiguredFields(Set<String> planNames) {
        Map<String, Set<String>> result = new Map<String, Set<String>>();
        for (Commission_Plan_Field_Config__c cfg : [
            SELECT Commission_Plan_Developer_Name__c, Field_API_Name__c
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c IN :planNames
        ]) {
            if (!result.containsKey(cfg.Commission_Plan_Developer_Name__c)) {
                result.put(cfg.Commission_Plan_Developer_Name__c, new Set<String>());
            }
            result.get(cfg.Commission_Plan_Developer_Name__c).add(cfg.Field_API_Name__c);
        }
        return result;
    }
}
