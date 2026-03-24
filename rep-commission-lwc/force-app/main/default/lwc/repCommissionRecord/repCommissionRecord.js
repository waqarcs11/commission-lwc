import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getConfiguredFields from '@salesforce/apex/CommissionPlanAdminController.getConfiguredFields';
import getTiersForPlan from '@salesforce/apex/CommissionPlanAdminController.getTiersForPlan';
import PLAN_FIELD from '@salesforce/schema/Representative_Commission__c.Commission_Plan_Developer_Name__c';

export default class RepCommissionRecord extends NavigationMixin(LightningElement) {
    @api recordId;

    @track configuredFields = [];
    @track planDeveloperName;
    @track isLoading = true;
    @track _showForm = true; // toggled to force form remount after save
    @track tiers = [];

    // Step 1: wire the record to read the plan field
    @wire(getRecord, { recordId: '$recordId', fields: [PLAN_FIELD] })
    wiredRecord({ error, data }) {
        if (data) {
            this.planDeveloperName = getFieldValue(data, PLAN_FIELD);
        } else if (error) {
            this.isLoading = false;
        }
    }

    // Step 2: wire configured fields for the plan (only runs once planDeveloperName is set)
    @wire(getConfiguredFields, { planDeveloperName: '$planDeveloperName' })
    wiredFields({ error, data }) {
        if (data !== undefined) {
            this.configuredFields = data;
            this.isLoading = false;
        } else if (error) {
            this.configuredFields = [];
            this.isLoading = false;
        }
    }

    // Step 3: wire tiers for the plan
    @wire(getTiersForPlan, { planDeveloperName: '$planDeveloperName' })
    wiredTiers({ error, data }) {
        if (data) {
            this.tiers = data;
        } else if (error) {
            this.tiers = [];
        }
    }

    get hasTiers() {
        return this.tiers && this.tiers.length > 0;
    }

    get configuredInputFields() {
        return (this.configuredFields || []).filter(f => !f.toLowerCase().endsWith('_calc__c'));
    }

    get configuredCalcFields() {
        return (this.configuredFields || []).filter(f => f.toLowerCase().endsWith('_calc__c'));
    }

    get hasConfiguredFields() {
        return this.configuredInputFields.length > 0;
    }

    get hasCalcFields() {
        return this.configuredCalcFields.length > 0;
    }

    get noFieldsConfigured() {
        return !this.isLoading && !this.hasConfiguredFields;
    }

    handleSuccess() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Saved',
            message: 'Commission record updated.',
            variant: 'success'
        }));
        // Notify LDS the record changed, then remount the form so
        // lightning-output-field picks up the fresh calc values from the trigger.
        notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        this._showForm = false;
        Promise.resolve().then(() => { this._showForm = true; });
    }

    handleError(event) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Save failed',
            message: event.detail.detail,
            variant: 'error'
        }));
    }

    handleBackToList() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Representative_Commission__c',
                actionName: 'list'
            },
            state: { filterName: 'Recent' }
        });
    }
}
