import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPlans            from '@salesforce/apex/CommissionPlanAdminController.getPlans';
import getAvailableFields  from '@salesforce/apex/CommissionPlanAdminController.getAvailableFields';
import getConfiguredFields from '@salesforce/apex/CommissionPlanAdminController.getConfiguredFields';
import saveConfig          from '@salesforce/apex/CommissionPlanAdminController.saveConfig';
import getReportNames      from '@salesforce/apex/CommissionPlanAdminController.getReportNames';

const USAGE_PERIOD_OPTIONS = [
    { label: 'Monthly',   value: 'Monthly' },
    { label: 'Quarterly', value: 'Quarterly' },
    { label: 'Annual',    value: 'Annual' }
];

// Tier output fields — value set by tier metadata lookup, not by an expression
const TIER_SYSTEM_FIELDS = new Set([
    'Tier_Lower_Calc__c',
    'Tier_Upper_Calc__c',
    'Tier_Payout_Calc__c'
]);

// Default expressions matching the existing Apex hardcoded logic.
// Applied only when a calc field is first added to a plan (no existing config record).
const DEFAULT_EXPRESSIONS = {
    'Attainment_Calc__c'                    : '{Funded_Units__c} / {Eligible_Units__c} * 100',
    'Brokered_Commission_Calc__c'           : '{Brokered_Margin_Amount__c} * ({Brokered_Margin__c} / 100)',
    'Team_Margin_Commission_Calc__c'        : '{Team_Margin_Amount__c} * ({Team_Margin__c} / 100)',
    'Termed_Deal_Commission_Calc__c'        : '{Termed_Deal_Margin_Amount__c} * ({Termed_Deal_Margin_Percentage__c} / 100)',
    'Cardiff_Commission_Calc__c'            : '{Cardiff_Deal_Margin_Amount__c} * ({Cardiff_Deal_Margin__c} / 100)',
    'Day60_Termed_Commission_Calc__c'       : '{Day60_Plus_Termed_Margin_Amount__c} * ({Day60_Plus_Termed_Margin__c} / 100)',
    'Team_Closing_Ratio_Commission_Calc__c' : 'IF({Team_Closing_Ratio__c} > 75, 3000, IF({Team_Closing_Ratio__c} >= 70, 1000, 0))',
    'Commission_Amount_Calc__c'             : '{Brokered_Commission_Calc__c} + {Team_Closing_Ratio_Commission_Calc__c} + {Team_Margin_Commission_Calc__c} + {Deal_Margin_Commission_Calc__c} + {Termed_Deal_Commission_Calc__c} + {Cardiff_Commission_Calc__c} + {Day60_Termed_Commission_Calc__c} + {Proposed_Comp_Commission_Calc__c}',
    'Final_Commission_Calc__c'              : '{Commission_Amount_Calc__c} + {Commission_Adjustment__c}'
};

// Plan-specific overrides — take priority over DEFAULT_EXPRESSIONS above
const PLAN_SPECIFIC_EXPRESSIONS = {
    'Proposed_Comp' : {
        'Attainment_Calc__c'                 : '{Approve_to_Fund_Ratio__c}',
        'Deal_Margin_Commission_Calc__c'     : '{Base_Commission__c} * ({Tier_Payout_Calc__c} / 100)',
        'Proposed_Comp_Commission_Calc__c'   : '{Proposed_Comp_Margin__c} * ({Tier_Payout_Calc__c} / 100) + {X50K_Funded__c} + {X50KPlus_Funded__c}'
    },
    'Brokered_PM_Comp' : {
        'Deal_Margin_Commission_Calc__c'     : '{Base_Commission__c} * ({Tier_Payout_Calc__c} / 100)'
    },
    'Brokered_CRR_Comp' : {
        'Deal_Margin_Commission_Calc__c'     : '{Tier_Payout_Calc__c}'
    },
    'Assistant_Renewals_Director_Comp' : {
        'Deal_Margin_Commission_Calc__c'     : '{Tier_Payout_Calc__c}'
    },
    'Cardiff_PM_Comp' : {
        'Deal_Margin_Commission_Calc__c'     : '{Tier_Payout_Calc__c}'
    },
    'CRF_CRR_Comp' : {
        'Deal_Margin_Commission_Calc__c'     : '{Tier_Payout_Calc__c}'
    }
};

function getDefaultExpression(apiName, planDeveloperName) {
    const planOverrides = PLAN_SPECIFIC_EXPRESSIONS[planDeveloperName] || {};
    return planOverrides[apiName] || DEFAULT_EXPRESSIONS[apiName] || '';
}

