/**
 * Post-install handler that seeds all commission plans and tiers into
 * Commission_Plan__c and Commission_Tier__c custom objects.
 * Safe to re-run: plans are upserted by DeveloperName__c (external ID),
 * and tiers are deleted and re-inserted per plan.
 *
 * To run manually in Anonymous Apex:
 *   CommissionDataInstallHandler.seedPlansAndTiers();
 */
public class CommissionDataInstallHandler implements InstallHandler {

    public void onInstall(InstallContext ctx) {
        seedPlansAndTiers();
    }

    public static void seedPlansAndTiers() {
        // Upsert plans by DeveloperName__c external ID
        List<Commission_Plan__c> plans = new List<Commission_Plan__c>{
            new Commission_Plan__c(Name = 'Cardiff PM Comp',                  DeveloperName__c = 'Cardiff_PM_Comp',                  Payout_Type__c = 'FlatDollar'),
            new Commission_Plan__c(Name = 'Brokered PM Comp',                 DeveloperName__c = 'Brokered_PM_Comp',                 Payout_Type__c = 'Percentage'),
            new Commission_Plan__c(Name = 'Brokered CRR Comp',                DeveloperName__c = 'Brokered_CRR_Comp',               Payout_Type__c = 'FlatDollar'),
            new Commission_Plan__c(Name = 'Assistant Renewals Director Comp', DeveloperName__c = 'Assistant_Renewals_Director_Comp', Payout_Type__c = 'FlatDollar'),
            new Commission_Plan__c(Name = 'CRF CRR Comp',                     DeveloperName__c = 'CRF_CRR_Comp',                    Payout_Type__c = 'FlatDollar'),
            new Commission_Plan__c(Name = 'Proposed Comp',                    DeveloperName__c = 'Proposed_Comp',                   Payout_Type__c = 'Percentage')
        };
        upsert plans DeveloperName__c;

        // Map DeveloperName__c → Id for tier linking
        Map<String, Id> planIdByDevName = new Map<String, Id>();
        for (Commission_Plan__c p : plans) {
            planIdByDevName.put(p.DeveloperName__c, p.Id);
        }

        // Delete existing tiers for these plans and re-insert
        delete [SELECT Id FROM Commission_Tier__c WHERE Commission_Plan__c IN :planIdByDevName.values()];

        List<Commission_Tier__c> tiers = new List<Commission_Tier__c>();

        // ── Cardiff PM Comp ────────────────────────────────────────────────────
        Id cpmId = planIdByDevName.get('Cardiff_PM_Comp');
        tiers.add(tier(cpmId,  0,    11.99,  0,     'Currency'));
        tiers.add(tier(cpmId, 12,    14.99,  1000,  'Currency'));
        tiers.add(tier(cpmId, 15,    17.99,  2500,  'Currency'));
        tiers.add(tier(cpmId, 22,    24.99,  6500,  'Currency'));
        tiers.add(tier(cpmId, 27,    100,    10000, 'Currency'));

        // ── Brokered PM Comp ───────────────────────────────────────────────────
        Id bpmId = planIdByDevName.get('Brokered_PM_Comp');
        tiers.add(tier(bpmId, 0,     4.99,   0, 'Percent'));
        tiers.add(tier(bpmId, 5,     6.49,   1, 'Percent'));
        tiers.add(tier(bpmId, 6.5,   7.49,   3, 'Percent'));
        tiers.add(tier(bpmId, 7.5,   8.99,   4, 'Percent'));
        tiers.add(tier(bpmId, 9,     100,    5, 'Percent'));

        // ── Brokered CRR Comp ──────────────────────────────────────────────────
        Id bcrrId = planIdByDevName.get('Brokered_CRR_Comp');
        tiers.add(tier(bcrrId,  0,   14.99,  0,    'Currency'));
        tiers.add(tier(bcrrId, 15,   16.99,  2500, 'Currency'));
        tiers.add(tier(bcrrId, 17,   19.99,  3000, 'Currency'));
        tiers.add(tier(bcrrId, 20,   21.99,  4000, 'Currency'));
        tiers.add(tier(bcrrId, 22,   100,    5000, 'Currency'));

        // ── Assistant Renewals Director Comp ───────────────────────────────────
        Id ardId = planIdByDevName.get('Assistant_Renewals_Director_Comp');
        tiers.add(tier(ardId,  0,    7.99,   0,    'Currency'));
        tiers.add(tier(ardId,  8,    9.99,   1000, 'Currency'));
        tiers.add(tier(ardId, 10,   12.99,   1500, 'Currency'));
        tiers.add(tier(ardId, 13,   15.99,   2500, 'Currency'));
        tiers.add(tier(ardId, 16,   19.99,   4000, 'Currency'));
        tiers.add(tier(ardId, 20,   100,     8000, 'Currency'));

        // ── CRF CRR Comp ───────────────────────────────────────────────────────
        Id crfId = planIdByDevName.get('CRF_CRR_Comp');
        tiers.add(tier(crfId,  0,   14.99,  0,    'Currency'));
        tiers.add(tier(crfId, 15,   19.99,  1000, 'Currency'));
        tiers.add(tier(crfId, 20,   24.99,  1500, 'Currency'));
        tiers.add(tier(crfId, 25,   29.99,  2000, 'Currency'));
        tiers.add(tier(crfId, 30,   34.99,  3000, 'Currency'));
        tiers.add(tier(crfId, 35,   100,    4000, 'Currency'));

        // ── Proposed Comp ──────────────────────────────────────────────────────
        Id propId = planIdByDevName.get('Proposed_Comp');
        tiers.add(tier(propId,  0,   16.99,  4,  'Percent'));
        tiers.add(tier(propId, 17,   19.99,  6,  'Percent'));
        tiers.add(tier(propId, 20,   22.49,  7,  'Percent'));
        tiers.add(tier(propId, 22.5, 26.49,  8,  'Percent'));
        tiers.add(tier(propId, 26.5, 33.49, 10,  'Percent'));
        tiers.add(tier(propId, 33.5, 100,   13,  'Percent'));

        insert tiers;
    }

    private static Commission_Tier__c tier(Id planId, Decimal lower, Decimal upper, Decimal payout, String payoutType) {
        return new Commission_Tier__c(
            Commission_Plan__c                        = planId,
            Lowest_of_Funded_Unit_Against_Eligible__c = lower,
            Upper_of_Funded_Units_Against_Eligible__c = upper,
            Plan_Tier_Payout__c                       = payout,
            Payout_Type__c                            = payoutType
        );
    }
}
