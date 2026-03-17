public with sharing class CommissionPlanAdminController {

    // Returns all Commission Plan custom metadata records
    @AuraEnabled(cacheable=true)
    public static List<Commission_Plan__mdt> getPlans() {
        return [
            SELECT Id, Label, DeveloperName, Payout_Type__c
            FROM Commission_Plan__mdt
            ORDER BY Label
        ];
    }

    // Returns accessible custom fields on Representative_Commission__c
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getAvailableFields() {
        List<FieldInfo> fields = new List<FieldInfo>();
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Representative_Commission__c.fields.getMap();

        for (String apiName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(apiName).getDescribe();
            // Only include accessible custom fields
            if (dfr.isAccessible() && apiName.endsWith('__c')) {
                fields.add(new FieldInfo(apiName, dfr.getLabel()));
            }
        }

        fields.sort();
        return fields;
    }

    // Returns field API names already configured for the given plan
    @AuraEnabled(cacheable=true)
    public static List<String> getConfiguredFields(String planDeveloperName) {
        List<String> configured = new List<String>();
        for (Commission_Plan_Field_Config__c config : [
            SELECT Field_API_Name__c
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = :planDeveloperName
        ]) {
            configured.add(config.Field_API_Name__c);
        }
        return configured;
    }

    // Replaces all config records for the plan with the new field selection
    @AuraEnabled
    public static void saveConfig(String planDeveloperName, List<String> fieldApiNames) {
        // Delete existing config records for this plan
        List<Commission_Plan_Field_Config__c> existing = [
            SELECT Id
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = :planDeveloperName
        ];
        if (!existing.isEmpty()) {
            delete existing;
        }

        // Insert new config records for selected fields
        List<Commission_Plan_Field_Config__c> newConfigs = new List<Commission_Plan_Field_Config__c>();
        for (String apiName : fieldApiNames) {
            newConfigs.add(new Commission_Plan_Field_Config__c(
                Name = (planDeveloperName + '_' + apiName).abbreviate(80),
                Commission_Plan_Developer_Name__c = planDeveloperName,
                Field_API_Name__c = apiName,
                Object_API_Name__c = 'Representative_Commission__c'
            ));
        }
        if (!newConfigs.isEmpty()) {
            insert newConfigs;
        }
    }

    // Wrapper for field descriptor data passed to LWC
    public class FieldInfo implements Comparable {
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String label   { get; set; }

        public FieldInfo(String apiName, String label) {
            this.apiName = apiName;
            this.label   = label;
        }

        public Integer compareTo(Object other) {
            return this.label.compareTo(((FieldInfo) other).label);
        }
    }
}
