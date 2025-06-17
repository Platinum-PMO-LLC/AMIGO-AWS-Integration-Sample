public class S3ExportBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    
    private String objectName;
    private Id queueId;
    private Integer chunkSize;
    private Integer recordsProcessed = 0;
    private Integer filesCreated = 0;
    private List<String> errorMessages = new List<String>();

    public S3ExportBatch(String queueId, String objectName, Integer chunkSize) {
        this.queueId = queueId;
        this.objectName = objectName;
        this.chunkSize = chunkSize ?? 5000;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {

        S3ExportLogger.logBatchStart(queueId, bc.getJobId(), objectName);

        String fieldsList = [SELECT Field_List__c 
                            FROM S3_Export_Config__mdt 
                            WHERE Object_Name__c = :objectName 
                            LIMIT 1].Field_List__c;

        String query = 'SELECT ' + fieldsList + ' FROM ' + objectName;
        
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> records) {
        try {
            String jsonData = JSON.serialize(records);
            
            String fileName = generateFileName();
            System.debug('jsonData --> ' + jsonData);

            // Upload to S3
            S3CalloutService.uploadFile(fileName, jsonData, 'application/json');
            
            recordsProcessed += records.size();
            filesCreated++;
            
            System.debug('queueId --> ' +queueId);
            S3ExportLogger.logBatchSuccess(queueId, bc.getJobId(), records.size(), fileName);
            
        } catch(Exception e) {
            String errorMsg = 'Batch execution failed: ' + e.getMessage();
            errorMessages.add(errorMsg);
            S3ExportLogger.logBatchError(queueId, bc.getJobId(), errorMsg);
        }
    }

    public void finish(Database.BatchableContext bc) {
        AsyncApexJob job = [
            SELECT Status, NumberOfErrors, ExtendedStatus 
            FROM AsyncApexJob 
            WHERE Id = :bc.getJobId()
        ];
        
        if(job.Status == 'Completed' && job.NumberOfErrors == 0 && errorMessages.isEmpty()) {
            // Update queue as completed
            S3_Export_Queue__c queueItem = new S3_Export_Queue__c(
                Id = queueId,
                Status__c = 'Completed',
                Completed_Date__c = System.now(),
                Records_Processed__c = recordsProcessed,
                Files_Created__c = filesCreated
            );
            update queueItem;
            
        } else {
            // Mark as failed and prepare for retry
            String errorSummary = String.join(errorMessages, '; ');
            if(String.isBlank(errorSummary)) {
                errorSummary = job.ExtendedStatus;
            }
            
            S3ExportQueueManager.updateQueueStatus(queueId, 'Failed', errorSummary);
        }
        
        S3ExportLogger.logBatchFinish(queueId, bc.getJobId(), job.Status, recordsProcessed, filesCreated);
    }

    @TestVisible
    private String generateFileName() {
        return objectName +'.json';
    }
}