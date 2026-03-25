/**
 * CommissionFieldConfigInstallHandler
 * Runs automatically after package installation.
 * Seeds default Commission_Plan_Field_Config__c records for each plan
 * if no config already exists for that plan (safe to re-run on upgrades).
 */
global class CommissionFieldConfigInstallHandler implements InstallHandler {

    global void onInstall(InstallContext context) {
        seedDefaultConfigs();
    }

    private void seedDefaultConfigs() {
        // Find plans that already have configs so we don't overwrite customer changes
        Set<String> existingPlans = new Set<String>();
        for (Commission_Plan_Field_Config__c cfg : [
            SELECT Commission_Plan_Developer_Name__c FROM Commission_Plan_Field_Config__c
        ]) {
            existingPlans.add(cfg.Commission_Plan_Developer_Name__c);
        }

        List<Commission_Plan_Field_Config__c> toInsert = new List<Commission_Plan_Field_Config__c>();

        if (!existingPlans.contains('Cardiff_PM_Comp')) {
            toInsert.addAll(buildConfigs('Cardiff_PM_Comp', new List<String>{
                'Eligible_Units__c',
                'Funded_Units__c',
                'Cardiff_Deal_Margin__c',
                'Cardiff_Deal_Margin_Amount__c',
                'Brokered_Margin__c',
                'Brokered_Margin_Amount__c',
                'Termed_Deal_Margin_Percentage__c',
                'Termed_Deal_Margin_Amount__c',
                'Commission_Adjustment__c',
                'Commission_Adjustment_Note__c',
                'Attainment_Calc__c',
                'Tier_Lower_Calc__c',
                'Tier_Upper_Calc__c',
                'Tier_Payout_Calc__c',
                'Cardiff_Commission_Calc__c',
                'Brokered_Commission_Calc__c',
                'Termed_Deal_Commission_Calc__c',
                'Commission_Amount_Calc__c',
                'Final_Commission_Calc__c'
            }));
        }

        if (!existingPlans.contains('Brokered_PM_Comp')) {
            toInsert.addAll(buildConfigs('Brokered_PM_Comp', new List<String>{
                'Base_Commission__c',
                'Eligible_Units__c',
                'Funded_Units__c',
                'Termed_Deal_Margin_Percentage__c',
                'Termed_Deal_Margin_Amount__c',
                'Commission_Adjustment__c',
                'Commission_Adjustment_Note__c',
                'Attainment_Calc__c',
                'Tier_Lower_Calc__c',
                'Tier_Upper_Calc__c',
                'Tier_Payout_Calc__c',
                'Deal_Margin_Commission_Calc__c',
                'Termed_Deal_Commission_Calc__c',
                'Commission_Amount_Calc__c',
                'Final_Commission_Calc__c'
            }));
        }

        if (!existingPlans.contains('Brokered_CRR_Comp')) {
            toInsert.addAll(buildConfigs('Brokered_CRR_Comp', new List<String>{
                'Eligible_Units__c',
                'Funded_Units__c',
                'Team_Margin__c',
                'Team_Margin_Amount__c',
                'Day60_Plus_Termed_Margin__c',
                'Day60_Plus_Termed_Margin_Amount__c',
                'Commission_Adjustment_Note__c',
                'Commission_Adjustment__c',
                'Attainment_Calc__c',
                'Tier_Payout_Calc__c',
                'Tier_Lower_Calc__c',
                'Tier_Upper_Calc__c',
                'Team_Margin_Commission_Calc__c',
                'Day60_Termed_Commission_Calc__c',
                'Commission_Amount_Calc__c',
                'Final_Commission_Calc__c'
            }));
        }

        if (!existingPlans.contains('Assistant_Renewals_Director_Comp')) {
            toInsert.addAll(buildConfigs('Assistant_Renewals_Director_Comp', new List<String>{
                'Eligible_Units__c',
                'Funded_Units__c',
                'Brokered_Margin__c',
                'Brokered_Margin_Amount__c',
                'Team_Closing_Ratio__c',
                'Commission_Adjustment__c',
                'Commission_Adjustment_Note__c',
                'Attainment_Calc__c',
                'Tier_Lower_Calc__c',
                'Tier_Upper_Calc__c',
                'Tier_Payout_Calc__c',
                'Brokered_Commission_Calc__c',
                'Team_Closing_Ratio_Commission_Calc__c',
                'Commission_Amount_Calc__c',
                'Final_Commission_Calc__c'
            }));
        }

        if (!existingPlans.contains('CRF_CRR_Comp')) {
            toInsert.addAll(buildConfigs('CRF_CRR_Comp', new List<String>{
                'Eligible_Units__c',
                'Funded_Units__c',
                'Team_Margin__c',
                'Team_Margin_Amount__c',
                'Commission_Adjustment__c',
                'Commission_Adjustment_Note__c',
                'Attainment_Calc__c',
                'Tier_Payout_Calc__c',
                'Tier_Lower_Calc__c',
                'Tier_Upper_Calc__c',
                'Team_Margin_Commission_Calc__c',
                'Commission_Amount_Calc__c',
                'Final_Commission_Calc__c'
            }));
        }

        if (!existingPlans.contains('Proposed_Comp')) {
            toInsert.addAll(buildConfigs('Proposed_Comp', new List<String>{
                'X50K_Funded__c',
                'X50KPlus_Funded__c',
                'Approve_to_Fund_Ratio__c',
                'Base_Commission__c',
                'Attainment_Calc__c',
                'Commission_Amount_Calc__c',
                'Deal_Margin_Commission_Calc__c',
                'Final_Commission_Calc__c',
                'Tier_Lower_Calc__c',
                'Tier_Payout_Calc__c',
                'Tier_Upper_Calc__c'
            }));
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private List<Commission_Plan_Field_Config__c> buildConfigs(String planName, List<String> fields) {
        List<Commission_Plan_Field_Config__c> configs = new List<Commission_Plan_Field_Config__c>();
        Integer sortOrder = 1;
        for (String fieldApi : fields) {
            configs.add(new Commission_Plan_Field_Config__c(
                Name                              = (planName + '_' + fieldApi).abbreviate(80),
                Commission_Plan_Developer_Name__c = planName,
                Field_API_Name__c                 = fieldApi,
                Object_API_Name__c                = 'Representative_Commission__c',
                Sort_Order__c                     = sortOrder++
            ));
        }
        return configs;
    }
}
