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
        List<CommissionPlanAdminController.PlanWrapper> plans = CommissionPlanAdminController.getPlans();
        Test.stopTest();

        // Custom metadata types may or may not exist in the test context.
        // We simply assert the call succeeds and returns a non-null list.
        System.assertNotEquals(null, plans, 'getPlans should return a non-null list');
    }

    // ── getAvailableFields ──────────────────────────────────────────────────────

    @IsTest
    static void testGetAvailableFields_returnsExpectedFields() {
        // Create a test user with the Commission_Plan_Admin permission set
        // so that FLS is granted before calling getAvailableFields()
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User testUser = new User(
            FirstName = 'Test', LastName = 'Admin',
            Email = 'commtest@example.com',
            Username = 'commtest' + System.currentTimeMillis() + '@example.com',
            Alias = 'ctest',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Commission_Plan_Admin' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = ps.Id);

        System.runAs(testUser) {
            Test.startTest();
            List<CommissionPlanAdminController.FieldInfo> fields =
                CommissionPlanAdminController.getAvailableFields();
            Test.stopTest();

            System.assertNotEquals(null, fields, 'getAvailableFields should return a non-null list');
            System.assert(!fields.isEmpty(), 'Expected at least one accessible field on Representative_Commission__c');

            for (CommissionPlanAdminController.FieldInfo fi : fields) {
                System.assertNotEquals(null, fi.apiName, 'apiName should not be null');
                System.assertNotEquals(null, fi.label,   'label should not be null');
                System.assert(fi.apiName.endsWith('__c'), 'Only custom fields should be returned');
            }
        }
    }

    // ── getConfiguredFields ─────────────────────────────────────────────────────

    // Helper — builds a JSON payload for saveConfig
    private static String makeConfigJson(List<String> fieldApiNames) {
        List<String> items = new List<String>();
        for (String f : fieldApiNames) {
            items.add('{"fieldApiName":"' + f + '","usagePeriod":"Monthly","metricType":"","defaultValue":null,"reportSource":"","reportFieldLabel":""}');
        }
        return '[' + String.join(items, ',') + ']';
    }

    @IsTest
    static void testGetConfiguredFields_returnsFieldsForPlan() {
        insert new List<Commission_Plan_Field_Config__c>{
            makeConfig('TestPlan', 'Base_Commission__c'),
            makeConfig('TestPlan', 'Funded_Units__c'),
            makeConfig('OtherPlan', 'Eligible_Units__c')
        };

        Test.startTest();
        List<Commission_Plan_Field_Config__c> result =
            CommissionPlanAdminController.getConfiguredFields('TestPlan');
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should return 2 fields for TestPlan');
        Set<String> names = new Set<String>{ result[0].Field_API_Name__c, result[1].Field_API_Name__c };
        System.assert(names.contains('Base_Commission__c'), 'Should contain Base_Commission__c');
        System.assert(names.contains('Funded_Units__c'),    'Should contain Funded_Units__c');
    }

    @IsTest
    static void testGetConfiguredFields_emptyForUnknownPlan() {
        Test.startTest();
        List<Commission_Plan_Field_Config__c> result =
            CommissionPlanAdminController.getConfiguredFields('NonExistentPlan');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list for unknown plan');
    }

    // ── saveConfig ──────────────────────────────────────────────────────────────

    @IsTest
    static void testSaveConfig_insertsNewRecords() {
        Test.startTest();
        CommissionPlanAdminController.saveConfig(
            'PlanA',
            makeConfigJson(new List<String>{ 'Base_Commission__c', 'Eligible_Units__c' })
        );
        Test.stopTest();

        List<Commission_Plan_Field_Config__c> saved = [
            SELECT Field_API_Name__c, Usage_Period__c
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = 'PlanA'
        ];
        System.assertEquals(2, saved.size(), 'Should have inserted 2 config records');
        System.assertEquals('Monthly', saved[0].Usage_Period__c, 'Default usage period should be Monthly');
    }

    @IsTest
    static void testSaveConfig_replacesExistingRecords() {
        insert makeConfig('PlanB', 'Funded_Units__c');

        Test.startTest();
        CommissionPlanAdminController.saveConfig(
            'PlanB',
            makeConfigJson(new List<String>{ 'Base_Commission__c' })
        );
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
        CommissionPlanAdminController.saveConfig('PlanC', '[]');
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = 'PlanC'
        ];
        System.assertEquals(0, count, 'All records should be deleted when no fields selected');
    }
}