const METRIC_TYPE_OPTIONS = [
    { label: '-- None --',                        value: '' },
    { label: 'Month Start Target',                value: 'Month_Start_Target' },
    { label: 'Month End Target',                  value: 'Month_End_Target' },
    { label: 'Tier Lookup Input',                 value: 'Tier_Lookup_Input' },
    { label: 'Tier Lookup Output $',              value: 'Tier_Lookup_Output_Dollar' },
    { label: 'Tier Lookup Output Assumption',     value: 'Tier_Lookup_Output_Assumption' },
    { label: 'User Input Assumption',             value: 'User_Input_Assumption' },
    { label: 'Calculation Input Assumption',      value: 'Calculation_Input_Assumption' },
    { label: 'User Input Commission Adjustment',  value: 'User_Input_Commission_Adjustment' },
    { label: 'Informational Output Value',        value: 'Informational_Output_Value' },
    { label: 'Commission $ Output Value',         value: 'Commission_Dollar_Output_Value' }
];

export default class CommissionPlanAdmin extends LightningElement {

    @track planOptions      = [];
    @track fieldList        = [];
    @track reportNameMap    = {};
    @track selectedPlan     = '';
    @track isLoading        = false;
    @track isSaving         = false;

    usagePeriodOptions = USAGE_PERIOD_OPTIONS;
    metricTypeOptions  = METRIC_TYPE_OPTIONS;

    // ── Getters ───────────────────────────────────────────────────────────────

    get showFields() {
        return this.selectedPlan && !this.isLoading && this.fieldList.length > 0;
    }

    get showEmpty() {
        return this.selectedPlan && !this.isLoading && this.fieldList.length === 0;
    }

    get reportSourceFields() {
        return this.fieldList
            .filter(f => f.reportSource)
            .map(f => ({
                apiName      : f.apiName,
                fieldLabel   : f.label,
                reportId     : f.reportSource,
                reportName   : this.reportNameMap[f.reportSource] || f.reportSource,
                measureLabel : f.reportFieldLabel || '—',
                reportUrl    : '/lightning/r/Report/' + f.reportSource + '/view'
            }));
    }

    get hasReportSources() {
        return this.reportSourceFields.length > 0;
    }

    get dataEntryFields() {
        return this.fieldList
            .filter(f => !f.isCalcField)
            .slice()
            .sort((a, b) => a.sortOrder - b.sortOrder);
    }

