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

    get showFields() {
        return this.selectedPlan && !this.isLoading && this.fieldList.length > 0;
    }

    get showEmpty() {
        return this.selectedPlan && !this.isLoading && this.fieldList.length === 0;
    }

    // Sorted within each section; checked fields first (in their saved order), then unchecked
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
                // configured comes back in Sort_Order__c order; use index as sort order
                const configuredIndexMap = new Map(configured.map((apiName, idx) => [apiName, idx + 1]));

                // unchecked fields get a sort order after all checked ones
                let uncheckedOrder = configured.length + 1;

                this.fieldList = available.map(f => {
                    const isChecked = configuredIndexMap.has(f.apiName);
                    return {
                        apiName: f.apiName,
                        label: f.label,
                        isCalcField: f.isCalcField,
                        checked: isChecked,
                        sortOrder: isChecked ? configuredIndexMap.get(f.apiName) : uncheckedOrder++
                    };
                });
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

    handleMoveUp(event) {
        this._move(event.target.dataset.api, -1);
    }

    handleMoveDown(event) {
        this._move(event.target.dataset.api, 1);
    }

    _move(apiName, direction) {
        // Get the section (data entry or calc) the field belongs to, sorted
        const field = this.fieldList.find(f => f.apiName === apiName);
        if (!field) return;

        const section = this.fieldList
            .filter(f => f.isCalcField === field.isCalcField)
            .slice()
            .sort((a, b) => a.sortOrder - b.sortOrder);

        const idx = section.findIndex(f => f.apiName === apiName);
        const swapIdx = idx + direction;
        if (swapIdx < 0 || swapIdx >= section.length) return;

        // Swap sortOrder values between the two fields
        const currentOrder = section[idx].sortOrder;
        const swapOrder   = section[swapIdx].sortOrder;

        this.fieldList = this.fieldList.map(f => {
            if (f.apiName === section[idx].apiName)   return { ...f, sortOrder: swapOrder };
            if (f.apiName === section[swapIdx].apiName) return { ...f, sortOrder: currentOrder };
            return f;
        });
    }

    handleSave() {
        // Collect checked fields from each section in their current sort order,
        // data entry first then calc fields
        const ordered = [
            ...this.dataEntryFields.filter(f => f.checked),
            ...this.calcFields.filter(f => f.checked)
        ].map(f => f.apiName);

        this.isSaving = true;
        saveConfig({
            planDeveloperName: this.selectedPlan,
            fieldApiNames: ordered
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
