import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPlans           from '@salesforce/apex/CommissionPlanAdminController.getPlans';
import getAvailableFields from '@salesforce/apex/CommissionPlanAdminController.getAvailableFields';
import getConfiguredFields from '@salesforce/apex/CommissionPlanAdminController.getConfiguredFields';
import saveConfig         from '@salesforce/apex/CommissionPlanAdminController.saveConfig';

const USAGE_PERIOD_OPTIONS = [
    { label: 'Monthly',   value: 'Monthly' },
    { label: 'Quarterly', value: 'Quarterly' },
    { label: 'Annual',    value: 'Annual' }
];

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
                    const existing = configMap.get(f.apiName);
                    const isChecked = !!existing;
                    return {
                        apiName         : f.apiName,
                        label           : f.label,
                        isCalcField     : f.isCalcField,
                        checked         : isChecked,
                        expanded        : false,
                        sortOrder       : isChecked ? existing.Sort_Order__c : uncheckedOrder++,
                        // Extra config properties
                        usagePeriod     : existing?.Usage_Period__c     || 'Monthly',
                        metricType      : existing?.Metric_Type__c      || '',
                        defaultValue    : existing?.Default_Value__c    ?? null,
                        reportSource    : existing?.Report_Source__c    || '',
                        reportFieldLabel: existing?.Report_Field_Label__c || ''
                    };
                });
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
            fieldApiName    : f.apiName,
            usagePeriod     : f.usagePeriod     || 'Monthly',
            metricType      : f.metricType      || '',
            defaultValue    : f.defaultValue,
            reportSource    : f.reportSource    || '',
            reportFieldLabel: f.reportFieldLabel || ''
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
