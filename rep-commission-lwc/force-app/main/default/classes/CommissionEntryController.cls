public with sharing class CommissionEntryController {

    // Returns all active users for the rep selector dropdown, including their assigned plan
    @AuraEnabled(cacheable=true)
    public static List<UserOption> getActiveUsers() {
        List<UserOption> options = new List<UserOption>();
        for (User u : [
            SELECT Id, Name, Commission_Plan__c
            FROM User
            WHERE IsActive = true
            AND UserType = 'Standard'
            ORDER BY Name
        ]) {
            options.add(new UserOption(u.Id, u.Name, u.Commission_Plan__c));
        }
        return options;
    }

    // Returns active users who have the given plan assigned on their user record
    @AuraEnabled(cacheable=true)
    public static List<UserOption> getUsersForPlan(String planDeveloperName) {
        List<UserOption> options = new List<UserOption>();
        for (User u : [
            SELECT Id, Name, Commission_Plan__c
            FROM User
            WHERE IsActive = true
            AND UserType = 'Standard'
            AND Commission_Plan__c = :planDeveloperName
            ORDER BY Name
        ]) {
            options.add(new UserOption(u.Id, u.Name, u.Commission_Plan__c));
        }
        return options;
    }

    // Creates commission records for all users assigned to the given plan for the given month.
    // Skips users who already have a record for that month and plan.
    // Returns a summary of how many were created vs skipped.
    @AuraEnabled
    public static RunResult runForMonth(String planDeveloperName, String commissionDate) {
        Date monthDate = Date.valueOf(commissionDate);
        String monthYearLabel = DateTime.newInstance(monthDate, Time.newInstance(0,0,0,0))
                                        .format('MMMM yyyy');

        // Find all active users assigned to this plan
        List<User> reps = [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
            AND Commission_Plan__c = :planDeveloperName
        ];

        if (reps.isEmpty()) return new RunResult(0, 0);

        // Find which users already have a record for this month and plan
        Set<Id> existingUserIds = new Set<Id>();
        for (Representative_Commission__c existing : [
            SELECT OwnerId
            FROM Representative_Commission__c
            WHERE Commission_Plan_Developer_Name__c = :planDeveloperName
            AND Commission_Month__c = :monthDate
            AND OwnerId IN :reps
        ]) {
            existingUserIds.add(existing.OwnerId);
        }

        // Create records only for users who don't have one yet
        List<Representative_Commission__c> toInsert = new List<Representative_Commission__c>();
        for (User rep : reps) {
            if (!existingUserIds.contains(rep.Id)) {
                toInsert.add(new Representative_Commission__c(
                    OwnerId                           = rep.Id,
                    Commission_Month__c               = monthDate,
                    Commission_Month_Year__c          = monthYearLabel,
                    Commission_Plan_Developer_Name__c = planDeveloperName,
                    Name = (planDeveloperName + ' ' + commissionDate.substring(0, 7)).abbreviate(80)
                ));
            }
        }

        if (!toInsert.isEmpty()) insert toInsert;

        return new RunResult(toInsert.size(), existingUserIds.size());
    }

    // Returns all commission plans from custom metadata
    @AuraEnabled(cacheable=true)
    public static List<RC_Commission_Plan__mdt> getCommissionPlans() {
        return [
            SELECT Label, DeveloperName, Payout_Type__c
            FROM RC_Commission_Plan__mdt
            ORDER BY Label
        ];
    }

    // Returns field details (apiName, label, type) for DATA ENTRY fields configured on the
    // given plan. Calc fields (_calc__c) are intentionally excluded — they are set by the
    // trigger and should never be entered manually.
    @AuraEnabled(cacheable=true)
    public static List<FieldDetail> getFieldsForPlan(String planDeveloperName) {
        List<FieldDetail> details = new List<FieldDetail>();

        List<Commission_Plan_Field_Config__c> configs = [
            SELECT Field_API_Name__c
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = :planDeveloperName
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];

        if (configs.isEmpty()) return details;

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Representative_Commission__c.fields.getMap();

        for (Commission_Plan_Field_Config__c config : configs) {
            String apiName = config.Field_API_Name__c.toLowerCase();
            // Skip calc fields — they are set by the trigger, not entered manually
            if (apiName.endsWith('_calc__c')) continue;
            if (fieldMap.containsKey(apiName)) {
                Schema.DescribeFieldResult dfr = fieldMap.get(apiName).getDescribe();
                if (dfr.isAccessible()) {
                    details.add(new FieldDetail(
                        dfr.getName(),
                        dfr.getLabel(),
                        dfr.getType().name()
                    ));
                }
            }
        }

        return details;
    }

    // Checks for an existing commission record for the given user, month and plan.
    // Dynamically SELECTs all data-entry fields configured for the plan so that
    // every field is pre-filled correctly when the user opens an existing record.
    @AuraEnabled
    public static Representative_Commission__c getExistingRecord(
        String userId,
        String commissionDate,
        String planDeveloperName
    ) {
        Date monthDate = Date.valueOf(commissionDate);

        // Start with required system fields
        List<String> selectFields = new List<String>{
            'Id', 'Name', 'Commission_Month__c', 'Commission_Plan_Developer_Name__c'
        };

        // Add all data-entry fields configured for this plan (calc fields excluded)
        for (Commission_Plan_Field_Config__c cfg : [
            SELECT Field_API_Name__c
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = :planDeveloperName
            ORDER BY Sort_Order__c ASC NULLS LAST
        ]) {
            if (!cfg.Field_API_Name__c.toLowerCase().endsWith('_calc__c')) {
                selectFields.add(cfg.Field_API_Name__c);
            }
        }

        String soql = 'SELECT ' + String.join(selectFields, ', ')
            + ' FROM Representative_Commission__c'
            + ' WHERE OwnerId = :userId'
            + ' AND Commission_Month__c = :monthDate'
            + ' AND Commission_Plan_Developer_Name__c = :planDeveloperName'
            + ' LIMIT 1';

        List<Representative_Commission__c> records = Database.query(soql);
        return records.isEmpty() ? null : records[0];
    }

    // Creates or updates a Representative_Commission__c record.
    // Pass existingRecordId to update; leave null to create.
    // fieldValuesJson is a JSON object of { "Field_API_Name__c": value, ... }
    @AuraEnabled
    public static String saveCommission(
        String userId,
        String commissionDate,
        String planDeveloperName,
        String fieldValuesJson,
        String existingRecordId
    ) {
        Map<String, Object> fieldValues =
            (Map<String, Object>) JSON.deserializeUntyped(fieldValuesJson);

        Representative_Commission__c record;

        Date monthDate       = Date.valueOf(commissionDate);
        String monthYearLabel = DateTime.newInstance(monthDate, Time.newInstance(0,0,0,0))
                                        .format('MMMM yyyy');   // e.g. "March 2025"

        if (String.isNotBlank(existingRecordId)) {
            // Update path — only change the provided field values
            record = new Representative_Commission__c(
                Id                     = existingRecordId,
                Commission_Month_Year__c = monthYearLabel
            );
        } else {
            // Create path — set owner, month, plan, and auto-generate name
            record = new Representative_Commission__c(
                OwnerId                           = userId,
                Commission_Month__c               = monthDate,
                Commission_Month_Year__c          = monthYearLabel,
                Commission_Plan_Developer_Name__c = planDeveloperName,
                Name = (planDeveloperName + ' ' + commissionDate.substring(0, 7)).abbreviate(80)
            );
        }

        // Dynamically apply the entered field values
        for (String fieldApi : fieldValues.keySet()) {
            Object rawValue = fieldValues.get(fieldApi);
            if (rawValue != null) {
                record.put(fieldApi, Decimal.valueOf(String.valueOf(rawValue)));
            }
        }

        upsert record;
        return record.Id;
    }

    // Accepts a JSON array of { "userId": "...", "planDeveloperName": "..." }.
    // Updates User.Commission_Plan__c for every entry. Uses partial DML so a
    // single failing record does not roll back the rest. Returns a summary of
    // how many succeeded and any error messages for the ones that failed.
    @AuraEnabled
    public static String saveUserPlans(String userPlansJson) {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(userPlansJson);

        // Keep a name map so error messages are readable (not just IDs)
        Map<Id, String> userNames = new Map<Id, String>();
        List<User> toUpdate = new List<User>();

        for (Object item : raw) {
            Map<String, Object> entry = (Map<String, Object>) item;
            String userId   = (String) entry.get('userId');
            String planName = (String) entry.get('planDeveloperName');
            String userName = (String) entry.get('userName');

            userNames.put(userId, userName != null ? userName : userId);
            toUpdate.add(new User(
                Id                 = userId,
                Commission_Plan__c = String.isBlank(planName) ? null : planName
            ));
        }

        if (toUpdate.isEmpty()) return 'OK:0';

        // allOrNone=false — save what we can, collect failures
        List<Database.SaveResult> results = Database.update(toUpdate, false);

        Integer saved = 0;
        List<String> errors = new List<String>();

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                saved++;
            } else {
                String name = userNames.get(toUpdate[i].Id);
                for (Database.Error err : results[i].getErrors()) {
                    errors.add(name + ': ' + err.getMessage());
                }
            }
        }

        if (!errors.isEmpty()) {
            String msg = saved + ' saved. Failures — ' + String.join(errors, ' | ');
            throw new AuraHandledException(msg);
        }

        return 'OK:' + saved;
    }

    // ── Wrapper classes ────────────────────────────────────────────────────────

    public class UserOption {
        @AuraEnabled public String id          { get; set; }
        @AuraEnabled public String name        { get; set; }
        @AuraEnabled public String commissionPlan { get; set; }

        public UserOption(String id, String name, String commissionPlan) {
            this.id             = id;
            this.name           = name;
            this.commissionPlan = commissionPlan;
        }
    }

    public class FieldDetail {
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String label   { get; set; }
        @AuraEnabled public String type    { get; set; }

        public FieldDetail(String apiName, String label, String type) {
            this.apiName = apiName;
            this.label   = label;
            this.type    = type;
        }
    }

    public class RunResult {
        @AuraEnabled public Integer created { get; set; }
        @AuraEnabled public Integer skipped { get; set; }

        public RunResult(Integer created, Integer skipped) {
            this.created = created;
            this.skipped = skipped;
        }
    }
}
