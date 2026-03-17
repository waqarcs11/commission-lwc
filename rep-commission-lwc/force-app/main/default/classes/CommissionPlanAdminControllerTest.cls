@IsTest
private class CommissionPlanAdminControllerTest {

    // ── Helpers ────────────────────────────────────────────────────────────────

    private static Commission_Plan_Field_Config__c makeConfig(String planName, String fieldApi) {
        return new Commission_Plan_Field_Config__c(
            Name = (planName + '_' + fieldApi).abbreviate(80),
            Commission_Plan_Developer_Name__c = planName,
            Field_API_Name__c = fieldApi,
            Object_API_Name__c = 'Representative_Commission__c'
        );
    }

    // ── getPlans ────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetPlans_returnsList() {
        Test.startTest();
        List<Commission_Plan__mdt> plans = CommissionPlanAdminController.getPlans();
        Test.stopTest();

        // Custom metadata types may or may not exist in the test context.
        // We simply assert the call succeeds and returns a non-null list.
        System.assertNotEquals(null, plans, 'getPlans should return a non-null list');
    }

    // ── getAvailableFields ──────────────────────────────────────────────────────

    @IsTest
    static void testGetAvailableFields_returnsExpectedFields() {
        Test.startTest();
        List<CommissionPlanAdminController.FieldInfo> fields =
            CommissionPlanAdminController.getAvailableFields();
        Test.stopTest();

        System.assertNotEquals(null, fields, 'getAvailableFields should return a non-null list');
        System.assert(!fields.isEmpty(), 'Expected at least one accessible field on Representative_Commission__c');

        // Verify wrapper fields are populated
        for (CommissionPlanAdminController.FieldInfo fi : fields) {
            System.assertNotEquals(null, fi.apiName, 'apiName should not be null');
            System.assertNotEquals(null, fi.label,   'label should not be null');
            System.assert(fi.apiName.endsWith('__c'), 'Only custom fields should be returned');
        }
    }

    // ── getConfiguredFields ─────────────────────────────────────────────────────

    @IsTest
    static void testGetConfiguredFields_returnsFieldsForPlan() {
        insert new List<Commission_Plan_Field_Config__c>{
            makeConfig('TestPlan', 'Base_Commission__c'),
            makeConfig('TestPlan', 'Funded_Units__c'),
            makeConfig('OtherPlan', 'Eligible_Units__c')
        };

        Test.startTest();
        List<String> result = CommissionPlanAdminController.getConfiguredFields('TestPlan');
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should return 2 fields for TestPlan');
        System.assert(result.contains('Base_Commission__c'), 'Should contain Base_Commission__c');
        System.assert(result.contains('Funded_Units__c'),    'Should contain Funded_Units__c');
    }

    @IsTest
    static void testGetConfiguredFields_emptyForUnknownPlan() {
        Test.startTest();
        List<String> result = CommissionPlanAdminController.getConfiguredFields('NonExistentPlan');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list for unknown plan');
    }

    // ── saveConfig ──────────────────────────────────────────────────────────────

    @IsTest
    static void testSaveConfig_insertsNewRecords() {
        List<String> fields = new List<String>{ 'Base_Commission__c', 'Eligible_Units__c' };

        Test.startTest();
        CommissionPlanAdminController.saveConfig('PlanA', fields);
        Test.stopTest();

        List<Commission_Plan_Field_Config__c> saved = [
            SELECT Field_API_Name__c
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = 'PlanA'
        ];
        System.assertEquals(2, saved.size(), 'Should have inserted 2 config records');
    }

    @IsTest
    static void testSaveConfig_replacesExistingRecords() {
        insert makeConfig('PlanB', 'Funded_Units__c');

        Test.startTest();
        CommissionPlanAdminController.saveConfig('PlanB', new List<String>{ 'Base_Commission__c' });
        Test.stopTest();

        List<Commission_Plan_Field_Config__c> saved = [
            SELECT Field_API_Name__c
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = 'PlanB'
        ];
        System.assertEquals(1, saved.size(), 'Old records should be replaced');
        System.assertEquals('Base_Commission__c', saved[0].Field_API_Name__c);
    }

    @IsTest
    static void testSaveConfig_clearAll_deletesRecords() {
        insert makeConfig('PlanC', 'Funded_Units__c');

        Test.startTest();
        CommissionPlanAdminController.saveConfig('PlanC', new List<String>());
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = 'PlanC'
        ];
        System.assertEquals(0, count, 'All records should be deleted when no fields selected');
    }
}
