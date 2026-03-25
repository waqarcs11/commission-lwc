@IsTest
private class CommissionFieldConfigInstallHandlerTest {

    @IsTest
    static void testInstall_seedsAllSixPlans() {
        Test.startTest();
        CommissionFieldConfigInstallHandler handler = new CommissionFieldConfigInstallHandler();
        handler.onInstall(null);
        Test.stopTest();

        List<Commission_Plan_Field_Config__c> configs = [
            SELECT Commission_Plan_Developer_Name__c, Field_API_Name__c, Sort_Order__c
            FROM Commission_Plan_Field_Config__c
            ORDER BY Commission_Plan_Developer_Name__c, Sort_Order__c
        ];

        Set<String> plans = new Set<String>();
        for (Commission_Plan_Field_Config__c cfg : configs) {
            plans.add(cfg.Commission_Plan_Developer_Name__c);
        }

        System.assert(plans.contains('Cardiff_PM_Comp'),                   'Cardiff_PM_Comp should be seeded');
        System.assert(plans.contains('Brokered_PM_Comp'),                  'Brokered_PM_Comp should be seeded');
        System.assert(plans.contains('Brokered_CRR_Comp'),                 'Brokered_CRR_Comp should be seeded');
        System.assert(plans.contains('Assistant_Renewals_Director_Comp'),  'Assistant_Renewals_Director_Comp should be seeded');
        System.assert(plans.contains('CRF_CRR_Comp'),                      'CRF_CRR_Comp should be seeded');
        System.assert(plans.contains('Proposed_Comp'),                     'Proposed_Comp should be seeded');
    }

    @IsTest
    static void testInstall_doesNotOverwriteExistingConfigs() {
        // Pre-insert a config for Cardiff_PM_Comp
        insert new Commission_Plan_Field_Config__c(
            Name                              = 'Cardiff_PM_Comp_Existing',
            Commission_Plan_Developer_Name__c = 'Cardiff_PM_Comp',
            Field_API_Name__c                 = 'Eligible_Units__c',
            Object_API_Name__c                = 'Representative_Commission__c',
            Sort_Order__c                     = 1
        );

        Test.startTest();
        CommissionFieldConfigInstallHandler handler = new CommissionFieldConfigInstallHandler();
        handler.onInstall(null);
        Test.stopTest();

        Integer cardiffCount = [
            SELECT COUNT() FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = 'Cardiff_PM_Comp'
        ];

        // Should still be 1 — existing config was not overwritten
        System.assertEquals(1, cardiffCount, 'Existing Cardiff_PM_Comp config should not be overwritten');
    }
}
