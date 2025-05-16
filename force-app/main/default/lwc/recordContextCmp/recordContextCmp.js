import { LightningElement, api, wire, track } from 'lwc';
import { getRecordUi } from 'lightning/uiRecordApi';
import { getRelatedListsInfo } from 'lightning/uiRelatedListApi';
import { NavigationMixin } from 'lightning/navigation';
import getRecordContext from '@salesforce/apex/RecordContextController.getRecordContext';
import processPrompt from '@salesforce/apex/RecordContextController.processPrompt';

export default class RecordContextComponent extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    
    @track userPrompt = '';
    @track displayFields = [];
    @track relatedLists = [];
    @track response = '';
    @track isLoading = false;
    @track urlParams = {};

    // Wire to get record UI data
    @wire(getRecordUi, { recordIds: '$recordId', layoutTypes: ['Full'], modes: ['View'] })
    wiredRecordUi({ error, data }) {
        if (data) this.processWireData(data);
        else if (error) this.handleError(error);
    }

    connectedCallback() {
        this.extractUrlParameters();
        this.loadRecordContext();
    }

    async loadRecordContext() {
        if (!this.recordId) return;
        
        this.isLoading = true;
        try {
            const result = await getRecordContext({ recordId: this.recordId });
            this.processApexData(result);
        } catch (error) {
            this.handleError(error);
        }
        this.isLoading = false;
    }

    processApexData(data) {
        if (!data) return;

        // Process main record
        this.objectApiName = data.objectApiName;
        this.displayFields = this.formatRecordFields(data.record);
        
        // Process related records
        this.relatedLists = this.formatRelatedLists(data.relatedRecords);
    }

    formatRecordFields(record) {
        return Object.keys(record)
            .filter(field => field !== 'attributes')
            .map(field => ({
                key: field,
                label: this.formatLabel(field),
                value: this.formatValue(record[field]),
                apiName: field
            }));
    }

    formatRelatedLists(relatedRecords) {
        const lists = [];
        for (const [listName, records] of Object.entries(relatedRecords)) {
            if (records?.length > 0) {
                lists.push({
                    name: listName,
                    label: this.formatListLabel(listName),
                    count: records.length,
                    records: records,
                    columns: this.generateColumns(records[0])
                });
            }
        }
        return lists;
    }

    generateColumns(firstRecord) {
        const columns = Object.keys(firstRecord)
            .filter(field => field !== 'Id')
            .map(field => ({
                label: this.formatLabel(field),
                fieldName: field,
                type: 'text'
            }));

        columns.push({
            label: 'View',
            type: 'button',
            typeAttributes: {
                label: 'View',
                name: 'view_record',
                title: 'View Record',
                variant: 'base'
            }
        });

        return columns;
    }

    formatLabel(input) {
        return input
            .replace(/__c$/, '')
            .replace(/([A-Z])/g, ' $1')
            .replace(/_/g, ' ')
            .trim()
            .toLowerCase()
            .replace(/^\w/, c => c.toUpperCase());
    }

    formatValue(value) {
        if (value === null || value === undefined) return '';
        if (typeof value === 'object') return JSON.stringify(value);
        if (typeof value === 'boolean') return value ? 'Yes' : 'No';
        return String(value);
    }

    handlePromptChange(event) {
        this.userPrompt = event.target.value;
    }

    async handleSubmit() {
        if (!this.userPrompt.trim()) return;
        
        this.isLoading = true;
        try {
            this.response = await processPrompt({
                recordId: this.recordId,
                prompt: this.userPrompt
            });
        } catch (error) {
            this.handleError(error);
        }
        this.isLoading = false;
    }

    handleRowAction(event) {
        const recordId = event.detail.row.Id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    extractUrlParameters() {
        const params = new URLSearchParams(window.location.search);
        this.urlParams = Object.fromEntries(params.entries());
    }

    handleError(error) {
        const message = error.body?.message || error.message || 'Unknown error';
        this.response = `Error: ${message}`;
    }

    get hasData() {
        return this.displayFields.length > 0 || this.relatedLists.length > 0;
    }

    get showResponse() {
        return this.response && !this.isLoading;
    }
}