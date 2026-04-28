public with sharing class CommissionPlanAdminController {

    // Returns all commission plans from the custom object
    @AuraEnabled(cacheable=true)
    public static List<PlanWrapper> getPlans() {
        List<PlanWrapper> result = new List<PlanWrapper>();
        for (Commission_Plan__c p : [
            SELECT Name, DeveloperName__c, Payout_Type__c
            FROM Commission_Plan__c
            ORDER BY Name
        ]) {
            result.add(new PlanWrapper(p.Name, p.DeveloperName__c, p.Payout_Type__c));
        }
        return result;
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

    // Returns full config records for the given plan in display order,
    // including all extra metadata fields (Usage Period, Metric Type, etc.)
    @AuraEnabled(cacheable=true)
    public static List<Commission_Plan_Field_Config__c> getConfiguredFields(String planDeveloperName) {
        return [
            SELECT Field_API_Name__c, Sort_Order__c,
                   Usage_Period__c, Metric_Type__c, Default_Value__c,
                   Report_Source__c, Report_Field_Label__c,
                   Calculation_Expression__c
            FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = :planDeveloperName
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];
    }

    // Replaces all config records for the plan with the new field selection + metadata.
    // fieldConfigJson is a JSON array of FieldConfigItem objects.
    @AuraEnabled
    public static void saveConfig(String planDeveloperName, String fieldConfigJson) {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(fieldConfigJson);

        // Delete existing config records for this plan
        List<Commission_Plan_Field_Config__c> existing = [
            SELECT Id FROM Commission_Plan_Field_Config__c
            WHERE Commission_Plan_Developer_Name__c = :planDeveloperName
        ];
        if (!existing.isEmpty()) delete existing;

        // Insert new config records with all metadata
        List<Commission_Plan_Field_Config__c> newConfigs = new List<Commission_Plan_Field_Config__c>();
        for (Integer i = 0; i < raw.size(); i++) {
            Map<String, Object> item = (Map<String, Object>) raw[i];
            String apiName = (String) item.get('fieldApiName');

            Commission_Plan_Field_Config__c cfg = new Commission_Plan_Field_Config__c(
                Name                              = (planDeveloperName + '_' + apiName).abbreviate(80),
                Commission_Plan_Developer_Name__c = planDeveloperName,
                Field_API_Name__c                 = apiName,
                Object_API_Name__c                = 'Representative_Commission__c',
                Sort_Order__c                     = i + 1,
                Usage_Period__c                   = (String)  item.get('usagePeriod'),
                Metric_Type__c                    = (String)  item.get('metricType'),
                Report_Source__c                  = (String)  item.get('reportSource'),
                Report_Field_Label__c             = (String)  item.get('reportFieldLabel'),
                Calculation_Expression__c         = (String)  item.get('calculationExpression')
            );

            // Default_Value__c supports 4 decimal places
            Object defVal = item.get('defaultValue');
            if (defVal != null) {
                cfg.Default_Value__c = Decimal.valueOf(String.valueOf(defVal));
            }

            newConfigs.add(cfg);
        }

        if (!newConfigs.isEmpty()) insert newConfigs;
    }

    // Creates or updates a commission plan by DeveloperName__c (upsert).
    @AuraEnabled
    public static void savePlan(String name, String developerName, String payoutType) {
        if (String.isBlank(name) || String.isBlank(developerName)) {
            throw new AuraHandledException('Plan Name and Developer Name are required.');
        }
        Commission_Plan__c plan = new Commission_Plan__c(
            Name             = name,
            DeveloperName__c = developerName,
            Payout_Type__c   = payoutType
        );
        upsert plan DeveloperName__c;
    }

    // Adds a new tier to the given plan.
    @AuraEnabled
    public static void saveTier(String planDeveloperName, Decimal lower, Decimal upper, Decimal payout, String payoutType) {
        List<Commission_Plan__c> plans = [SELECT Id FROM Commission_Plan__c WHERE DeveloperName__c = :planDeveloperName LIMIT 1];
        if (plans.isEmpty()) throw new AuraHandledException('Plan not found: ' + planDeveloperName);
        insert new Commission_Tier__c(
            Commission_Plan__c                        = plans[0].Id,
            Lowest_of_Funded_Unit_Against_Eligible__c = lower,
            Upper_of_Funded_Units_Against_Eligible__c = upper,
            Plan_Tier_Payout__c                       = payout,
            Payout_Type__c                            = payoutType
        );
    }

    // Deletes a single tier by Id.
    @AuraEnabled
    public static void deleteTier(Id tierId) {
        delete new Commission_Tier__c(Id = tierId);
    }

    // Returns commission tiers for the given plan with record Ids (for delete support).
    @AuraEnabled(cacheable=true)
    public static List<TierInfo> getTiersForPlanWithId(String planDeveloperName) {
        List<TierInfo> tiers = new List<TierInfo>();
        if (String.isBlank(planDeveloperName)) return tiers;
        for (Commission_Tier__c tier : [
            SELECT Id, Lowest_of_Funded_Unit_Against_Eligible__c,
                   Upper_of_Funded_Units_Against_Eligible__c,
                   Plan_Tier_Payout__c, Payout_Type__c
            FROM Commission_Tier__c
            WHERE Commission_Plan__r.DeveloperName__c = :planDeveloperName
            ORDER BY Lowest_of_Funded_Unit_Against_Eligible__c ASC NULLS LAST
        ]) {
            TierInfo t = new TierInfo(
                tier.Lowest_of_Funded_Unit_Against_Eligible__c,
                tier.Upper_of_Funded_Units_Against_Eligible__c,
                tier.Plan_Tier_Payout__c,
                tier.Payout_Type__c
            );
            t.id = tier.Id;
            tiers.add(t);
        }
        return tiers;
    }

    // Returns report names for a list of report IDs.
    // Used by the Report Sources Reference widget to display human-readable names.
    @AuraEnabled(cacheable=true)
    public static List<ReportInfo> getReportNames(List<String> reportIds) {
        List<ReportInfo> results = new List<ReportInfo>();
        if (reportIds == null || reportIds.isEmpty()) return results;

        for (Report r : [SELECT Id, Name FROM Report WHERE Id IN :reportIds]) {
            results.add(new ReportInfo(String.valueOf(r.Id), r.Name));
        }
        return results;
    }

    public class ReportInfo {
        @AuraEnabled public String reportId   { get; set; }
        @AuraEnabled public String reportName { get; set; }

        public ReportInfo(String reportId, String reportName) {
            this.reportId   = reportId;
            this.reportName = reportName;
        }
    }

    // Returns commission tiers for the given plan, ordered by lower bound.
    @AuraEnabled(cacheable=true)
    public static List<TierInfo> getTiersForPlan(String planDeveloperName) {
        List<TierInfo> tiers = new List<TierInfo>();
        if (String.isBlank(planDeveloperName)) return tiers;

        for (Commission_Tier__c tier : [
            SELECT Lowest_of_Funded_Unit_Against_Eligible__c,
                   Upper_of_Funded_Units_Against_Eligible__c,
                   Plan_Tier_Payout__c,
                   Payout_Type__c
            FROM Commission_Tier__c
            WHERE Commission_Plan__r.DeveloperName__c = :planDeveloperName
            ORDER BY Lowest_of_Funded_Unit_Against_Eligible__c ASC NULLS LAST
        ]) {
            tiers.add(new TierInfo(
                tier.Lowest_of_Funded_Unit_Against_Eligible__c,
                tier.Upper_of_Funded_Units_Against_Eligible__c,
                tier.Plan_Tier_Payout__c,
                tier.Payout_Type__c
            ));
        }
        return tiers;
    }

    public class TierInfo {
        @AuraEnabled public String  id         { get; set; }
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

    // Wrapper that exposes Label/DeveloperName shape matching the old metadata API — keeps LWC unchanged
    public class PlanWrapper {
        @AuraEnabled public String Label       { get; set; }
        @AuraEnabled public String DeveloperName { get; set; }
        @AuraEnabled public String payoutType  { get; set; }

        public PlanWrapper(String label, String developerName, String payoutType) {
            this.Label         = label;
            this.DeveloperName = developerName;
            this.payoutType    = payoutType;
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
