import { LightningElement, track } from 'lwc';
import makeRealCallout from '@salesforce/apex/AWSLambdaActualCallout.makeRealCallout';
import makeDefaultCallout from '@salesforce/apex/AWSLambdaActualCallout.makeDefaultCallout';
import getFullResponse from '@salesforce/apex/AWSLambdaActualCallout.getFullResponse';
import getResponseMessage from '@salesforce/apex/AWSLambdaActualCallout.getResponseMessage';

export default class AwsLambdaDemo extends LightningElement {
    @track num1 = 15;
    @track num2 = 20;
    @track result;
    @track fullResponse;
    @track responseMessage;
    @track errorMessage;
    @track isLoading = false;

    handleNum1Change(event) {
        this.num1 = parseInt(event.target.value, 10) || 0;
    }

    handleNum2Change(event) {
        this.num2 = parseInt(event.target.value, 10) || 0;
    }

    callWithCustomValues() {
        this.isLoading = true;
        this.result = undefined;
        this.fullResponse = undefined;
        this.responseMessage = undefined;
        this.errorMessage = undefined;

        // Promise chain to first get the sum result
        makeRealCallout({ num1: this.num1, num2: this.num2 })
            .then(result => {
                this.result = result;
                
                // Then get the message
                return getResponseMessage({ num1: this.num1, num2: this.num2 });
            })
            .then(message => {
                this.responseMessage = message;
                this.isLoading = false;
            })
            .catch(error => {
                this.errorMessage = 'Error making callout: ' + (error.body ? error.body.message : error.message);
                this.isLoading = false;
            });
    }

    callWithDefaultValues() {
        this.isLoading = true;
        this.result = undefined;
        this.fullResponse = undefined;
        this.responseMessage = undefined;
        this.errorMessage = undefined;

        makeDefaultCallout()
            .then(result => {
                this.result = result;
                
                // Get message using the default values
                return getResponseMessage({ num1: 15, num2: 20 });
            })
            .then(message => {
                this.responseMessage = message;
                this.isLoading = false;
            })
            .catch(error => {
                this.errorMessage = 'Error making callout: ' + (error.body ? error.body.message : error.message);
                this.isLoading = false;
            });
    }

    getDetailedResponse() {
        this.isLoading = true;
        this.result = undefined;
        this.fullResponse = undefined;
        this.responseMessage = undefined;
        this.errorMessage = undefined;

        getFullResponse({ num1: this.num1, num2: this.num2 })
            .then(response => {
                this.fullResponse = response;
                this.isLoading = false;
            })
            .catch(error => {
                this.errorMessage = 'Error making callout: ' + (error.body ? error.body.message : error.message);
                this.isLoading = false;
            });
    }
} 