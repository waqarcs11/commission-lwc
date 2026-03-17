import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPlans from '@salesforce/apex/CommissionPlanAdminController.getPlans';
import getAvailableFields from '@salesforce/apex/CommissionPlanAdminController.getAvailableFields';
import getConfiguredFields from '@salesforce/apex/CommissionPlanAdminController.getConfiguredFields';
import saveConfig from '@salesforce/apex/CommissionPlanAdminController.saveConfig';

export default class CommissionPlanAdmin extends LightningElement {
    @track planOptions = [];
    @track fieldList = [];
    @track selectedPlan = '';
    @track isLoading = false;
    @track isSaving = false;

    // Show the field list only when a plan is selected and not currently loading
    get showFields() {
        return this.selectedPlan && !this.isLoading && this.fieldList.length > 0;
    }

    // Show empty state when plan is selected, load is done, but no fields came back
    get showEmpty() {
        return this.selectedPlan && !this.isLoading && this.fieldList.length === 0;
    }

    connectedCallback() {
        this.loadPlans();
    }

    loadPlans() {
        this.isLoading = true;
        getPlans()
            .then(plans => {
                this.planOptions = plans.map(p => ({
                    label: p.Label,
                    value: p.DeveloperName
                }));
            })
            .catch(error => {
                this.showToast('Error', this.extractMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

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
                const configuredSet = new Set(configured);
                this.fieldList = available.map(f => ({
                    apiName: f.apiName,
                    label: f.label,
                    checked: configuredSet.has(f.apiName)
                }));
            })
            .catch(error => {
                this.showToast('Error', this.extractMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleFieldToggle(event) {
        const apiName = event.target.dataset.api;
        const checked = event.target.checked;
        this.fieldList = this.fieldList.map(f =>
            f.apiName === apiName ? { ...f, checked } : f
        );
    }

    handleSave() {
        const selectedFields = this.fieldList
            .filter(f => f.checked)
            .map(f => f.apiName);

        this.isSaving = true;
        saveConfig({
            planDeveloperName: this.selectedPlan,
            fieldApiNames: selectedFields
        })
            .then(() => {
                this.showToast('Success', 'Configuration saved successfully.', 'success');
            })
            .catch(error => {
                this.showToast('Error', this.extractMessage(error), 'error');
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    extractMessage(error) {
        return (error && error.body && error.body.message) ? error.body.message : 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
