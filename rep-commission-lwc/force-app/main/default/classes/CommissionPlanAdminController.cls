public with sharing class CommissionPlanAdminController {

    // Returns all Commission Plan custom metadata records
    @AuraEnabled(cacheable=true)
    public static List<RC_Commission_Plan__mdt> getPlans() {
        return [
            SELECT Id, Label, DeveloperName, Payout_Type__c
            FROM RC_Commission_Plan__mdt
            ORDER BY Label
        ];
    }

    // System/tracking fields excluded from admin config (in addition to any *_calc__c fields)
    private static final Set<String> SYSTEM_FIELDS = new Set<String>{
        'commission_month__c', 'commission_month_year__c',
        'commission_plan_developer_name__c', 'status__c'
    };

    // Returns accessible data-entry custom fields on Representative_Commission__c.
    // Calc output fields are excluded automatically via the _calc__c suffix convention.
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getAvailableFields() {
        List<FieldInfo> fields = new List<FieldInfo>();
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Representative_Commission__c.fields.getMap();

        for (String apiName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(apiName).getDescribe();
            // Exclude: non-custom, inaccessible, and system fields
            // Calc fields (_calc__c) are included so admins can choose which ones to show
            if (dfr.isAccessible()
                    && apiName.endsWith('__c')
                    && !SYSTEM_FIELDS.contains(apiName)) {
                fields.add(new FieldInfo(dfr.getName(), dfr.getLabel(), apiName.endsWith('_calc__c')));
            }
        }

        fields.sort();
        return fields;
    }

    // Returns field API names already configured for the given plan, in display order
    @AuraEnabled(cacheable=true)
    public static List<String> getConfiguredFields(String planDeveloperName) {
        List<String> configured = new List<String>();
        for (Commission_Plan_Field_Config__c config : [
            SELECT Field_API_Name__c
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = :planDeveloperName
            ORDER BY Sort_Order__c ASC NULLS LAST
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

        // Insert new config records for selected fields, preserving the passed-in order
        List<Commission_Plan_Field_Config__c> newConfigs = new List<Commission_Plan_Field_Config__c>();
        for (Integer i = 0; i < fieldApiNames.size(); i++) {
            String apiName = fieldApiNames[i];
            newConfigs.add(new Commission_Plan_Field_Config__c(
                Name = (planDeveloperName + '_' + apiName).abbreviate(80),
                Commission_Plan_Developer_Name__c = planDeveloperName,
                Field_API_Name__c = apiName,
                Object_API_Name__c = 'Representative_Commission__c',
                Sort_Order__c = i + 1
            ));
        }
        if (!newConfigs.isEmpty()) {
            insert newConfigs;
        }
    }

    // Returns commission tiers for the given plan, ordered by lower bound.
    // Fetches all CMT tiers and filters in Apex because MetadataRelationship
    // fields cannot be used in SOQL WHERE clauses.
    @AuraEnabled(cacheable=true)
    public static List<TierInfo> getTiersForPlan(String planDeveloperName) {
        List<TierInfo> tiers = new List<TierInfo>();
        if (String.isBlank(planDeveloperName)) return tiers;

        for (RC_Commission_Tier__mdt tier : [
            SELECT Commission_Plan__r.DeveloperName,
                   Lowest_of_Funded_Unit_Against_Eligible__c,
                   Upper_of_Funded_Units_Against_Eligible__c,
                   Plan_Tier_Payout__c,
                   Payout_Type__c
            FROM RC_Commission_Tier__mdt
            ORDER BY Lowest_of_Funded_Unit_Against_Eligible__c ASC NULLS LAST
        ]) {
            if (tier.Commission_Plan__r.DeveloperName == planDeveloperName) {
                tiers.add(new TierInfo(
                    tier.Lowest_of_Funded_Unit_Against_Eligible__c,
                    tier.Upper_of_Funded_Units_Against_Eligible__c,
                    tier.Plan_Tier_Payout__c,
                    tier.Payout_Type__c
                ));
            }
        }
        return tiers;
    }

    public class TierInfo {
        @AuraEnabled public Decimal lower      { get; set; }
        @AuraEnabled public Decimal upper      { get; set; }
        @AuraEnabled public Decimal payout     { get; set; }
        @AuraEnabled public String  payoutType { get; set; }

        public TierInfo(Decimal lower, Decimal upper, Decimal payout, String payoutType) {
            this.lower      = lower;
            this.upper      = upper;
            this.payout     = payout;
            this.payoutType = payoutType;
        }
    }

    // Wrapper for field descriptor data passed to LWC
    public class FieldInfo implements Comparable {
        @AuraEnabled public String  apiName    { get; set; }
        @AuraEnabled public String  label      { get; set; }
        @AuraEnabled public Boolean isCalcField { get; set; }

        public FieldInfo(String apiName, String label, Boolean isCalcField) {
            this.apiName     = apiName;
            this.label       = label;
            this.isCalcField = isCalcField;
        }

        public Integer compareTo(Object other) {
            return this.label.compareTo(((FieldInfo) other).label);
        }
    }
}