    get calcFields() {
        return this.fieldList
            .filter(f => f.isCalcField)
            .slice()
            .sort((a, b) => a.sortOrder - b.sortOrder);
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        getPlans()
            .then(plans => {
                this.planOptions = plans.map(p => ({ label: p.Label, value: p.DeveloperName }));
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'));
    }

    // ── Plan selection ────────────────────────────────────────────────────────

    handlePlanChange(event) {
        this.selectedPlan = event.detail.value;
        this.loadFields();
    }

    loadFields() {
        this.isLoading = true;
        this.fieldList = [];
        this.reportNameMap = {};

        Promise.all([
            getAvailableFields(),
            getConfiguredFields({ planDeveloperName: this.selectedPlan })
        ])
            .then(([available, configured]) => {
                // Build a map of existing config by fieldApiName
                const configMap = new Map(
                    configured.map(c => [c.Field_API_Name__c, c])
                );

                let uncheckedOrder = configured.length + 1;

                this.fieldList = available.map(f => {
                    const existing   = configMap.get(f.apiName);
                    const isChecked  = !!existing;
                    // Tier system fields show in the list but have no expression — value set by tier lookup
                    const isExpressionField = f.isCalcField && !TIER_SYSTEM_FIELDS.has(f.apiName);
                    // For expression fields, fall back to the Apex-equivalent default when no expression is saved yet
                    const defaultExpr = isExpressionField
                        ? getDefaultExpression(f.apiName, this.selectedPlan)
                        : '';
                    return {
                        apiName               : f.apiName,
                        label                 : f.label,
                        displayLabel          : f.label + ' (' + f.apiName + ')',
                        isCalcField           : f.isCalcField,
                        isExpressionField     : isExpressionField,
                        checked               : isChecked,
                        expanded              : false,
                        sortOrder             : isChecked ? existing.Sort_Order__c : uncheckedOrder++,
                        // Extra config properties
                        usagePeriod           : existing?.Usage_Period__c          || 'Monthly',
                        metricType            : existing?.Metric_Type__c           || '',
                        defaultValue          : existing?.Default_Value__c         ?? null,
                        reportSource          : existing?.Report_Source__c         || '',
                        reportFieldLabel      : existing?.Report_Field_Label__c    || '',
                        calculationExpression : existing?.Calculation_Expression__c || defaultExpr
                    };
                });

                // Fetch report names for any fields that have a report source configured
                const reportIds = [...new Set(
                    this.fieldList.map(f => f.reportSource).filter(id => !!id)
                )];
                if (reportIds.length > 0) {
                    return getReportNames({ reportIds });
                }
                return [];
            })
            .then(reportInfoList => {
                if (reportInfoList && reportInfoList.length > 0) {
                    const nameMap = {};
                    reportInfoList.forEach(r => { nameMap[r.reportId] = r.reportName; });
                    this.reportNameMap = nameMap;
                }
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'))
            .finally(() => { this.isLoading = false; });
    }

    // ── Field toggle & expand ─────────────────────────────────────────────────

    handleFieldToggle(event) {
        const apiName = event.target.dataset.api;
        const checked = event.target.checked;
        this.fieldList = this.fieldList.map(f =>
            f.apiName === apiName
                ? { ...f, checked, expanded: checked ? f.expanded : false }
                : f
        );
    }

    handleToggleExpand(event) {
        const apiName = event.currentTarget.dataset.api;
        this.fieldList = this.fieldList.map(f =>
            f.apiName === apiName ? { ...f, expanded: !f.expanded } : f
        );
    }

    // ── Config property handlers ──────────────────────────────────────────────

    handleUsagePeriodChange(event) {
        const apiName = event.target.dataset.api;
        this.fieldList = this.fieldList.map(f =>
            f.apiName === apiName ? { ...f, usagePeriod: event.detail.value } : f
        );
    }

    handleMetricTypeChange(event) {
        const apiName = event.target.dataset.api;
        this.fieldList = this.fieldList.map(f =>
            f.apiName === apiName ? { ...f, metricType: event.detail.value } : f
        );
    }

    handleDefaultValueChange(event) {
        const apiName = event.target.dataset.api;
        const val = event.detail.value;
        this.fieldList = this.fieldList.map(f =>
            f.apiName === apiName ? { ...f, defaultValue: val !== '' ? val : null } : f
        );
    }

    handleReportSourceChange(event) {
        const apiName = event.target.dataset.api;
        this.fieldList = this.fieldList.map(f =>
            f.apiName === apiName ? { ...f, reportSource: event.detail.value } : f
        );
    }

    handleReportFieldLabelChange(event) {
        const apiName = event.target.dataset.api;
        this.fieldList = this.fieldList.map(f =>
            f.apiName === apiName ? { ...f, reportFieldLabel: event.detail.value } : f
        );
    }

    handleCalculationExpressionChange(event) {
        const apiName = event.target.dataset.api;
        this.fieldList = this.fieldList.map(f =>
            f.apiName === apiName ? { ...f, calculationExpression: event.detail.value } : f
        );
    }

    // ── Move up / down ────────────────────────────────────────────────────────

    handleMoveUp(event)   { this._move(event.target.dataset.api, -1); }
    handleMoveDown(event) { this._move(event.target.dataset.api,  1); }

    _move(apiName, direction) {
        const field = this.fieldList.find(f => f.apiName === apiName);
        if (!field) return;

        const section = this.fieldList
            .filter(f => f.isCalcField === field.isCalcField)
            .slice()
            .sort((a, b) => a.sortOrder - b.sortOrder);

        const idx     = section.findIndex(f => f.apiName === apiName);
        const swapIdx = idx + direction;
        if (swapIdx < 0 || swapIdx >= section.length) return;

        const currentOrder = section[idx].sortOrder;
        const swapOrder    = section[swapIdx].sortOrder;

        this.fieldList = this.fieldList.map(f => {
            if (f.apiName === section[idx].apiName)    return { ...f, sortOrder: swapOrder };
            if (f.apiName === section[swapIdx].apiName) return { ...f, sortOrder: currentOrder };
            return f;
        });
    }

    // ── Save ──────────────────────────────────────────────────────────────────

    handleSave() {
        const ordered = [
            ...this.dataEntryFields.filter(f => f.checked),
            ...this.calcFields.filter(f => f.checked)
        ].map(f => ({
            fieldApiName          : f.apiName,
            usagePeriod           : f.isCalcField ? 'Monthly'              : (f.usagePeriod      || 'Monthly'),
            metricType            : f.isCalcField ? ''                     : (f.metricType       || ''),
            defaultValue          : f.isCalcField ? null                   : f.defaultValue,
            reportSource          : f.isCalcField ? ''                     : (f.reportSource     || ''),
            reportFieldLabel      : f.isCalcField ? ''                     : (f.reportFieldLabel || ''),
            calculationExpression : f.isCalcField ? (f.calculationExpression || '') : ''
        }));

        this.isSaving = true;
        saveConfig({
            planDeveloperName: this.selectedPlan,
            fieldConfigJson  : JSON.stringify(ordered)
        })
            .then(() => {
                this.showToast('Success', 'Configuration saved successfully.', 'success');
                // Reload to sync sortOrder from server
                this.loadFields();
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'))
            .finally(() => { this.isSaving = false; });
    }

    // ── Print ─────────────────────────────────────────────────────────────────

    handlePrint() {
        window.print();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    extractMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message)       return error.message;
        return 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
