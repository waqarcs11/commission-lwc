@IsTest
private class CommissionEntryControllerTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Commission_Plan_Field_Config__c makeConfig(String planName, String fieldApi) {
        return new Commission_Plan_Field_Config__c(
            Name                              = (planName + '_' + fieldApi).abbreviate(80),
            Commission_Plan_Developer_Name__c = planName,
            Field_API_Name__c                 = fieldApi,
            Sort_Order__c                     = 1
        );
    }

    private static Representative_Commission__c makeRecord(Id ownerId, String plan, Date month) {
        return new Representative_Commission__c(
            OwnerId                           = ownerId,
            Commission_Month__c               = month,
            Commission_Month_Year__c          = 'March 2025',
            Commission_Plan_Developer_Name__c = plan,
            Name                              = (plan + ' 2025-03').abbreviate(80)
        );
    }

    // Creates a System Administrator user with the Commission_Plan_Admin permission set.
    // Used for tests that check FLS-gated field visibility.
    private static User createAdminUserWithPermSet() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            FirstName          = 'Test',
            LastName           = 'CommAdmin',
            Email              = 'commtest@example.com',
            Username           = 'commtest' + String.valueOf(Math.random()).replace('0.','') + '@example.com',
            Alias              = 'ctest',
            TimeZoneSidKey     = 'America/Los_Angeles',
            LocaleSidKey       = 'en_US',
            EmailEncodingKey   = 'UTF-8',
            LanguageLocaleKey  = 'en_US',
            ProfileId          = adminProfile.Id
        );
        insert u;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Commission_Plan_Admin' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        return u;
    }

    // ── getActiveUsers ────────────────────────────────────────────────────────

    @IsTest
    static void testGetActiveUsers_returnsCurrentUser() {
        Test.startTest();
        List<CommissionEntryController.UserOption> users = CommissionEntryController.getActiveUsers();
        Test.stopTest();

        System.assertNotEquals(null, users, 'Should return a non-null list');
        // Running user (Standard type) should be in the list
        Boolean found = false;
        for (CommissionEntryController.UserOption u : users) {
            if (u.id == UserInfo.getUserId()) { found = true; break; }
        }
        System.assert(found, 'Running user should appear in active users list');
    }

    // ── getUsersForPlan ───────────────────────────────────────────────────────

    @IsTest
    static void testGetUsersForPlan_emptyWhenNoneAssigned() {
        Test.startTest();
        List<CommissionEntryController.UserOption> users =
            CommissionEntryController.getUsersForPlan('NONEXISTENT_PLAN_XYZ');
        Test.stopTest();

        System.assertEquals(0, users.size(), 'Should return empty list for unknown plan');
    }

    // ── getCommissionPlans ────────────────────────────────────────────────────

    @IsTest
    static void testGetCommissionPlans_returnsNonNull() {
        Test.startTest();
        List<CommissionEntryController.PlanWrapper> plans = CommissionEntryController.getCommissionPlans();
        Test.stopTest();

        System.assertNotEquals(null, plans, 'Should return a non-null list');
    }

    // ── getFieldsForPlan ──────────────────────────────────────────────────────

    @IsTest
    static void testGetFieldsForPlan_returnsConfiguredFields() {
        insert makeConfig('Test_Plan', 'Eligible_Units__c');
        User adminUser = createAdminUserWithPermSet();

        Test.startTest();
        List<CommissionEntryController.FieldDetail> fields;
        System.runAs(adminUser) {
            fields = CommissionEntryController.getFieldsForPlan('Test_Plan');
        }
        Test.stopTest();

        System.assertEquals(1, fields.size(), 'Should return one configured field');
        System.assertEquals('Eligible_Units__c', fields[0].apiName);
    }

    @IsTest
    static void testGetFieldsForPlan_excludesCalcFields() {
        insert new List<Commission_Plan_Field_Config__c>{
            makeConfig('Test_Plan', 'Eligible_Units__c'),
            makeConfig('Test_Plan', 'Attainment_Calc__c')
        };
        User adminUser = createAdminUserWithPermSet();

        Test.startTest();
        List<CommissionEntryController.FieldDetail> fields;
        System.runAs(adminUser) {
            fields = CommissionEntryController.getFieldsForPlan('Test_Plan');
        }
        Test.stopTest();

        for (CommissionEntryController.FieldDetail f : fields) {
            System.assert(
                !f.apiName.toLowerCase().endsWith('_calc__c'),
                'Calc fields should be excluded: ' + f.apiName
            );
        }
    }

    @IsTest
    static void testGetFieldsForPlan_emptyWhenNoConfig() {
        Test.startTest();
        List<CommissionEntryController.FieldDetail> fields =
            CommissionEntryController.getFieldsForPlan('NO_CONFIG_PLAN');
        Test.stopTest();

        System.assertEquals(0, fields.size(), 'Should return empty list when no config exists');
    }

    // ── getExistingRecord ─────────────────────────────────────────────────────

    @IsTest
    static void testGetExistingRecord_returnsNullWhenNone() {
        insert makeConfig('Test_Plan', 'Eligible_Units__c');
        User adminUser = createAdminUserWithPermSet();

        Test.startTest();
        Representative_Commission__c result;
        System.runAs(adminUser) {
            result = CommissionEntryController.getExistingRecord(
                adminUser.Id, '2025-03-01', 'Test_Plan'
            );
        }
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when no record exists');
    }

    @IsTest
    static void testGetExistingRecord_returnsRecordWhenExists() {
        insert makeConfig('Test_Plan', 'Eligible_Units__c');
        User adminUser = createAdminUserWithPermSet();
        Representative_Commission__c rec = makeRecord(adminUser.Id, 'Test_Plan', Date.newInstance(2025, 3, 1));
        insert rec;

        Test.startTest();
        Representative_Commission__c result;
        System.runAs(adminUser) {
            result = CommissionEntryController.getExistingRecord(
                adminUser.Id, '2025-03-01', 'Test_Plan'
            );
        }
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return existing record');
        System.assertEquals(rec.Id, result.Id);
    }

    // ── saveCommission ────────────────────────────────────────────────────────

    @IsTest
    static void testSaveCommission_createsRecord() {
        insert makeConfig('Test_Plan', 'Eligible_Units__c');

        Test.startTest();
        String recordId = CommissionEntryController.saveCommission(
            UserInfo.getUserId(),
            '2025-03-01',
            'Test_Plan',
            '{"Eligible_Units__c": 10}',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, recordId, 'Should return a record Id');
        Representative_Commission__c saved = [
            SELECT Commission_Plan_Developer_Name__c, Commission_Month__c
            FROM Representative_Commission__c
            WHERE Id = :recordId
        ];
        System.assertEquals('Test_Plan', saved.Commission_Plan_Developer_Name__c);
        System.assertEquals(Date.newInstance(2025, 3, 1), saved.Commission_Month__c);
    }

    @IsTest
    static void testSaveCommission_updatesExistingRecord() {
        insert makeConfig('Test_Plan', 'Eligible_Units__c');
        Representative_Commission__c rec = makeRecord(UserInfo.getUserId(), 'Test_Plan', Date.newInstance(2025, 3, 1));
        insert rec;

        Test.startTest();
        String recordId = CommissionEntryController.saveCommission(
            UserInfo.getUserId(),
            '2025-03-01',
            'Test_Plan',
            '{"Eligible_Units__c": 20}',
            rec.Id
        );
        Test.stopTest();

        System.assertEquals(rec.Id, recordId, 'Should return same record Id on update');
    }

    // ── runForMonth ───────────────────────────────────────────────────────────

    @IsTest
    static void testRunForMonth_createsRecordsForAssignedUsers() {
        // Assign plan to running user
        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        u.Commission_Plan__c = 'Test_Plan';
        update u;

        Test.startTest();
        CommissionEntryController.RunResult result =
            CommissionEntryController.runForMonth('Test_Plan', '2025-04-01');
        Test.stopTest();

        System.assertEquals(1, result.created, 'Should create 1 record');
        System.assertEquals(0, result.skipped, 'Should skip 0 records');
    }

    @IsTest
    static void testRunForMonth_skipsExistingRecords() {
        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        u.Commission_Plan__c = 'Test_Plan';
        update u;

        // Pre-create a record for this month
        insert makeRecord(UserInfo.getUserId(), 'Test_Plan', Date.newInstance(2025, 5, 1));

        Test.startTest();
        CommissionEntryController.RunResult result =
            CommissionEntryController.runForMonth('Test_Plan', '2025-05-01');
        Test.stopTest();

        System.assertEquals(0, result.created, 'Should create 0 — already exists');
        System.assertEquals(1, result.skipped, 'Should skip 1 existing record');
    }

    @IsTest
    static void testRunForMonth_returnsZeroWhenNoUsersOnPlan() {
        Test.startTest();
        CommissionEntryController.RunResult result =
            CommissionEntryController.runForMonth('UNASSIGNED_PLAN', '2025-06-01');
        Test.stopTest();

        System.assertEquals(0, result.created);
        System.assertEquals(0, result.skipped);
    }

    // ── saveUserPlans ─────────────────────────────────────────────────────────

    @IsTest
    static void testSaveUserPlans_assignsPlan() {
        String payload = JSON.serialize(new List<Map<String, String>>{
            new Map<String, String>{
                'userId'            => UserInfo.getUserId(),
                'userName'          => 'Test User',
                'planDeveloperName' => 'Test_Plan'
            }
        });

        Test.startTest();
        String result = CommissionEntryController.saveUserPlans(payload);
        Test.stopTest();

        System.assertEquals('OK:1', result, 'Should return OK:1');
        User updated = [SELECT Commission_Plan__c FROM User WHERE Id = :UserInfo.getUserId()];
        System.assertEquals('Test_Plan', updated.Commission_Plan__c);
    }

    @IsTest
    static void testSaveUserPlans_unassignsPlan() {
        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        u.Commission_Plan__c = 'Test_Plan';
        update u;

        String payload = JSON.serialize(new List<Map<String, String>>{
            new Map<String, String>{
                'userId'            => UserInfo.getUserId(),
                'userName'          => 'Test User',
                'planDeveloperName' => ''
            }
        });

        Test.startTest();
        CommissionEntryController.saveUserPlans(payload);
        Test.stopTest();

        User updated = [SELECT Commission_Plan__c FROM User WHERE Id = :UserInfo.getUserId()];
        System.assertEquals(null, updated.Commission_Plan__c, 'Plan should be cleared');
    }

    @IsTest
    static void testSaveUserPlans_emptyPayload() {
        Test.startTest();
        String result = CommissionEntryController.saveUserPlans('[]');
        Test.stopTest();

        System.assertEquals('OK:0', result);
    }
}
