// recordContextPrompt.js
import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecordContext from '@salesforce/apex/RecordContextController.getRecordContext';
import processPrompt from '@salesforce/apex/RecordContextController.processPrompt';

export default class RecordContextPrompt extends LightningElement {
    @api recordId;
    @track prompt = '';
    @track response = '';
    @track error = '';
    @track isProcessing = false;
    @track showResponse = false;
    @track debugInfo = false; // Add a flag for showing debug info if needed

    recordContext;

    // Handle changes to the prompt textarea
    handlePromptChange(event) {
        this.prompt = event.target.value;
    }

    // Handle send button click
    handleSendPrompt() {
        if (!this.prompt || this.prompt.trim() === '') {
            this.showToast('Error', 'Please enter a prompt', 'error');
            return;
        }

        this.isProcessing = true;
        this.error = '';
        this.showResponse = false;

        // Call Apex method to process the prompt
        processPrompt({ recordId: this.recordId, prompt: this.prompt })
            .then(result => {
                this.response = result;
                this.showResponse = true;
                this.isProcessing = false;
                console.log('Process prompt successful');
            })
            .catch(error => {
                this.handleError(error);
                this.isProcessing = false;
            });
    }

    // Handle errors
    handleError(error) {
        let errorMessage = 'Unknown error';
        if (error.body) {
            if (error.body.message) {
                errorMessage = error.body.message;
            } else if (typeof error.body === 'string') {
                errorMessage = error.body;
            }
        } else if (error.message) {
            errorMessage = error.message;
        }
        
        console.error('Error in RecordContextPrompt: ', errorMessage);
        this.error = errorMessage;
        this.showToast('Error', errorMessage, 'error');
    }

    // Show toast notification
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }
}